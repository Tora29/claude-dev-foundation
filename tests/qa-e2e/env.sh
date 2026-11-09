# 実機の claude -p で qa を動かすための一時環境を作る。読み込んで使う
# フックの書き込み先と ~/knowledge は一時ホームに向け、本物の ~/.claude-logs と ~/knowledge に触れない
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
src=${KNOWLEDGE_SRC:-$HOME/ghq/github.com/Tora29/knowledge}
e2e=$(mktemp -d /tmp/cdf-qa.XXXXXX) || exit 1
fake_home="$e2e/home"
mkdir -p "$fake_home" "$e2e/plugins" "$e2e/bin"
git clone -q "$src" "$fake_home/knowledge" || exit 1
for p in core qa; do
  cp -R "$root/plugins/$p" "$e2e/plugins/$p"
  jq --arg h "$fake_home" '.hooks |= with_entries(.value |= map(.hooks |= map(.command = "export HOME=\($h); " + .command)))' \
    "$root/plugins/$p/hooks/hooks.json" > "$e2e/plugins/$p/hooks/hooks.json"
  grep -rl '~/knowledge' "$e2e/plugins/$p" | while IFS= read -r f; do
    sed -i '' "s#~/knowledge#$fake_home/knowledge#g" "$f"
  done
done
# 本物の GitHub に PR を作らないよう gh をスタブにする
cat > "$e2e/bin/gh" <<STUB
#!/bin/bash
log="$e2e/gh-calls.jsonl"
body=""
args=("\$@")
for ((i = 0; i < \${#args[@]}; i++)); do
  case "\${args[i]}" in
    --body-file|-F) body=\$(cat "\${args[i+1]}" 2>/dev/null) ;;
    --body|-b) body=\${args[i+1]} ;;
  esac
done
jq -cn --arg body "\$body" '{args: \$ARGS.positional, body: \$body}' --args -- "\$@" >> "\$log"
case "\$1 \${2:-}" in
  "pr create") echo "https://example.invalid/stub/pull/1" ;;
  "auth status") echo "Logged in (stub)" ;;
esac
exit 0
STUB
chmod +x "$e2e/bin/gh"
e2e_cleanup() { rm -rf "$e2e"; }
run_claude() { # 作業ディレクトリ モデル 出力 依頼文 [追加の引数...]
  local dir=$1 model=$2 out=$3 prompt=$4; shift 4
  (cd "$dir" && PATH="$e2e/bin:$PATH" env -u CLAUDECODE claude -p "$prompt" \
    --plugin-dir "$e2e/plugins/core" --plugin-dir "$e2e/plugins/qa" \
    --model "$model" --setting-sources project,local --add-dir "$fake_home/knowledge" \
    --max-budget-usd "${MAX_BUDGET_USD:-2}" --output-format stream-json --verbose "$@" </dev/null > "$out" 2>&1)
}
