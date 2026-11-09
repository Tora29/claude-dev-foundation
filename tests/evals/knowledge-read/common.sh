set -e
here=$(cd "$(dirname "$0")" && pwd)
cp -R "$here/../../.fixture/knowledge" "$HOME/knowledge"
git init -q .
