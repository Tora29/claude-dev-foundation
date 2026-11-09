---
name: qa
description: 要件、基本設計、またはブランチ全体を qa-reviewer で採点する。要件の確定前、基本設計の承認前、PR作成前に使う。
argument-hint: "[requirements|design] [要件ID ...]"
---
引数が requirements か design ならそれを対象とし、それ以外は pr を対象とする。残りの引数は関連する要件ID。なければ「なし」とする。

1. qa-reviewer を呼ぶ。渡すのは対象と要件IDだけで、実装の経緯や自分の判断は伝えない
2. レポートと指摘を受け取る。保存はフックが行うので、自分では保存しない
3. 対象が requirements / design なら、レポートを人に見せて確定または承認を待つ
4. 対象が pr なら、~/knowledge/qa/checklist.md の処理の表に従って修正する。コードを変えたら /qa をやり直す
5. 自動で直すものがなくなったら、判定、件数、人に判断してほしい点を伝えて終わる。PRは作らない
