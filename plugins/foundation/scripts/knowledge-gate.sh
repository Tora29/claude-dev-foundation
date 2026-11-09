#!/bin/bash
input=$(cat)
sid=$(jq -r '.session_id // ""' <<<"$input")
[[ $sid =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
map="$HOME/knowledge/languages.json"
[ -f "$map" ] || exit 0   # knowledge がなければ止めない（SessionStart の clone の失敗で作業を止めないため）
case "$(jq -r '.tool_name // ""' <<<"$input")" in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
    # 書き込みに当たる操作があるときだけ、コマンドに出てくるファイル名を対象にする。2>&1 や >/dev/null は書き込みに数えない
    w=$(sed -E 's/[0-9]*>&[0-9]+//g; s#[0-9]*>+[[:space:]]*/dev/null##g' <<<"$cmd")
    grep -qE '>|(^|[[:space:];&|])(tee|sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|mv|cp|touch)([[:space:]]|$)' <<<"$w" || exit 0
    names=$(grep -oE "[^[:space:]\"'<>|;&()]+" <<<"$w" | sed -E 's#.*/##')
    ;;
  Edit|Write|NotebookEdit) names=$(basename "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")") ;;
  *) exit 0 ;;
esac
reads="$HOME/.claude-logs/knowledge-reads/$sid"
missing=$(jq -r --rawfile names <(printf '%s\n' "$names") --rawfile reads <(cat "$reads" 2>/dev/null) '
  ($reads | split("\n")) as $done
  | ($names | split("\n") | map(select(. != ""))) as $files
  | [to_entries[] | select(any(.value.extensions[]; . as $e | any($files[]; endswith("." + $e)))) | .value.required[]]
  | unique | map(select(. as $p | $done | index($p) | not))
  | map("~/knowledge/" + .) | join("、")' "$map") || exit 0
[ -z "$missing" ] && exit 0
jq -n --arg r "この種類のファイルを編集する前に、Read で次の規約を読んでください: $missing" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
