# scripts/mask.jq
def mask:
  gsub("-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)"; "***MASKED***")
  | gsub("sk[-_][A-Za-z0-9_-]{16,}"; "***MASKED***")
  | gsub("xox[abprs]-[A-Za-z0-9-]{10,}"; "***MASKED***")
  | gsub("(?<k>bearer\\s+)[A-Za-z0-9._~+/=-]{8,}"; "\(.k)***MASKED***"; "i")
  | gsub("(gh[pousr]_|github_pat_)[A-Za-z0-9_]{20,}"; "***MASKED***")
  | gsub("AKIA[0-9A-Z]{16}"; "***MASKED***")
  | gsub("eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]+"; "***MASKED***")
  | gsub("(?<k>(password|passwd|secret|token|api[_-]?key)[\"']?\\s*[:=]\\s*)(\"(?:[^\"\\\\]|\\\\.)*\"|'[^']*'|[^\\s\",;]+)"; "\(.k)***MASKED***"; "i");
def mask_all: walk(if type == "string" then mask else . end);
