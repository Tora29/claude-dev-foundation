#!/bin/bash
set -u
here=$(dirname "$0"); . "$here/lib.sh"
umask 077
input=$(cat)
cd "$(jq -r .cwd <<<"$input")" || exit 0
logs="$HOME/.claude-logs"; mkdir -p "$logs/qa-state" "$logs/qa-reports"
last_jsonl() { awk '/^```jsonl[[:space:]]*$/{b="";on=1;next} /^```[[:space:]]*$/{if(on){last=b;on=0};next} on{b=b $0 "\n"} END{printf "%s",last}'; }
# 1回の QA でフックが2回呼ばれることがある（文章で答えて止まったときと、SubagentHandback で返したあと）。
# 同じエージェントの結果は1回だけ保存する。2回とも保存すると、指摘が重なり、blocker の連続回数を2回数えるため
agent=$(jq -r '.agent_id // "" | select(test("^[A-Za-z0-9_-]+$")) // ""' <<<"$input")
mark=""; [ -n "$agent" ] && mark="$logs/qa-state/saved/$agent"
[ -n "$mark" ] && [ -f "$mark" ] && exit 0
msg=$(jq -r '.last_assistant_message // ""' <<<"$input")
block=$(last_jsonl <<<"$msg")
# 文章と SubagentHandback を1つの発言で出すと、フックは道具で返したあとにしか呼ばれず、最後の文章が空になる。
# そのときはエージェントの記録から、jsonl のブロックを含む最後の文章か、道具で返したレポートを読む。
# 道具の呼び出しはフックの時点でまだ記録に書かれていないことがあるので、文章のほうも探す
if [ -z "$block" ]; then
  tr=$(jq -r '.agent_transcript_path // (if (.transcript_path // "") != "" and (.agent_id // "") != "" then (.transcript_path | sub("\\.jsonl$"; "")) + "/subagents/agent-" + .agent_id + ".jsonl" else "" end)' <<<"$input")
  # SubagentHandback で返した直後にフックが呼ばれると、道具の呼び出しがまだ記録に書かれていないことがある。
  # 道具で返したあとはエージェントに続きをさせられないので、記録に出てくるまで少し待って読み直す（0.1秒おき、既定で3秒まで）
  if [ -n "$tr" ] && [ -f "$tr" ]; then
    steps=${QA_SAVE_WAIT_STEPS:-30}
    for ((i = 0; i <= steps; i++)); do
      found=$(jq -rn '[inputs | select(.message.role? == "assistant") | .message.content? | arrays | .[]
        | if .type? == "text" then .text? elif .type? == "tool_use" and .name? == "SubagentHandback" then .input.message? else empty end
        | strings | select(test("(^|\n)```jsonl[ \t]*(\n|$)"))] | last // ""' "$tr" 2>/dev/null)
      [ -n "$found" ] && break
      [ "$i" -lt "$steps" ] && sleep 0.1
    done
    if [ -n "$found" ]; then msg=$found; block=$(last_jsonl <<<"$msg"); fi
  fi
fi
records=$(jq -c --slurp . <<<"$block" 2>/dev/null) || records=""
summary=$(jq -c 'map(select(.type=="summary")) | first // empty' <<<"${records:-[]}")
if [ -z "$summary" ]; then
  # レポートが文章にも記録にも無い。1回目は止まらせずに、レポートを文章で書き直させる。
  # ただし SubagentHandback で返したあとのエージェントは続きをしないので、そのときは上の読み直しが頼り。
  # 書き直しても読めなければ（stop_hook_active）、知らせて終わる
  if [ "$(jq -r '.stop_hook_active // false' <<<"$input")" != true ]; then
    jq -n '{decision:"block",reason:"QAの結果をフックが読み取れませんでした。出力A（人間向けレポート）と出力B（jsonl を言語指定したコードブロック）を、道具を使わずに通常の応答の文章としてもう一度出力してください。jsonl のブロックは応答の最後に置いてください。"}'
    exit 0
  fi
  echo '{"systemMessage":"QAの結果を読み取れませんでした。QA未実施として扱います"}'
  exit 0
fi
target=$(jq -r '.target // "pr"' <<<"$summary")
branch=$(git branch --show-current)
day=$(date +%F)
run=$(date +%H%M%S)   # 同じ日の何回目の QA かを区別する
blockers=$(jq '[.[]|select(.type=="finding" and .severity=="blocker")]|length' <<<"$records")
majors=$(jq '[.[]|select(.type=="finding" and .severity=="major")]|length' <<<"$records")
# 指摘と、回ごとの判定と件数の保存
jq -c --arg b "$branch" --arg d "$day" --arg t "$target" --arg r "$run" --argjson nb "$blockers" --argjson nm "$majors" -L "$here" 'include "mask";
  (.[] | select(.type=="finding")), (map(select(.type=="summary")) | first | . + {blockers:$nb, majors:$nm})
  | . + {branch:$b, target:$t, date:$d, run:$r} | mask_all' \
  <<<"$records" >> "$logs/qa-findings-$day.jsonl"
# 人向けレポートの保存（jsonl ブロックを除く）。回ごとに別のファイルにする
safe_branch=${branch//\//-}
awk '/^```jsonl[[:space:]]*$/{exit} {print}' <<<"$msg" |
  jq -Rrs -L "$here" 'include "mask"; mask' > "$logs/qa-reports/$day-$safe_branch-$target-$run.md"
if [ -n "$mark" ]; then mkdir -p "${mark%/*}"; : > "$mark"; fi
[ "$target" = pr ] || exit 0
# ゲート用の状態更新。件数は指摘の行から数え、LLMの申告を使わない
high=$(jq '[.[]|select(.type=="finding" and .severity=="blocker" and .fix_risk=="high")]|length' <<<"$records")
if [ "$blockers" -eq 0 ] && [ "$(jq -r '.verdict // ""' <<<"$summary")" = 差し戻し ]; then
  echo '{"systemMessage":"QAの判定と指摘が食い違っています。QA未実施として扱います"}'
  exit 0
fi
human=$(jq -r '.needs_human // false' <<<"$summary"); [ "$high" -gt 0 ] && human=true
f=$(state_file); streak=0
[ -f "$f" ] && streak=$(jq -r '.blocker_streak // 0' "$f")
if [ "$blockers" -gt 0 ]; then streak=$((streak+1)); else streak=0; fi
jq -n --arg fp "$(fingerprint)" --argjson b "$blockers" --argjson m "$majors" --argjson h "$human" --argjson s "$streak" \
  '{fingerprint:$fp, blockers:$b, majors:$m, needs_human:$h, blocker_streak:$s}' > "$f"
exit 0
