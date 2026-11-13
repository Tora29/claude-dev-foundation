#!/bin/bash
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
scripts="$root/plugins/foundation/scripts"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# 状態ファイルは $HOME の下に書かれるので、本物の ~/.claude-logs に触れないよう一時ホームで動かす
export HOME="$work/home"
mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="$work/gitconfig"
git config --global user.name test
git config --global user.email test@example.invalid
git config --global init.defaultBranch main

fail=0; n=0
check() { # 名前 期待 実際
  n=$((n + 1))
  [ "$2" = "$3" ] || { echo "NG $1: want=$2 got=$3"; fail=$((fail + 1)); }
}

repo="$work/repo"
git init -q --bare "$work/origin.git"
git init -q "$repo"
cd "$repo" || exit 1
mkdir -p src docs sub
echo 'export const a = 1' > src/a.ts
echo '# 要件' > docs/requirements.md
echo '# 基本設計' > docs/basic-design.md
echo '# メモ' > docs/notes.md
echo '# README' > README.md
git add -A && git commit -qm init
git remote add origin "$work/origin.git"
git push -q -u origin main
git remote set-head origin main
git switch -q -c feat/x

. "$scripts/lib.sh"

gate() { # コマンド [cwd]
  jq -n --arg c "$1" --arg d "${2:-$repo}" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    "$scripts/pr-gate.sh" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty' | sed 's/^$//' | { read -r d; echo "${d:-pass}"; }
}
gate_reason() { # コマンド。deny の理由が QA と main のどちらかまで見る
  jq -n --arg c "$1" --arg d "$repo" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    "$scripts/pr-gate.sh" 2>/dev/null | jq -r '.hookSpecificOutput | if . == null then "pass" else .permissionDecision + ":" + (if (.permissionDecisionReason | test("QA")) then "QA" elif (.permissionDecisionReason | test("直接 push")) then "main" else "other" end) end'
}
state() { # blockers needs_human streak [fingerprint]
  mkdir -p "$(dirname "$(state_file)")"
  jq -n --arg fp "${4:-$(fingerprint)}" --argjson b "$1" --argjson h "$2" --argjson s "$3" \
    '{fingerprint:$fp, blockers:$b, majors:0, needs_human:$h, blocker_streak:$s}' > "$(state_file)"
}

# 指紋: 判定の対象に変更がなければ空。docs のほかのファイルと *.md は対象外
check "指紋: 変更なし" "" "$(fingerprint)"
echo '追記' >> docs/notes.md; echo '追記' >> README.md
check "指紋: 対象外の docs と *.md だけ" "" "$(fingerprint)"
check "判定3: 対象の変更がなければ通す" pass "$(gate 'gh pr create --fill')"

echo '追記' >> docs/requirements.md
check "指紋: requirements.md は対象" yes "$([ -n "$(fingerprint)" ] && echo yes)"
git checkout -q docs/requirements.md

# 指紋: 未追跡、ステージ済み、コミット済み、サブフォルダからの実行で変わらない
echo 'export const b = 2' > src/b.ts
fp_untracked=$(fingerprint)
check "指紋: 未追跡の新規ファイルで値が出る" yes "$([ -n "$fp_untracked" ] && echo yes)"
git add src/b.ts
check "指紋: ステージ済み" "$fp_untracked" "$(fingerprint)"
git commit -qm b
check "指紋: コミット済み" "$fp_untracked" "$(fingerprint)"
check "指紋: サブフォルダから" "$fp_untracked" "$(cd sub && fingerprint)"
check "指紋: 対象外の変更を足しても同じ" "$fp_untracked" "$(echo x >> docs/notes.md; fingerprint)"
echo 'export const b = 3' > src/b.ts
check "指紋: コードが変われば変わる" changed "$([ "$(fingerprint)" != "$fp_untracked" ] && echo changed)"
git checkout -q src/b.ts
echo 'export const c = 4' > src/c.ts
fp_before=$(fingerprint)
display_config() { # set か unset
  local k
  for k in diff.noprefix=true color.diff=always color.ui=always diff.mnemonicPrefix=true diff.relative=true; do
    if [ "$1" = set ]; then git config "${k%%=*}" "${k#*=}"; else git config --unset "${k%%=*}"; fi
  done
}
display_config set
check "指紋: diff.noprefix と color.diff=always でも同じ" "$fp_before" "$(fingerprint)"
git add src/c.ts && git commit -qm c
check "指紋: 表示の設定を変えてもコミットの前後で同じ" "$fp_before" "$(fingerprint)"
display_config unset

