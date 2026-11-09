#!/bin/bash
# commit-push-pr の通しの流れ（コミット → /qa → 修正 → PR）を確かめる。origin はローカルの bare リポジトリ、gh はスタブ
. "$(dirname "$0")/env.sh"
trap e2e_cleanup EXIT
out_dir="$root/tests/qa-e2e/results/flow-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out_dir"
# QA の前の PR 作成が、実機のフックで止まるか。連結したコマンドでも止まるか
g="$e2e/gate"
"$root/tests/qa-e2e/make-repo.sh" "$g" reviewer
run_claude "$g/app" haiku "$out_dir/gate.jsonl" '次の2つのコマンドを、それぞれ1回ずつ、この順に Bash で実行してください。止められても再試行や代わりの手段は使わず、各結果を1行で報告してください。
1. gh pr create --fill
2. git status --short && gh pr create --fill' --allowedTools Bash

r="$e2e/flow"
"$root/tests/qa-e2e/make-repo.sh" "$r" flow
run_claude "$r/app" "${MODEL:-sonnet}" "$out_dir/flow.jsonl" "/qa:commit-push-pr" \
  --allowedTools Read Glob Grep Edit Write Bash Skill Task Agent
# 人の判断を求めて止まったときは、同じセッションを続けて答える
followup=${FOLLOWUP:-'判断をお伝えします。関連する要件は REQ-001 と NFR-001 です。そのほかの指摘は今回は直さず、残った点として PR 本文に書いてください。続けて PR まで進めてください。'}
sid=$(jq -rs '[.[] | select(.type == "system" and .subtype == "init")] | first | .session_id' "$out_dir/flow.jsonl")
if [ -n "$sid" ] && [ -z "$(jq -r 'select(.args[0] == "pr" and .args[1] == "create") | 1' "$e2e/gh-calls.jsonl" 2>/dev/null)" ]; then
  run_claude "$r/app" "${MODEL:-sonnet}" "$out_dir/flow2.jsonl" "$followup" \
    --allowedTools Read Glob Grep Edit Write Bash Skill Task Agent --resume "$sid"
fi
app="$r/app"
{
  echo "## QA 前の PR 作成"
  jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | {id, c: .input.command}] as $u | ([.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result") | {key: .tool_use_id, value: (.content | tostring | .[0:120])}] | from_entries) as $r | $u[] | "\(.c) => \($r[.id])"' "$out_dir/gate.jsonl"
  n=$(jq -c 'select(.args[0] == "pr")' "$e2e/gh-calls.jsonl" 2>/dev/null | wc -l | tr -d ' '); echo "gh の実行: ${n} 回（0 なら止まった）"
  : > "$e2e/gh-calls.jsonl"
  echo; echo "## 最終応答"; for f in "$out_dir"/flow.jsonl "$out_dir"/flow2.jsonl; do [ -f "$f" ] && { echo "### $(basename "$f")"; jq -rs '[.[] | select(.type == "result")] | last | .result' "$f"; }; done
  echo; echo "## メインのツール呼び出し"
  cat "$out_dir"/flow*.jsonl | jq -rs '.[] | select(.type == "assistant" and .parent_tool_use_id == null) | .message.content[]? | select(.type == "tool_use") | "\(.name) \(.input.command // .input.skill // .input.subagent_type // .input.file_path // "" | tostring | gsub("\n"; " ") | .[0:140])"'
  echo; echo "## フックに止められた呼び出し"
  cat "$out_dir"/flow*.jsonl | jq -rs '.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result" and .is_error == true) | (.content | tostring | .[0:160])'
  echo; echo "## ブランチとコミット"; git -C "$app" branch --show-current; git -C "$app" log --oneline --all
  echo; echo "## origin のブランチ"; git -C "$r/origin.git" branch
  echo; echo "## 作業ツリー"; git -C "$app" status --short
  echo; echo "## ゲートの記録"; cat "$fake_home"/.claude-logs/qa-state/*.json 2>/dev/null
  echo; echo "## QA の回数"; ls "$fake_home"/.claude-logs/qa-reports/ 2>/dev/null; cat "$fake_home"/.claude-logs/qa-findings-*.jsonl 2>/dev/null | jq -c '{severity, location, fix_risk, effort}'
  echo; echo "## gh の呼び出し"; jq -c '.args' "$e2e/gh-calls.jsonl" 2>/dev/null
  echo; echo "## PR 本文"; jq -r 'select(.args[0] == "pr" and .args[1] == "create") | .body' "$e2e/gh-calls.jsonl" 2>/dev/null
  echo; echo "## PR 本文に場所が書かれていないか"
  jq -r 'select(.args[0] == "pr" and .args[1] == "create") | .body' "$e2e/gh-calls.jsonl" 2>/dev/null | grep -nE '[A-Za-z0-9_./-]+\.(js|ts):[0-9]+|再現' || echo "なし"
  echo; echo "## 費用"; for f in "$out_dir"/*.jsonl; do echo "$(basename "$f"): $(jq -s '[.[] | select(.type == "result")] | last | .total_cost_usd' "$f")"; done
} > "$out_dir/report.md" 2>&1
echo "結果: $out_dir/report.md"
