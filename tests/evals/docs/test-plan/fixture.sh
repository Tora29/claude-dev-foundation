#!/bin/bash
. "$(dirname "$0")/../common.sh"
cp "$sample/basic-design.md" docs/basic-design.md
cat > docs/test-plan.md <<'MD'
# テスト計画: 家計簿サンプル

| 要件ID | 設計ID | テストレベル | 確認する内容 | テスト名 |
|---|---|---|---|---|
| REQ-001 | BD-001 | 結合 | 支出を登録できる | test/routes/api/expenses/server.test.ts「支出を登録できる」 |
MD
