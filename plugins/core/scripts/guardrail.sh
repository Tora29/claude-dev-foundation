#!/bin/bash
# PreToolUse: 破壊的なコマンド、PR のマージ、秘密情報を含むファイルの読み書きを deny / ask にする
# 禁止リストの中身は guardrail-rules.json にある。事故を防ぐためのもので、意図的な回避までは防がない（それは sandbox の役割）
here=$(cd "$(dirname "$0")" && pwd) || exit 2
exec jq -c -L "$here" --slurpfile rules "$here/guardrail-rules.json" 'include "guardrail"; decide($rules[0])'
