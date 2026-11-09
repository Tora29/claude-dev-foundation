#!/bin/bash
# 弱点を仕込んだ架空のリポジトリで qa-reviewer を繰り返し動かし、検出と判定がぶれないかを見る
# 使い方: tests/qa-e2e/reviewer-runs.sh [回数]
runs=${1:-3}
. "$(dirname "$0")/env.sh"
trap e2e_cleanup EXIT
out_dir="$root/tests/qa-e2e/results/reviewer-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out_dir"
prompt='qa-reviewer サブエージェントに「対象: pr、要件ID: REQ-001」とだけ伝えて実行してください。返ってきたレポートの総合判定を1行で答えてください。コードやファイルは変更しないでください。'
for i in $(seq 1 "$runs"); do
  r="$e2e/run$i"
  "$root/tests/qa-e2e/make-repo.sh" "$r" reviewer
  run_claude "$r/app" haiku "$out_dir/run$i.jsonl" "$prompt" \
    --allowedTools Read Glob Grep Bash Task Agent --disallowedTools Edit Write
  state=$(cat "$fake_home"/.claude-logs/qa-state/*.json 2>/dev/null | jq -c --arg d "$r" 'select(true)' | tail -1)
  findings=$(cat "$fake_home"/.claude-logs/qa-findings-*.jsonl 2>/dev/null | jq -c 'select(.branch == "feat/export")' | jq -sc .)
  report=$(ls -t "$fake_home"/.claude-logs/qa-reports/*-feat-export-pr.md 2>/dev/null | head -1)
  verdict=$(grep -m1 -oE '総合判定[^差修マ対]*(差し戻し|修正推奨|マージ可|対象なし)' "$report" 2>/dev/null | grep -oE '差し戻し|修正推奨|マージ可|対象なし')
  jq -sc '[.[] | select(.type == "assistant" and .parent_tool_use_id != null) | .message.content[]? | select(.type == "tool_use" and .name == "Bash") | .input.command]' "$out_dir/run$i.jsonl" > "$out_dir/run$i-bash.json" 2>/dev/null
  denied=$(jq -s '[.[] | select(.type == "user" and .parent_tool_use_id != null) | .message.content[]? | select(.type == "tool_result" and .is_error == true and ((.content | tostring) | test("実行できます|使えません")))] | length' "$out_dir/run$i.jsonl" 2>/dev/null)
  cost=$(jq -s '[.[] | select(.type == "result")] | last | .total_cost_usd' "$out_dir/run$i.jsonl" 2>/dev/null)
  agent=$(jq -s '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and (.name == "Task" or .name == "Agent")) | .input.subagent_type] | join(",")' -r "$out_dir/run$i.jsonl" 2>/dev/null)
  jq -nc --argjson i "$i" --arg v "${verdict:-}" --arg a "$agent" --argjson s "${state:-null}" --argjson f "${findings:-[]}" --argjson c "${cost:-null}" --argjson d "${denied:-0}" \
    --argjson bash "$(cat "$out_dir/run$i-bash.json" 2>/dev/null || echo '[]')" \
    '{run: $i, agent: $a, verdict: $v, state: $s, findings: [$f[] | {severity, characteristic, location, fix_risk}], bash: $bash, guard_denied: $d, cost: $c}' >> "$out_dir/summary.jsonl"
  rm -f "$fake_home"/.claude-logs/qa-state/*.json "$fake_home"/.claude-logs/qa-findings-*.jsonl "$fake_home"/.claude-logs/qa-reports/*.md
done
echo "集計: $out_dir/summary.jsonl"
jq -r '"run\(.run): agent=\(.agent) 判定=\(.verdict) blockers=\(.state.blockers // "記録なし") majors=\(.state.majors // "-") needs_human=\(.state.needs_human // "-") 指摘=\([.findings[] | "\(.severity):\(.location)"] | join(" ")) 制限で拒否=\(.guard_denied) 費用=$\(.cost)"' "$out_dir/summary.jsonl"