# 判定1: 既定ブランチへの push
check "判定1: 作業ブランチから main を指定" deny "$(gate 'git push origin main')"
check "判定1: HEAD:main" deny "$(gate 'git push origin HEAD:main')"
check "判定1: 作業ブランチの push は通す" pass "$(gate 'git push -u origin feat/x')"
check "判定1: main を含む別名のブランチは通す" pass "$(gate 'git push origin feat/main-fix')"
git switch -q main
check "判定1: main の上での push" deny "$(gate 'git push')"
check "判定1: main の上でも作業ブランチの削除は通す" pass "$(gate 'git push origin --delete feat/x')"
check "判定1: main の削除は止める" deny "$(gate 'git push origin --delete main')"
git switch -q feat/x

# 判定1: push するリポジトリで判定する。印（.foundation/allow-direct-push）が origin の main にあれば通す
mkrepo() { # パス。origin を持ち、main にいるリポジトリを作る
  git init -q --bare "$1.git" && git init -q "$1" &&
    (cd "$1" && echo x > a && git add -A && git commit -qm init && git remote add origin "$1.git" &&
      git push -q -u origin main && git remote set-head origin main)
}
kn="$HOME/kn"; nm="$work/nm"
mkrepo "$kn"; mkrepo "$nm"
check "判定1: 別のリポジトリの main の上での push は、そのリポジトリで判定する" deny "$(gate "cd $nm && git push")"
check "判定1: git -C の push も対象" deny "$(gate "git -C $nm push origin main")"
check "判定1: git -c の後ろの push も対象" deny "$(gate 'git -c push.default=current push origin main')"
mkdir -p "$kn/.foundation" && touch "$kn/.foundation/allow-direct-push"
check "判定1: 印を手元に置いただけでは止める" deny "$(gate 'cd ~/kn && git push origin main')"
(cd "$kn" && git switch -q -c feat/m && git add -A && git commit -qm m && git push -q origin feat/m)
check "判定1: 印が作業ブランチにあるだけでは止める" deny "$(gate "cd $kn && git push origin HEAD:main")"
(cd "$kn" && git switch -q main && git merge -q feat/m && git push -q origin main)
check "判定1: 印が origin の main にあれば通す" pass "$(gate 'cd ~/kn && git push origin main')"
check "判定1: 印があれば main の上での push も通す" pass "$(gate "cd $kn && git push")"
check "判定1: 印があれば git -C も通す" pass "$(gate 'git -C ~/kn push origin main')"
check "判定1: \$HOME のパスも読む" pass "$(gate 'cd "$HOME/kn" && git push')"
check "判定1: 印があっても main の削除は止める" deny "$(gate "cd $kn && git push origin --delete main")"
check "判定1: 印は push するリポジトリのものだけを見る" deny "$(gate "cd $nm && git push origin main" "$kn")"
check "判定1: 印のないリポジトリへの cd を挟んでも止める" deny "$(gate "cd $kn && git status && cd $nm && git push")"

# 判定2: PR 作成でなければ通す
check "判定2: gh pr view" pass "$(gate 'gh pr view 1')"
check "判定2: git status" pass "$(gate 'git status')"

