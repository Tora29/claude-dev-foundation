#!/bin/bash
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
scripts="$root/plugins/qa/scripts"
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
  jq -n --arg m "$1" --arg d "$repo" '{hook_event_name:"SubagentStop",agent_type:"qa:qa-reviewer",cwd:$d,last_assistant_message:$m}' |
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
check "保存: 指摘は2行" 2 "$(wc -l < "$HOME/.claude-logs/qa-findings-$day.jsonl" | tr -d ' ')"
check "保存: 指摘はマスクされる" 0 "$(grep -c "$fake_token" "$HOME/.claude-logs/qa-findings-$day.jsonl")"
check "保存: レポートに jsonl を含めない" 0 "$(grep -c '```jsonl' "$HOME/.claude-logs/qa-reports/$day-feat-x-pr.md")"
check "保存: ファイルは本人だけが読める" "-rw-------" "$(ls -l "$HOME/.claude-logs/qa-findings-$day.jsonl" | cut -c1-10)"
save "$(report "$sum"$'\n'"$f3")" >/dev/null
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
check "保存: 読み取れないことを知らせる" yes "$(jq -r .systemMessage <<<"$msg" | grep -q '読み取れません' && echo yes)"
save "$(report '{"type":"summary","target":"requirements","verdict":"修正推奨","needs_human":false}'$'\n'"$f2")" >/dev/null
check "保存: requirements はゲートの記録を変えない" same "$(cmp -s "$work/before.json" "$(state_file)" && echo same)"
check "保存: requirements のレポートは残す" yes "$([ -f "$HOME/.claude-logs/qa-reports/$day-feat-x-requirements.md" ] && echo yes)"
save "$(printf '```jsonl\n%s\n```\n修正版:\n```jsonl\n%s\n```\n' '{"type":"summary","target":"pr","verdict":"マージ可","needs_human":false}' "$sum"$'\n'"$f1")" >/dev/null
check "保存: jsonl が複数あれば最後を使う" 1 "$(jq -r .blockers "$(state_file)")"

# qa-bash-guard.sh
mkdir -p .claude
printf '%s\n' 'npm test' 'semgrep scan --config p/default --metrics=off --error --quiet .' > .claude/qa-test-commands
guard() { # コマンド [agent_type]
  jq -n --arg c "$1" --arg a "${2-qa:qa-reviewer}" --arg d "$repo" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d} + (if $a == "" then {} else {agent_type:$a} end)' |
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

echo "$((n - fail))/$n passed"
[ "$fail" -eq 0 ]
