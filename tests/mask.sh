#!/bin/bash
root=$(cd "$(dirname "$0")/.." && pwd)
rep() { printf "%0.s$1" $(seq 1 "$2"); }
fail=0; n=0
check() { # 入力 残ってはいけない文字列（空なら入力がそのまま残ること）
  n=$((n + 1))
  got=$(jq -n -r -L "$root/plugins/foundation/scripts" --arg s "$1" 'include "mask"; $s | mask')
  if [ -n "$2" ]; then
    case "$got" in *"$2"*) echo "NG 漏れ: $got"; fail=$((fail + 1)) ;; esac
  elif [ "$got" != "$1" ]; then
    echo "NG 変化: $1 -> $got"; fail=$((fail + 1))
  fi
}
# 本物のトークンと誤検知されないよう、値は実行時に組み立てる
v=$(rep c 24)
check "key=sk_live_$v" "$v"
check "slack=xoxb-1234567890-$v" "$v"
check "Authorization: Bearer plain${v}" "plain$v"
check 'password="ab\"leaked"' 'leaked'
check "gh=ghp_$(rep a 36)" "$(rep a 36)"
check "sk-$v" "$v"
check 'secret="日本語の値" 残り' '日本語の値'
check 'ふつうの文章です。tokens are counted.' ''
echo "$((n - fail))/$n passed"
[ "$fail" -eq 0 ]
