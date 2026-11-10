#!/bin/bash
[ -n "$CLAUDE_BOT_RUN" ] && exit 0   # 週次分析自身の実行は記録しない
umask 077
mkdir -p ~/.claude-logs
jq -c -L "${CLAUDE_PLUGIN_ROOT}/scripts" 'include "mask";
  {ts: now, ev: .hook_event_name, sid: .session_id, cwd, agent: .agent_type,
   tool: .tool_name, file: (.tool_input.file_path // .tool_input.notebook_path), prompt, error, transcript: .transcript_path}
  | with_entries(select(.value != null))
  | mask_all
  | if .error then .error |= (if type == "string" then .[:500] else . end) else . end' \
  >> ~/.claude-logs/events-$(date +%F).jsonl
