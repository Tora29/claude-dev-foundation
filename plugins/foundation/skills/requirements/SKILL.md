---
name: requirements
description: 要件定義を人に質問しながら下書きし、docs/requirements.md に REQ-ID と NFR-ID を追記・変更する。機能の追加や仕様変更で要件を決めるときに使う。
user-invocable: false
---
1. ~/knowledge/docs-templates/requirements.md を読み、注記に従う
2. docs/requirements.md を読む。なければテンプレートから作る。あれば作り直さず、追記または変更する
3. 人に質問しながら下書きする。分からない点は推測で埋めない
4. 下書きができたら `/foundation:qa requirements` を実行し、レポートを人に見せて確定を待つ。確定するまで設計や実装に進まない
5. 既存の要件を変えたときは、確定のあとで REQ-ID をたどり、影響する設計書、コード、テストを洗い出して人に示す。修正は同じPRで行う

終わる条件: `/foundation:qa requirements` のあと、人が確定した。
