#!/bin/bash
input=$(cat)
sid=$(jq -r '.session_id // ""' <<<"$input")
file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
[[ $sid =~ ^[A-Za-z0-9_-]+$ ]] && [ -n "$file" ] || exit 0
map="$HOME/knowledge/languages.json"
[ -f "$map" ] || exit 0   # knowledge がなければ止めない（SessionStart の clone の失敗で作業を止めないため）
reads="$HOME/.claude-logs/knowledge-reads/$sid"
missing=$(jq -r --arg name "$(basename "$file")" --rawfile reads <(cat "$reads" 2>/dev/null) '
  ($reads | split("\n")) as $done
  | [to_entries[] | select(any(.value.extensions[]; . as $e | $name | endswith("." + $e))) | .value.required[]]
  | unique | map(select(. as $p | $done | index($p) | not))
  | map("~/knowledge/" + .) | join("、")' "$map") || exit 0
[ -z "$missing" ] && exit 0
jq -n --arg r "この種類のファイルを編集する前に、Read で次の規約を読んでください: $missing" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