# 判定4〜7
check "判定4: QA の記録がない" deny "$(gate 'gh pr create --fill')"
check "判定4: gh api でのPR作成も対象" deny "$(gate 'gh api repos/o/r/pulls -f title=x')"
check "判定4: 連結したコマンドも対象" deny "$(gate 'git push -u origin feat/x && gh pr create --fill')"
check "判定4: push と --base main の PR 作成の連結は QA で判定する" "deny:QA" "$(gate_reason 'git push -u origin feat/x && gh pr create --base main')"
check "判定4: 作業ブランチの削除と PR 作成の連結も QA で判定する" "deny:QA" "$(gate_reason 'git push origin --delete old && gh pr create')"
check "判定1: 連結の中の HEAD:main への push" "deny:main" "$(gate_reason 'git status && git push origin HEAD:main')"
state 0 false 0 "0000"
check "判定4: 指紋が違う" deny "$(gate 'gh pr create --fill')"
state 0 false 0
check "判定5: blocker 0件" pass "$(gate 'gh pr create --fill')"
check "判定5: サブフォルダからでも同じ記録を見る" pass "$(gate 'gh pr create --fill' "$repo/sub")"
state 1 true 1
check "判定6: needs_human" ask "$(gate 'gh pr create --fill')"
state 2 false 3
check "判定6: blocker が連続3回" ask "$(gate 'gh pr create --fill')"
state 1 false 2
check "判定7: それ以外の blocker" deny "$(gate 'gh pr create --fill')"
rm -f "$(state_file)"

# Git リポジトリの外
check "Git の外での PR 作成" deny "$(gate 'gh pr create --fill' "$work")"

# save-qa-result.sh: 最終応答から保存し、件数は指摘の行から数える
save() { # 最終応答
  jq -n --arg m "$1" --arg d "$repo" '{hook_event_name:"SubagentStop",agent_type:"foundation:qa-reviewer",cwd:$d,last_assistant_message:$m}' |
    "$scripts/save-qa-result.sh"
}
report() { # summary の JSON と finding の JSON（改行区切り）
  printf '# QAレポート\n本文\n\n```jsonl\n%s\n```\n' "$1"
}
fake_token="ghp_$(printf 'a%.0s' $(seq 1 36))"
f1='{"type":"finding","severity":"blocker","characteristic":"セキュリティ","location":"src/a.ts:1","finding":"x","evidence":"token='"$fake_token"'","fix_diff":"","impact_if_ignored":"","effort":"S","fix_risk":"low"}'
f2='{"type":"finding","severity":"major","characteristic":"保守性","location":"src/b.ts:1","finding":"y","evidence":"","fix_diff":"","impact_if_ignored":"","effort":"S","fix_risk":"low"}'
f3='{"type":"finding","severity":"blocker","characteristic":"セキュリティ","location":"src/a.ts:2","finding":"z","evidence":"","fix_diff":"","impact_if_ignored":"","effort":"M","fix_risk":"high"}'
sum='{"type":"summary","target":"pr","verdict":"差し戻し","needs_human":false}'
day=$(date +%F)

out=$(save "$(report "$sum"$'\n'"$f1"$'\n'"$f2")")
check "保存: 状態ファイルができる" yes "$([ -f "$(state_file)" ] && echo yes)"
check "保存: blockers は指摘の行から" 1 "$(jq -r .blockers "$(state_file)")"
check "保存: majors" 1 "$(jq -r .majors "$(state_file)")"
check "保存: streak" 1 "$(jq -r .blocker_streak "$(state_file)")"
check "保存: 指紋は現在の値" "$(fingerprint)" "$(jq -r .fingerprint "$(state_file)")"
check "保存: 指摘は2行" 2 "$(jq -s 'map(select(.type=="finding"))|length' "$HOME/.claude-logs/qa-findings-$day.jsonl")"
check "保存: 回ごとの判定と件数を残す" '差し戻し 1 1' "$(jq -rs 'map(select(.type=="summary"))|last|"\(.verdict) \(.blockers) \(.majors)"' "$HOME/.claude-logs/qa-findings-$day.jsonl")"
check "保存: 指摘と判定に同じ回の印が付く" 1 "$(jq -rs 'map(.run)|unique|length' "$HOME/.claude-logs/qa-findings-$day.jsonl")"
check "保存: 指摘はマスクされる" 0 "$(grep -c "$fake_token" "$HOME/.claude-logs/qa-findings-$day.jsonl")"
check "保存: レポートに jsonl を含めない" 0 "$(cat "$HOME/.claude-logs/qa-reports/$day-feat-x-pr-"*.md | grep -c '```jsonl')"
check "保存: ファイルは本人だけが読める" "-rw-------" "$(ls -l "$HOME/.claude-logs/qa-findings-$day.jsonl" | cut -c1-10)"
sleep 1   # 回の印は秒単位なので、次の回と分ける
save "$(report "$sum"$'\n'"$f3")" >/dev/null
check "保存: レポートは回ごとに残る" 2 "$(ls "$HOME/.claude-logs/qa-reports/$day-feat-x-pr-"*.md | wc -l | tr -d ' ')"
check "保存: fix_risk が high の blocker で needs_human" true "$(jq -r .needs_human "$(state_file)")"
check "保存: streak が続く" 2 "$(jq -r .blocker_streak "$(state_file)")"
save "$(report '{"type":"summary","target":"pr","verdict":"マージ可","needs_human":false}')" >/dev/null
check "保存: blocker 0件で streak が戻る" 0 "$(jq -r .blocker_streak "$(state_file)")"
check "保存: blocker 0件ならゲートを通る" pass "$(gate 'gh pr create --fill')"

