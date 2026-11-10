#!/bin/bash
here=$(cd "$(dirname "$0")" && pwd) || exit 2
input=$(cat)
out=$("$here/$1" <<<"$input"); rc=$?
[ -n "$out" ] && printf '%s\n' "$out"
# deny と ask だけを記録する。記録に失敗しても判定は変えない
if [ -n "$out" ] && [ -z "${CLAUDE_BOT_RUN:-}" ]; then
  (
    umask 077
    mkdir -p ~/.claude-logs
    jq -c -L "$here" --arg gate "${1%.sh}" --argjson out "$out" 'include "mask";
      ($out.hookSpecificOutput.permissionDecision // empty) as $d
      | {ts: now, ev: .hook_event_name, sid: .session_id, cwd, agent: .agent_type, tool: .tool_name,
         gate: $gate, decision: $d, reason: $out.hookSpecificOutput.permissionDecisionReason,
         file: (.tool_input.file_path // .tool_input.notebook_path),
         command: (.tool_input.command // null | if . then .[:300] else . end)}
      | with_entries(select(.value != null))
      | mask_all' <<<"$input" >> ~/.claude-logs/events-$(date +%F).jsonl
  ) 2>/dev/null
fi
exit $rc
