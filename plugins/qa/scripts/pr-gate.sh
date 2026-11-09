#!/bin/bash
here=$(dirname "$0"); . "$here/lib.sh"
decide() { jq -n --arg d "$1" --arg r "$2" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'; exit 0; }
input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input") || exit 2
cd "$(jq -r .cwd <<<"$input")" || exit 2
default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); default=${default#origin/}; default=${default:-main}
# 連結したコマンドのうち git push の部分だけを見る（gh pr create --base main に反応しないため）
push=$(awk '{gsub(/&&|\|\||;|\|/,"\n"); print}' <<<"$cmd" | grep -E '^[[:space:]]*git[[:space:]]+push\b')
if [ -n "$push" ]; then
  if grep -qE '[[:space:]](--delete|-d)[[:space:]]' <<<"$push" && ! grep -qE "[[:space:]]$default([[:space:]]|$)" <<<"$push"; then
    :  # 既定ブランチ以外の削除は、既定ブランチの上からでも通す。続く gh pr create は下で判定する
  elif [ "$(git branch --show-current 2>/dev/null)" = "$default" ] || grep -qE "[[:space:]:]$default([[:space:]]|$)" <<<"$push"; then
    decide deny "$default への直接 push は禁止です。作業ブランチから PR を作ってください"
  fi
fi
grep -qE '(^|[;&|[:space:]])gh[[:space:]]+(pr[[:space:]]+create|api[[:space:]].*pulls)' <<<"$cmd" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || decide deny "Git リポジトリの中で実行してください"
fp=$(fingerprint) || decide deny "差分を計算できませんでした"
[ -z "$fp" ] && exit 0   # 判定の対象に変更がなければ通す
f=$(state_file)
[ -f "$f" ] || decide deny "QA が未実施です。/qa を実行してください"
[ "$(jq -r .fingerprint "$f")" = "$fp" ] || decide deny "最後の QA の後にコードか要件、基本設計が変わりました。/qa をやり直してください"
b=$(jq -r .blockers "$f")
[ "$b" -eq 0 ] && exit 0
if [ "$(jq -r .needs_human "$f")" = true ] || [ "$(jq -r .blocker_streak "$f")" -ge 3 ]; then
  decide ask "blocker が ${b} 件残っています。人の判断で PR を作りますか？"
fi
decide deny "blocker が ${b} 件残っています。修正して /qa をやり直してください"
