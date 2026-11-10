---
name: detailed-design
description: 複雑なモジュールの詳細設計を docs/detailed-design/ に1モジュール1ファイルで、DD-ID を付けて書く。処理の理由やエラー処理がコードだけでは伝わらないモジュールを実装するときに使う。
user-invocable: false
---
1. ~/knowledge/docs-templates/detailed-design.md を読み、注記に従う
2. docs/basic-design.md の関連する BD-ID と、対象モジュールのコードを読む
3. docs/detailed-design/<モジュール名>.md に書く。1モジュール1ファイルで、すでにあれば DD-ID を追記する。DD-ID はプロジェクト全体で重ならない番号にする

終わる条件: 実装と同じPRに含めた。
