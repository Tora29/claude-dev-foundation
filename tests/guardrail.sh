#!/bin/bash
# guardrail-rules.json を変えたら実行する。tests/guardrail-cases.json のとおりに判定されるかを確かめる
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/plugins/core/scripts/guardrail.sh"
fail=0; n=0
while IFS= read -r c; do
  n=$((n + 1))
  input=$(jq -c '{hook_event_name: "PreToolUse", tool_name: (.tool // "Bash"), tool_input:
    (if .cmd then {command: .cmd} else {file_path: .file, notebook_path: .notebook, path: .path} | with_entries(select(.value != null)) end)}' <<<"$c")
  got=$("$script" <<<"$input") || { echo "ERROR(exit $?): $c"; fail=$((fail + 1)); continue; }
  got=$(jq -r .hookSpecificOutput.permissionDecision <<<"$got"); got=${got:-pass}
  want=$(jq -r .want <<<"$c")
  [ "$got" = "$want" ] || { echo "NG want=$want got=$got: $c"; fail=$((fail + 1)); }
done < <(jq -c '.[]' "$root/tests/guardrail-cases.json")
echo "$((n - fail))/$n passed"
[ "$fail" -eq 0 ]
