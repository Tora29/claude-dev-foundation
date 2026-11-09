#!/bin/bash
root=$(cd "$(dirname "$0")/.." && pwd)
scripts="$root/plugins/foundation/scripts"
home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
mkdir -p "$home/knowledge/typescript" "$home/knowledge/svelte" "$home/knowledge/common" "$home/work"
for f in typescript/conventions.md svelte/conventions.md common/coding.md; do echo x > "$home/knowledge/$f"; done
cat > "$home/knowledge/languages.json" <<'JSON'
{
  "typescript": { "extensions": ["ts", "tsx"], "required": ["typescript/conventions.md"] },
  "svelte": { "extensions": ["svelte", "svelte.ts"], "required": ["svelte/conventions.md"] }
}
JSON
pass=0; fail=0
check() { # 説明 期待（deny / allow） 実際の出力
  local got=allow; grep -q '"deny"' <<<"$3" && got=deny
  if [ "$got" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "NG: $1（期待 $2、実際 $got）"; fi
}
gate() { jq -n --arg s "$1" --arg f "$2" '{session_id:$s,tool_name:"Edit",tool_input:{file_path:$f}}' | HOME=$home bash "$scripts/knowledge-gate.sh"; }
read_() { jq -n --arg s "$1" --arg f "$2" '{session_id:$s,tool_name:"Read",tool_input:{file_path:$f}}' | HOME=$home bash "$scripts/knowledge-read.sh"; }

check "読む前の .ts" deny "$(gate s1 "$home/work/a.ts")"
check "言語の対応がない .md" allow "$(gate s1 "$home/work/README.md")"
check "拡張子のない Makefile" allow "$(gate s1 "$home/work/Makefile")"
read_ s1 "$home/knowledge/common/coding.md"
check "関係のない規約だけ読んだ .ts" deny "$(gate s1 "$home/work/a.ts")"
read_ s1 "$home/knowledge/typescript/conventions.md"
check "読んだあとの .ts" allow "$(gate s1 "$home/work/a.ts")"
check "読んだあとの .tsx" allow "$(gate s1 "$home/work/b.tsx")"
check "別のセッションの .ts" deny "$(gate s2 "$home/work/a.ts")"
check ".svelte.ts は TypeScript と Svelte の両方が要る" deny "$(gate s1 "$home/work/c.svelte.ts")"
grep -q 'svelte/conventions.md' <<<"$(gate s1 "$home/work/c.svelte.ts")" && grep -vq 'typescript/conventions.md' <<<"$(gate s1 "$home/work/c.svelte.ts")" && pass=$((pass+1)) || { fail=$((fail+1)); echo "NG: 足りない規約だけを示す"; }
read_ s3 "$home/knowledge/../knowledge/svelte/conventions.md"
check "../ を含むパスで読んでも記録される" allow "$(gate s3 "$home/work/d.svelte")"
read_ s4 "$home/work/typescript/conventions.md"
check "knowledge の外の同じ名前のファイルは数えない" deny "$(gate s4 "$home/work/a.ts")"
check "session_id が不正なら止めない" allow "$(gate '../x' "$home/work/a.ts")"
mv "$home/knowledge/languages.json" "$home/languages.json"
check "languages.json がなければ止めない" allow "$(gate s9 "$home/work/a.ts")"
[ "$(stat -f %Lp "$home/.claude-logs/knowledge-reads" 2>/dev/null || stat -c %a "$home/.claude-logs/knowledge-reads")" = 700 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "NG: 記録のディレクトリの権限"; }
echo "$pass/$((pass+fail)) passed"
[ "$fail" -eq 0 ]
