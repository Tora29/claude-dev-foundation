#!/bin/bash
# 使い方: tests/run-evals.sh knowledge-read|docs [runs]
# 環境変数: KNOWLEDGE_SRC（knowledge の clone 元）、MODELS、MAX_COST_USD
set -u
mode=${1:?knowledge-read または docs を指定してください}
root=$(cd "$(dirname "$0")/.." && pwd)
src=${KNOWLEDGE_SRC:-$HOME/ghq/github.com/Tora29/knowledge}
max_cost=${MAX_COST_USD:-10}
case "$mode" in
  knowledge-read) runs=${2:-5}; models=${MODELS:-haiku sonnet} ;;
  docs) runs=${2:-3}; models=${MODELS:-sonnet} ;;
  *) echo "不明なモード: $mode" >&2; exit 2 ;;
esac

stamp=$(date +%Y%m%d-%H%M%S)
out="$root/tests/evals/results/$mode-$stamp"
mkdir -p "$out"

# スキルを起動するとプラグインのパスがモデルに見え、本物のホームを推測して一時ホームの外を読みにいく。
# それでは実環境で読めるものが失敗に見えるので、ホームの外の作業コピーで動かす。
# knowledge は private なので、複製をリポジトリの中に置かない意味もある
work=$(mktemp -d /tmp/cdf-eval.XXXXXX) || exit 1
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
mkdir -p "$work/tests"
cp -R "$root/plugins" "$work/plugins"
cp -R "$root/tests/evals" "$work/tests/evals"
rm -rf "$work/tests/evals/results"
fixture="$work/tests/evals/.fixture"
mkdir -p "$fixture"
# ハードリンクがあると eval が読み込みを拒否する
git clone -q --no-hardlinks "$src" "$fixture/knowledge" || exit 1
if [ ! -f "$fixture/knowledge/INDEX.md" ]; then
  python3 "$fixture/knowledge/ops/build-index.py" || exit 1
fi
knowledge_rev=$(git -C "$fixture/knowledge" rev-parse --short HEAD)

