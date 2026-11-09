# fingerprint: 既定ブランチとの分岐点からの差分のハッシュ。コード、要件、基本設計が対象。変更がなければ空
# 一時的なインデックスに作業ツリーを入れて比べるので、未追跡、ステージ済み、コミット済みで値が変わらない
# git diff ではなく diff-index を使うのは、表示の設定（色、接頭辞、外部の diff）で値が変わらないようにするため
fingerprint() {
  (
    cd "$(git rev-parse --show-toplevel)" || exit 1
    base_ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD || echo main)
    base=$(git merge-base "$base_ref" HEAD) || exit 1
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    export GIT_INDEX_FILE="$tmp/index"
    git read-tree HEAD && git add -A || exit 1
    {
      git diff-index --cached -p --binary --no-color --no-ext-diff --no-textconv "$base" -- . ':(exclude)docs/**' ':(exclude)*.md'
      git diff-index --cached -p --binary --no-color --no-ext-diff --no-textconv "$base" -- docs/requirements.md docs/basic-design.md
    } | { d=$(cat); [ -z "$d" ] || printf '%s' "$d" | shasum -a 256 | cut -d' ' -f1; }
  )
}
# state_file: リポジトリとブランチごとの状態ファイル。セッションをまたいでも同じ記録を見る
state_file() {
  local k
  k=$(printf '%s|%s' "$(git rev-parse --show-toplevel)" "$(git branch --show-current)" | shasum -a 256 | cut -c1-16)
  echo "$HOME/.claude-logs/qa-state/$k.json"
}