cp "$(state_file)" "$work/before.json"
msg=$(save "$(report "$sum")")
check "保存: 差し戻しなのに blocker がなければ記録しない" same "$(cmp -s "$work/before.json" "$(state_file)" && echo same)"
check "保存: そのときは知らせる" yes "$(jq -r .systemMessage <<<"$msg" | grep -q 'QA未実施' && echo yes)"
msg=$(save "jsonl のブロックがない応答")
check "保存: 読み取れなければ記録しない" same "$(cmp -s "$work/before.json" "$(state_file)" && echo same)"
check "保存: 読み取れなければ1回目は書き直させる" block "$(jq -r .decision <<<"$msg")"
check "保存: 書き直させる理由に jsonl を求める" yes "$(jq -r .reason <<<"$msg" | grep -q 'jsonl' && echo yes)"
msg=$(jq -n --arg d "$repo" '{hook_event_name:"SubagentStop",agent_type:"foundation:qa-reviewer",cwd:$d,stop_hook_active:true,last_assistant_message:"jsonl のブロックがない応答"}' | "$scripts/save-qa-result.sh")
check "保存: 書き直しても読み取れなければ記録しない" same "$(cmp -s "$work/before.json" "$(state_file)" && echo same)"
check "保存: 書き直しても読み取れなければ止めずに知らせる" 'null yes' "$(jq -r .decision <<<"$msg") $(jq -r .systemMessage <<<"$msg" | grep -q '読み取れません' && echo yes)"
save "$(report '{"type":"summary","target":"requirements","verdict":"修正推奨","needs_human":false}'$'\n'"$f2")" >/dev/null
check "保存: requirements はゲートの記録を変えない" same "$(cmp -s "$work/before.json" "$(state_file)" && echo same)"
check "保存: requirements のレポートは残す" yes "$(ls "$HOME/.claude-logs/qa-reports/$day-feat-x-requirements-"*.md >/dev/null 2>&1 && echo yes)"
save "$(printf '```jsonl\n%s\n```\n修正版:\n```jsonl\n%s\n```\n' '{"type":"summary","target":"pr","verdict":"マージ可","needs_human":false}' "$sum"$'\n'"$f1")" >/dev/null
check "保存: jsonl が複数あれば最後を使う" 1 "$(jq -r .blockers "$(state_file)")"

