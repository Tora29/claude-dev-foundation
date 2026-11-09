---
name: commit-push-pr
description: 変更をコミットし、QAを通してPRを作る。ユーザーがマージして「完了」と伝えたら、既定ブランチに戻して片付ける。
disable-model-invocation: true
---
ブランチ名、コミットの件名、PRのタイトルと本文の書き方は ~/knowledge/common/git-workflow.md に従う。リポジトリの .claude/rules/ に書き方の決まりがあれば、そちらを優先する。

## PRを作る

1. `git status`、`git branch --show-current`、`git diff --stat` で現状を確かめる。変更がなければ伝えて終わる
2. `gh api user --jq .login` と `gh repo view --json owner --jq .owner.login` が一致するか確かめる。一致しなければ先に進まず、`! gh auth switch --user <所有者>` の実行をユーザーに頼む。アカウントを自分で切り替えない
3. 差分に、~/knowledge/common/ とリポジトリのルールで「公開してよい情報」に当たらないもの（秘密の値、固有の値など）がないか確かめる。あればコミットせずに伝える
4. 既定ブランチの上なら作業ブランチを作る。差分に関係のない変更が混ざっていれば、PRを分けるかユーザーに確かめる
5. 対象のファイルを指定して `git add` し、コミットする。`git add -A` と `git add .` は使わない
6. /qa を実行し、関連する要件IDを渡す（会話や docs/test-plan.md から分かるもの。小の変更は「なし」）。このセッションで /qa を通したあとに変更がなければ省いてよい
7. 指摘を ~/knowledge/qa/checklist.md の処理の表に従って修正し、コミットして /qa をやり直す。人の判断が必要なら、ここで止めて伝える
8. 自動で直すものがなくなったら `git push -u origin <ブランチ>` と `gh pr create` を実行する
   - QAの結果として本文に書くのは、判定、件数、人に判断してほしい点だけ。脆弱性の場所や再現方法は書かない
   - QAの結果は本文の最初の段落に書かない
   - ラベルはリポジトリのルールに従う。まだないラベルを作るときは、ユーザーに確かめる
9. ゲートに止められたら、理由に従う
10. PRのURL、QAの判定と件数、本文の最初の段落を伝え、「マージしたら『完了』と伝えてください」と添える

## マージのあとに片付ける（ユーザーが「完了」と伝えたとき）

1. 手順2と同じアカウントの確認をしてから、`gh pr view <ブランチ> --json state,url` で `MERGED` か確かめる。違えば伝えて何もしない
2. `git switch <既定ブランチ>`、`git pull --ff-only`、`git branch -D <ブランチ>`、`git fetch --prune` を実行する。squash マージでは `-d` が失敗するので、マージを確かめたうえで `-D` を使う
3. リモートに作業ブランチが残っていれば `git push origin --delete <ブランチ>` で消す
4. 既定ブランチが最新になったことと、消したブランチ名を伝える

## 守ること

- 既定ブランチへ直接 push しない。`--force` と `--no-verify` は使わない
- `gh` にログインしていなければ、`! gh auth login` の実行をユーザーに頼む
