---
name: test-plan
description: REQ-ID と NFR-ID ごとにテストレベルと確認する内容を決め、docs/test-plan.md の対応表に行を追記する。要件に対するテストを計画するとき、実装の前に使う。
user-invocable: false
---
1. ~/knowledge/docs-templates/test-plan.md と ~/knowledge/testing/policy.md を読み、それに従う
2. docs/requirements.md と docs/test-plan.md を読む。test-plan.md がなければテンプレートから作る。あれば作り直さず、行を追記する
3. 設計IDは、docs/detailed-design/ と docs/basic-design.md から探して書く

終わる条件: 状態が有効の Must 要件と、すべての NFR-ID に行がある。