# 文章を書かずに SubagentHandback でレポートを返したとき
handback_line() { # レポート
  jq -cn --arg m "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:$m}}]}}'
}
mkdir -p "$work/tr/sess/subagents"
{ handback_line "$(report "$sum"$'\n'"$f1")"; handback_line "$(report '{"type":"summary","target":"pr","verdict":"修正推奨","needs_human":false}'$'\n'"$f2")"; } > "$work/tr/agent-x.jsonl"
save_tr() { # 入力に足す JSON
  jq -n --arg d "$repo" --argjson x "$1" '{hook_event_name:"SubagentStop",agent_type:"foundation:qa-reviewer",cwd:$d,last_assistant_message:""} + $x' |
    "$scripts/save-qa-result.sh"
}
save_tr "$(jq -n --arg p "$work/tr/agent-x.jsonl" '{agent_transcript_path:$p}')" >/dev/null
check "保存: 文章が空ならエージェントの記録の最後のレポートを読む" '0 1' "$(jq -r '"\(.blockers) \(.majors)"' "$(state_file)")"
check "保存: その回の判定も残す" 修正推奨 "$(jq -rs 'map(select(.type=="summary"))|last|.verdict' "$HOME/.claude-logs/qa-findings-$day.jsonl")"
cp "$work/tr/agent-x.jsonl" "$work/tr/sess/subagents/agent-a1.jsonl"
handback_line "$(report "$sum"$'\n'"$f1")" >> "$work/tr/sess/subagents/agent-a1.jsonl"
save_tr "$(jq -n --arg p "$work/tr/sess.jsonl" '{transcript_path:$p,agent_id:"a1"}')" >/dev/null
check "保存: 記録の場所が無ければ親の記録の隣を探す" 1 "$(jq -r .blockers "$(state_file)")"
cp "$(state_file)" "$work/before.json"
msg=$(save_tr "$(jq -n --arg p "$work/tr/none.jsonl" '{agent_transcript_path:$p}')")
check "保存: 記録が無ければ記録しない" same "$(cmp -s "$work/before.json" "$(state_file)" && echo same)"
check "保存: 記録が無ければ書き直させる" block "$(jq -r .decision <<<"$msg")"
save_tr "$(jq -n --arg p "$work/tr/agent-x.jsonl" '{agent_transcript_path:$p,last_assistant_message:"# 文章\n本文"}')" >/dev/null
check "保存: 文章に jsonl が無くても記録から読む" '0 1' "$(jq -r '"\(.blockers) \(.majors)"' "$(state_file)")"

# 文章と SubagentHandback を1つの発言で出し、フックの時点で道具の呼び出しがまだ記録に無いとき
text_line() { # 文章
  jq -cn --arg m "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$m}]}}'
}
{ text_line "途中の文章"; text_line "$(report "$sum"$'\n'"$f1")"; text_line "締めの一言"; } > "$work/tr/agent-t.jsonl"
save_tr "$(jq -n --arg p "$work/tr/agent-t.jsonl" '{agent_transcript_path:$p}')" >/dev/null
check "保存: 記録の中の jsonl を含む最後の文章を読む" '1 0' "$(jq -r '"\(.blockers) \(.majors)"' "$(state_file)")"
text_line "$(report '{"type":"summary","target":"pr","verdict":"修正推奨","needs_human":false}'$'\n'"$f2")" > "$work/tr/agent-u.jsonl"
handback_line "$(report "$sum"$'\n'"$f1")" >> "$work/tr/agent-u.jsonl"
save_tr "$(jq -n --arg p "$work/tr/agent-u.jsonl" '{agent_transcript_path:$p}')" >/dev/null
check "保存: 文章と道具の両方があれば後のほうを読む" '1 0' "$(jq -r '"\(.blockers) \(.majors)"' "$(state_file)")"

# 同じエージェントでフックが2回呼ばれたとき（文章で止まったときと、道具で返したあと）
rm -f "$(state_file)"
lines() { wc -l < "$HOME/.claude-logs/qa-findings-$day.jsonl" | tr -d ' '; }
before=$(lines)
save_tr "$(jq -n --arg m "$(report "$sum"$'\n'"$f1")" '{agent_id:"dup1",last_assistant_message:$m}')" >/dev/null
save_tr "$(jq -n --arg p "$work/tr/agent-u.jsonl" '{agent_id:"dup1",agent_transcript_path:$p}')" >/dev/null
check "保存: 同じエージェントの2回目は保存しない（streak）" 1 "$(jq -r .blocker_streak "$(state_file)")"
check "保存: 同じエージェントの2回目は保存しない（指摘の行）" 2 "$(($(lines) - before))"
save_tr "$(jq -n --arg m "$(report "$sum"$'\n'"$f1")" '{agent_id:"dup2",last_assistant_message:$m}')" >/dev/null
check "保存: 別のエージェントなら保存する" 2 "$(jq -r .blocker_streak "$(state_file)")"
save_tr "$(jq -n '{agent_id:"dup3",last_assistant_message:"jsonl の無い文章"}')" >/dev/null
save_tr "$(jq -n --arg p "$work/tr/agent-t.jsonl" '{agent_id:"dup3",agent_transcript_path:$p}')" >/dev/null
check "保存: 1回目に読めなければ2回目で保存する" 3 "$(jq -r .blocker_streak "$(state_file)")"
save_tr "$(jq -n --arg m "$(report "$sum"$'\n'"$f1")" '{agent_id:"../x",last_assistant_message:$m}')" >/dev/null
check "保存: おかしなエージェントの ID でも印をフォルダの外に作らない" no "$([ -e "$HOME/.claude-logs/qa-state/x" ] && echo yes || echo no)"

