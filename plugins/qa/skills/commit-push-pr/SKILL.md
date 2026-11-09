---
name: commit-push-pr
description: 変更をコミットし、QAを通してPRを作る。
disable-model-invocation: true
---
1. 既定ブランチの上なら作業ブランチを作り、変更をコミットする。件名は ~/knowledge/common/ のGitのルールに従う
2. /qa を実行し、関連する要件IDを渡す（会話や docs/test-plan.md から分かるもの。小の変更は「なし」）。このセッションで /qa を通したあとに変更がなければ省いてよい
3. 指摘を ~/knowledge/qa/checklist.md の処理の表に従って修正し、コミットして /qa をやり直す。人の判断が必要なら、ここで止めて伝える
4. 自動で直すものがなくなったら push して `gh pr create` を実行する。本文に入れるのは判定、件数、人に判断してほしい点だけで、脆弱性の場所や再現方法は書かない
5. ゲートに止められたら、理由に従う
