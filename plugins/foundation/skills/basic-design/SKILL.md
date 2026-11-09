---
name: basic-design
description: 確定した要件から基本設計を下書きし、docs/basic-design.md に BD-ID を追記する。新機能や設計の変更で、実装の前に方式を決めるときに使う。
argument-hint: "[対象の要件ID ...]"
---
1. ~/knowledge/docs-templates/basic-design.md を読み、注記に従う
2. docs/requirements.md の確定した要件と、docs/basic-design.md を読む。basic-design.md がなければテンプレートから作る。あれば作り直さず、追記する
3. 既存のコードや定義ファイルを確かめて下書きする
4. 方式を変えるときは、理由を docs/adr/ に残す
5. 下書きができたら `/foundation:qa design` を実行し、レポートを人に見せて承認を待つ。承認されるまで実装に進まない

終わる条件: `/foundation:qa design` のあと、人が承認した。
