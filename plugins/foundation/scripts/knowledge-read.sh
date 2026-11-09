#!/bin/bash
input=$(cat)
sid=$(jq -r '.session_id // ""' <<<"$input")
file=$(jq -r '.tool_input.file_path // ""' <<<"$input")
[[ $sid =~ ^[A-Za-z0-9_-]+$ ]] && [ -n "$file" ] || exit 0
kn=$(cd "$HOME/knowledge" 2>/dev/null && pwd -P) || exit 0
dir=$(cd "$(dirname "$file")" 2>/dev/null && pwd -P) || exit 0
case "$dir/" in "$kn"/*) ;; *) exit 0 ;; esac
rel="${dir#"$kn"}/$(basename "$file")"
logs="$HOME/.claude-logs/knowledge-reads"
umask 077; mkdir -p "$logs"
printf '%s\n' "${rel#/}" >> "$logs/$sid"
find "$logs" -type f -mtime +7 -delete 2>/dev/null
exit 0
