# Bash のコマンドを、規則と照合しやすい形に直す
def normalize:
  gsub("\\\\\\n"; " ")
  # ヒアドキュメントの本文は実行されないことがほとんどなので外す（コミットメッセージでの誤検知を防ぐ）
  | gsub("<<-?\\s*['\"]?(?<t>\\w+)['\"]?(?<r>[^\\n]*)\\n[\\s\\S]*?\\n\\s*\\k<t>\\b"; " \(.r)\n")
  # sh -c と eval の中身は、そのまま実行されるコマンドとして扱う
  | gsub("\\b(?:(?:ba|z)?sh\\s+-\\w*c|eval)\\s+\"(?<p>(?:[^\"\\\\]|\\\\.)*)\""; "; \(.p) ;")
  | gsub("\\b(?:(?:ba|z)?sh\\s+-\\w*c|eval)\\s+'(?<p>[^']*)'"; "; \(.p) ;")
  # 引用符を外す。中の区切り文字は無効にする（git commit -m "a; rm -rf /" を別のコマンドと見ない）
  | gsub("(?<q>\"(?:[^\"\\\\]|\\\\.)*\"|'[^']*')"; .q | .[1:-1] | gsub("[;&|()<>`\\n]"; " "))
  | gsub("[0-9]*>&[0-9-]+"; " ");

# sudo や環境変数の指定、コマンドのパスを外して、コマンド名から始まる形にする
def strip_prefix:
  sub("^[\\s{!]*(?:(?:\\w+=\\S*|sudo|command|builtin|env|exec|nohup|time|nice|xargs|then|do|else|if|while|until)(?:\\s+-\\S+)*\\s+)*"; "")
  | sub("^[^\\s/]*/(?:[^\\s/]+/)*(?=[^\\s/]+(?:\\s|$))"; "")
  | sub("^git(?:\\s+(?:-C|-c)\\s+\\S+|\\s+--\\S+)*\\s+"; "git ");

def segments: [splits("&&|\\|\\||[;|&\\n()`]") | strip_prefix | select(test("\\S"))];

def secret_rule($rules):
  . as $path
  | first($rules.secret_files[]
      | . as $r
      | select(($path | test($r.pattern; "i")) and (($r.unless // null) == null or ($path | test($r.unless; "i")) == false)));

def is_secret($rules): [secret_rule($rules)] | length > 0;

# そのコマンドが読み書きしうるパスの候補
def path_tokens($rules):
  if test($rules.secret_commands)
  then [splits("[\\s=@<>:]+")]
  else [match("[<>]+\\s*(?<t>\\S+)"; "g").captures[0].string]
  end;

def bash_hits($rules):
  normalize as $cmd
  | ($cmd | segments) as $segs
  | ($rules.bash[]
      | . as $r
      | select(
          if $r.scope == "command" then ($cmd | test($r.pattern; $r.flags // ""))
          else any($segs[]; test($r.pattern; $r.flags // "") and (($r.unless // null) == null or test($r.unless) == false))
          end)
      | {decision, reason}),
    ($segs[]
      | path_tokens($rules)[]
      | select(is_secret($rules))
      | {decision: "ask", reason: "秘密情報を含むファイル \(.) に触れるコマンドです。実行してよいか確認してください"});

def file_hits($rules):
  (.tool_input | (.file_path, .notebook_path, .path) | strings)
  | . as $path
  | secret_rule($rules)
  | {decision, reason: "秘密情報を含むファイル \($path) の読み書きは禁止です。必要なら人に依頼してください"};

def decide($rules):
  [ if (.tool_input.command | type) == "string" then .tool_input.command | bash_hits($rules)
    else file_hits($rules) end ]
  | sort_by(.decision != "deny")
  | first // empty
  | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: .decision, permissionDecisionReason: .reason}};