summary="$out/summary.jsonl"
: > "$summary"
for model in $models; do
  # Bash を渡すと eval の sandbox がホームを読めなくするので、Edit と Write だけを渡す
  (cd "$work" && claude plugin eval . --eval-dir tests/evals --tag "$mode" --runs "$runs" --model "$model" \
    --ablation none --no-publish --trust-plugin --scaffold --keep-temp --threshold 0 \
    --max-cost-usd "$max_cost" --allow-tools Edit Write \
    --output-dir "$out/$model" --report "$out/$model/report.html" -j "${CONCURRENCY:-4}" </dev/null >"$out/$model.log" 2>&1)
  echo "$model: exit=$? ($out/$model.log)"
  result="$out/$model/aggregate-result.json"
  [ -f "$result" ] || { echo "結果がありません: $result" >&2; continue; }

  # 判定はモデルの申告でなく trace のツール呼び出しから行う。tool_order は Edit と Write をまとめて扱えず、Read の成否も見ない
  jq -c '.cases[] | .name as $c | .arms.with | to_entries[] |
    {case: $c, run: (.key + 1), trace: .value.tracePath, cost: .value.costUsd, error: .value.error, graders: [.value.graders[]? | {name, passed}]}' "$result" |
  while IFS= read -r row; do
    trace=$(jq -r .trace <<<"$row")
    case "$(jq -r .case <<<"$row")" in
      ts-*) dir=typescript ;; svelte-*) dir=svelte ;; tf-*) dir=terraform ;; *) dir=none ;;
    esac
    [ -f "$trace" ] || { jq -c --arg model "$model" --arg rev "$knowledge_rev" 'del(.trace) + {model: $model, knowledge: $rev, verdict: "no_trace"}' <<<"$row" >> "$summary"; continue; }
    judged=$(jq -cs --arg dir "$dir" '
      ([.[] | select(.type == "user") | .message.content | arrays | .[] | select(.type == "tool_result" and .is_error == true) | .tool_use_id]) as $errors
      | [.[] | select(.type == "assistant") | .message.content | arrays | .[] | select(.type == "tool_use")] as $tools
      | ($tools | to_entries) as $t
      | ([$t[] | select(.value.name == "Edit" or .value.name == "Write") | .key] | first) as $edit
      | ([$t[] | select(.value.name == "Read" and ((.value.id | IN($errors[])) | not) and ((.value.input.file_path // "") | test("/knowledge/(INDEX\\.md$|" + $dir + "/)"))) | .key] | first) as $read
      | ([$t[] | select(.value.name == "Read" and ((.value.input.file_path // "") | test("/knowledge/(INDEX\\.md$|" + $dir + "/)"))) | .key] | first) as $try
      | (map(select(.type == "result")) | last // {}) as $r
      | {verdict: (if $edit == null then "no_edit" elif $read == null then "no_read" elif $read < $edit then "read_first" else "read_after" end),
         tools: [$tools[].name],
         tried_first: (($try != null) and ($edit != null) and ($try < $edit)),
         reads: [$tools[] | select(.name == "Read") | {path: (.input.file_path // "" | sub("^(/private)?/tmp/e-[^/]+/home/"; "~/")), ok: ((.id | IN($errors[])) | not)}],
         read_index: ([$tools[] | select(.name == "Read") | .input.file_path // "" | select(test("/knowledge/INDEX\\.md$"))] | length > 0),
         read_lang: ([$tools[] | select(.name == "Read") | .input.file_path // "" | select(test("/knowledge/" + $dir + "/"))] | length > 0),
         skill: ([$tools[] | select(.name == "Skill") | .input.skill]),
         usage: $r.usage, trace_cost: $r.total_cost_usd}' "$trace")
    jq -c --arg model "$model" --arg rev "$knowledge_rev" --argjson j "$judged" 'del(.trace) + {model: $model, knowledge: $rev} + $j' <<<"$row" >> "$summary"
  done

  # 複製した knowledge が残らないよう、実行ごとの一時ディレクトリを消す
  sed -n 's/^ *kept temp: //p' "$out/$model.log" | while IFS= read -r d; do
    case "$d" in /private/tmp/e-*|/tmp/e-*) chmod -R u+rwx "$d" 2>/dev/null; rm -rf "$d" ;; esac
  done
  jq -r '"費用の見積もり(\($m)): $\(.costUsd) / \(.durationSeconds)秒 / CLI \(.claudeVersion) / partial=\(.partial)"' --arg m "$model" "$result"
done

echo
echo "knowledge: $knowledge_rev"
if [ "$mode" = knowledge-read ]; then
  echo "| 組み合わせ | モデル | 最初の Edit/Write より前に Read できた | 前に試みた | Read が後 | Read なし | 編集なし | スキル起動 |"
  echo "|---|---|---|---|---|---|---|---|"
  jq -rs 'group_by([.case, .model])[] | . as $g | length as $n |
    ([.[] | select(.verdict == "read_first")] | length) as $m |
    "| \(.[0].case) | \(.[0].model) | \($n)回中\($m)回 | \([$g[] | select(.tried_first == true)] | length) | \([$g[] | select(.verdict == "read_after")] | length) | \([$g[] | select(.verdict == "no_read")] | length) | \([$g[] | select(.verdict == "no_edit" or .verdict == "no_trace")] | length) | \([$g[] | select((.skill // []) | length > 0)] | length) |"' "$summary"
else
  echo "| ケース | 全グレーダー通過 | 落ちたグレーダー |"
  echo "|---|---|---|"
  jq -rs 'group_by(.case)[] | length as $n |
    "| \(.[0].case) | \($n)回中\([.[] | select(([.graders[].passed] | all) and .error == null)] | length)回 | \([.[].graders[] | select(.passed | not) | .name] | group_by(.) | map("\(.[0])×\(length)") | join(", ")) |"' "$summary"
fi
echo "集計: $summary"
