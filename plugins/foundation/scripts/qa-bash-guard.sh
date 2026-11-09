#!/bin/bash
input=$(cat)
case "$(jq -r '.agent_type // ""' <<<"$input")" in *qa-reviewer) ;; *) exit 0 ;; esac
deny() { jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cd "$(jq -r .cwd <<<"$input")" || deny "作業ディレクトリに移動できません"
[[ "$cmd" == *$'\n'* || "$cmd" =~ [\;\&\|\<\>\$\`] ]] && deny "パイプ・連結・リダイレクトは使えません。コマンドを1つずつ実行してください"
grep -qFx -- "$cmd" .claude/qa-test-commands 2>/dev/null && exit 0
[[ "$cmd" == *--output* || "$cmd" == *--ext-diff* ]] && deny "--output / --ext-diff は使えません"
[[ "$cmd" =~ ^git[[:space:]]+(status|diff|log|show|ls-files|merge-base|symbolic-ref|rev-parse)([[:space:]]|$) ]] && exit 0
deny "git の読み取りコマンドと .claude/qa-test-commands に書かれたコマンドだけ実行できます"
