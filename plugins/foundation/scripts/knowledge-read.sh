#!/bin/bash
input=$(cat)
sid=$(jq -r '.session_id // ""' <<<"$input")
[[ $sid =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
kn=$(cd "$HOME/knowledge" 2>/dev/null && pwd -P) || exit 0
# Read はファイルのパス、Bash は cat などのコマンドに書かれた ~/knowledge のパスを数える
case "$(jq -r '.tool_name // ""' <<<"$input")" in
  Read) files=$(jq -r '.tool_input.file_path // ""' <<<"$input") ;;
  Bash) files=$(jq -r '.tool_input.command // ""' <<<"$input" | grep -oE "(~|\\\$HOME|\\\$\{HOME\}|$HOME)/knowledge/[A-Za-z0-9_./-]+" | sed -E "s#^(~|\\\$HOME|\\\$\{HOME\})#$HOME#") ;;
  *) exit 0 ;;
esac
logs="$HOME/.claude-logs/knowledge-reads"
umask 077; mkdir -p "$logs"
while IFS= read -r file; do
  [ -n "$file" ] || continue
  dir=$(cd "$(dirname "$file")" 2>/dev/null && pwd -P) || continue
  case "$dir/" in "$kn"/*) ;; *) continue ;; esac
  rel="${dir#"$kn"}/$(basename "$file")"
  printf '%s\n' "${rel#/}" >> "$logs/$sid"
done <<<"$files"
find "$logs" -type f -mtime +7 -delete 2>/dev/null
exit 0
