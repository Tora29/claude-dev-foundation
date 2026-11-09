#!/bin/bash
# 使い方: make-repo.sh <作るディレクトリ> <reviewer|flow>
# reviewer: 弱点を作業ブランチにコミットした状態。flow: main の上の未コミットの変更
set -eu
dest=$1 mode=$2
mkdir -p "$dest"
cd "$dest"
git init -q --bare origin.git
git init -q -b main app
cd app
mkdir -p src test docs .claude
cat > package.json <<'JSON'
{ "name": "kakeibo-sample", "private": true, "type": "module", "scripts": { "test": "node --test" }, "dependencies": { "express": "^5.1.0" } }
JSON
cat > docs/requirements.md <<'MD'
# 要件定義: 家計簿サンプル

## 2. 機能要件
| ID | 要件 | 優先度 | 状態 | 関連業務 |
|---|---|---|---|---|
| REQ-001 | 自分の支出の一覧を CSV で出力できる | Must | 有効 | 集計 |

## 3. 非機能要件（該当するものだけ）
| ID | 品質特性 | 要件 | 測り方 |
|---|---|---|---|
| NFR-001 | セキュリティ | 本人のデータのみ取得可 | 認可テスト |
MD
cat > docs/test-plan.md <<'MD'
# テスト計画: 家計簿サンプル

| 要件ID | 設計ID | テストレベル | 確認する内容 | テスト名 |
|---|---|---|---|---|
| REQ-001 | - | 結合 | 自分の支出を CSV で出力できる | test/export.test.js「自分の支出を CSV で出力できる」 |
| NFR-001 | - | 結合 | 他人の支出は出力されない | test/export.test.js「他人の支出は出力されない」 |
MD
printf '%s\n' 'node --test' 'semgrep scan --config p/default --metrics=off --error --quiet .' > .claude/qa-test-commands
cat > src/db.js <<'JS'
const expenses = [
  { userId: 'u1', date: '2026-11-01', amount: 1200, memo: '昼食' },
  { userId: 'u2', date: '2026-11-02', amount: 800, memo: '本' },
]

export function findExpenses(userId) {
  return expenses.filter((e) => e.userId === userId)
}
JS
git add -A
git commit -qm "chore: 雛形"
git remote add origin ../origin.git
git push -q -u origin main
git remote set-head origin main

if [ "$mode" = reviewer ]; then
  git switch -q -c feat/export
fi
# 認可の欠陥: 出力する利用者をセッションではなくクエリから受け取る
cat > src/export.js <<'JS'
import { findExpenses } from './db.js'

function toLine(e) {
  return `${e.date},${e.amount},"${e.memo.replaceAll('"', '""')}"`
}

export function exportCsv(req) {
  const userId = req.query.userId
  return findExpenses(userId).map(toLine).join('\n')
}
JS
if [ "$mode" = reviewer ]; then
  # コードインジェクション: 利用者の入力を eval に渡す（Semgrep の p/default で検出される）
  cat > src/routes.js <<'JS'
import express from 'express'
import { exportCsv } from './export.js'

export const app = express()

app.get('/export', (req, res) => res.type('text/csv').send(exportCsv(req)))
app.get('/calc', (req, res) => res.send(String(eval(req.query.expr))))
JS
fi
cat > test/export.test.js <<'JS'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { exportCsv } from '../src/export.js'

test('自分の支出を CSV で出力できる', () => {
  const csv = exportCsv({ session: { userId: 'u1' }, query: { userId: 'u1' } })
  assert.equal(csv, '2026-11-01,1200,"昼食"')
})
JS
if [ "$mode" = reviewer ]; then
  git add -A
  git commit -qm "feat(export): 支出を CSV で出力できるようにする"
fi