# qa-bash-guard.sh
mkdir -p .claude
printf '%s\n' 'npm test' 'semgrep scan --config p/default --metrics=off --error --quiet .' > .claude/qa-test-commands
guard() { # コマンド [agent_type]
  jq -n --arg c "$1" --arg a "${2-foundation:qa-reviewer}" --arg d "$repo" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d} + (if $a == "" then {} else {agent_type:$a} end)' |
    "$scripts/qa-bash-guard.sh" | jq -r '.hookSpecificOutput.permissionDecision // empty' | { read -r d; echo "${d:-pass}"; }
}
check "制限: git diff" pass "$(guard 'git diff main')"
check "制限: git log" pass "$(guard 'git log --oneline -5')"
check "制限: qa-test-commands の行" pass "$(guard 'npm test')"
check "制限: semgrep の行" pass "$(guard 'semgrep scan --config p/default --metrics=off --error --quiet .')"
check "制限: 書いていないコマンド" deny "$(guard 'npm run build')"
check "制限: パイプ" deny "$(guard 'git diff | cat')"
check "制限: 連結" deny "$(guard 'npm test && rm -rf src')"
check "制限: リダイレクト" deny "$(guard 'git diff > x.patch')"
check "制限: 変数展開" deny "$(guard 'git diff $HOME')"
check "制限: --output" deny "$(guard 'git diff --output=x.patch')"
check "制限: --ext-diff" deny "$(guard 'git diff --ext-diff')"
check "制限: git の書き込み" deny "$(guard 'git commit -m x')"
check "制限: 改行で連結" deny "$(guard $'git status\nrm -rf src')"
check "制限: qa-reviewer 以外は対象外" pass "$(guard 'rm -rf src' '')"
check "制限: 別のエージェントも対象外" pass "$(guard 'npm run build' 'Explore')"

# run-gate.sh: 判定をそのまま返し、deny と ask だけを記録する
rg() { # 包むフック 入力
  "$scripts/run-gate.sh" "$1" <<<"$2"; echo "rc=$?"
}
events="$HOME/.claude-logs/events-$(date +%F).jsonl"
rm -f "$events"
in_deny=$(jq -n --arg d "$repo" --arg t "$fake_token" '{hook_event_name:"PreToolUse",session_id:"s1",cwd:$d,tool_name:"Bash",tool_input:{command:"git push origin main # token=\($t)"}}')
want=$(printf '%s\n' "$in_deny" | "$scripts/pr-gate.sh")
got=$(rg pr-gate.sh "$in_deny")
check "記録: 判定はそのまま返す" "$want"$'\n'rc=0 "$got"
check "記録: deny を1行残す" 'pr-gate deny Bash' "$(jq -r '"\(.gate) \(.decision) \(.tool)"' "$events")"
check "記録: コマンドはマスクする" 0 "$(grep -c "$fake_token" "$events")"
rg pr-gate.sh "$(jq -n --arg d "$repo" '{hook_event_name:"PreToolUse",session_id:"s1",cwd:$d,tool_name:"Bash",tool_input:{command:"git status"}}')" >/dev/null
check "記録: 判定がなければ残さない" 1 "$(wc -l < "$events" | tr -d ' ')"
check "記録: フックの失敗の終了コードを返す" rc=2 "$(rg pr-gate.sh '{"cwd":"/nonexistent","tool_input":{"command":"git push"}}' 2>/dev/null | tail -1)"
CLAUDE_BOT_RUN=1 rg pr-gate.sh "$in_deny" >/dev/null
check "記録: 週次分析の実行は残さない" 1 "$(wc -l < "$events" | tr -d ' ')"
rm -f "$events"

echo "$((n - fail))/$n passed"
[ "$fail" -eq 0 ]
