#!/bin/bash
here=$(dirname "$0"); . "$here/lib.sh"
decide() { jq -n --arg d "$1" --arg r "$2" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'; exit 0; }
input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input") || exit 2
cd "$(jq -r .cwd <<<"$input")" || exit 2
# 既定ブランチへの直接 push を許すリポジトリの印。origin の既定ブランチに入っているときだけ効く。
# 手元に置いただけでは効かないので、エージェントが自分で印を置いてゲートを外すことはできない
allow=.foundation/allow-direct-push
resolve() { # 基準のディレクトリ パス
  local p=${2//[\"\']/}
  case $p in
    "~") p=$HOME ;;
    "~/"*) p=$HOME/${p#"~/"} ;;
    '$HOME'*) p=$HOME${p#'$HOME'} ;;
    '${HOME}'*) p=$HOME${p#'${HOME}'} ;;
    /*) ;;
    *) p=$1/$p ;;
  esac
  printf '%s' "$p"
}
check_push() { # リポジトリ push の部分
  local default
  default=$(git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); default=${default#origin/}; default=${default:-main}
  if grep -qE '[[:space:]](--delete|-d)[[:space:]]' <<<"$2"; then
    # 既定ブランチ以外の削除は、既定ブランチの上からでも通す。既定ブランチの削除は印があっても止める
    grep -qE "[[:space:]:]$default([[:space:]]|$)" <<<"$2" && decide deny "$default の削除は禁止です"
    return
  fi
  if [ "$(git -C "$1" branch --show-current 2>/dev/null)" = "$default" ] || grep -qE "[[:space:]:]$default([[:space:]]|$)" <<<"$2"; then
    git -C "$1" cat-file -e "refs/remotes/origin/$default:$allow" 2>/dev/null && return
    decide deny "$default への直接 push は禁止です。作業ブランチから PR を作ってください"
  fi
}
# 連結したコマンドのうち git push の部分だけを見る（gh pr create --base main に反応しないため）。
# push するリポジトリはセッションの cwd とは限らないので、前の cd と git -C をたどって決める
dir=$PWD
while IFS= read -r seg; do
  if [[ $seg =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]]; then
    dir=$(resolve "$dir" "${BASH_REMATCH[1]}")
    continue
  fi
  [[ $seg =~ ^[[:space:]]*git(([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*)[[:space:]]+push([[:space:]]|$) ]] || continue
  opts=${BASH_REMATCH[1]}
  repo_dir=$dir
  [[ $opts =~ -C[[:space:]]+([^[:space:]]+) ]] && repo_dir=$(resolve "$dir" "${BASH_REMATCH[1]}")
  check_push "$repo_dir" "$seg"
done < <(awk '{gsub(/&&|\|\||;|\|/,"\n"); print}' <<<"$cmd")
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
