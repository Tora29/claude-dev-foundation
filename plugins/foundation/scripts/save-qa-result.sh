#!/bin/bash
set -u
here=$(dirname "$0"); . "$here/lib.sh"
umask 077
input=$(cat)
cd "$(jq -r .cwd <<<"$input")" || exit 0
logs="$HOME/.claude-logs"; mkdir -p "$logs/qa-state" "$logs/qa-reports"
last_jsonl() { awk '/^```jsonl[[:space:]]*$/{b="";on=1;next} /^```[[:space:]]*$/{if(on){last=b;on=0};next} on{b=b $0 "\n"} END{printf "%s",last}'; }
msg=$(jq -r '.last_assistant_message // ""' <<<"$input")
block=$(last_jsonl <<<"$msg")
# 裏で動いたエージェントは、文章を書かずに SubagentHandback の道具でレポートを返すことがある。
# そのときは最後の文章が空になるので、エージェントの記録から最後に返したレポートを読む
if [ -z "$block" ]; then
  tr=$(jq -r '.agent_transcript_path // (if (.transcript_path // "") != "" and (.agent_id // "") != "" then (.transcript_path | sub("\\.jsonl$"; "")) + "/subagents/agent-" + .agent_id + ".jsonl" else "" end)' <<<"$input")
  if [ -n "$tr" ] && [ -f "$tr" ]; then
    handback=$(jq -rn '[inputs | .message.content? | arrays | .[] | select(.type? == "tool_use" and .name? == "SubagentHandback") | .input.message? | strings] | last // ""' "$tr" 2>/dev/null)
    if [ -n "$handback" ]; then msg=$handback; block=$(last_jsonl <<<"$msg"); fi
  fi
fi
records=$(jq -c --slurp . <<<"$block" 2>/dev/null) || records=""
summary=$(jq -c 'map(select(.type=="summary")) | first // empty' <<<"${records:-[]}")
if [ -z "$summary" ]; then
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
