set -e
here=$(cd "$(dirname "$0")" && pwd)
sample="$here/../sample"
cp -R "$here/../../.fixture/knowledge" "$HOME/knowledge"
git init -q .
mkdir -p docs src
cp "$sample/requirements.md" docs/requirements.md
