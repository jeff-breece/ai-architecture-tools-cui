#!/usr/bin/env bash
# pack-context — Package a repo/dir into an AI-ready context bundle
# Usage: pack-context [DIR] [OPTIONS]
#   -o, --output FILE    Write to file instead of stdout
#   -x, --exclude PAT    Glob patterns to exclude (repeatable)
#   -m, --max-kb N       Skip files larger than N KB (default: 100)
#   -e, --ext LIST       Comma-separated extensions to include (default: auto)
#       --no-tree        Skip directory tree
#       --no-tokens      Skip token count
set -uo pipefail

IS_TTY=0; [[ -t 1 ]] && IS_TTY=1
HAS_GUM=0; [[ "$IS_TTY" -eq 1 ]] && command -v gum >/dev/null 2>&1 && HAS_GUM=1
if [[ "$IS_TTY" -eq 1 ]]; then
  G=$'\e[32m' C=$'\e[36m' Y=$'\e[33m' R=$'\e[31m'
  B=$'\e[1m'  D=$'\e[2m'  X=$'\e[0m'
else
  G='' C='' Y='' R='' B='' D='' X=''
fi

print_rule() { printf '%s\n' "${G}  ──────────────────────────────────────────────────────────────${X}"; }
print_ok()   { printf '%s\n' "${G}  [  OK  ]${X} ${1}"; }
print_info() { printf '%s\n' "${C}  [ INFO ]${X} ${1}"; }
print_warn() { printf '%s\n' "${Y}  [ WARN ]${X} ${Y}${1}${X}"; }
clr()        { [[ "$IS_TTY" -eq 1 ]] && printf '\033[2J\033[H'; }

banner() {
  clr; printf '\n'
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 3" \
      "P A C K   C O N T E X T" "" "AI-Ready Repo Bundler"
    printf '\n'
  else
    printf '%s\n' "${G}${B}  ################################################################${X}"
    printf '%s\n' "${G}${B}  #    P A C K   C O N T E X T                                  #${X}"
    printf '%s\n' "${G}${B}  #    AI-Ready Repo Bundler                                     #${X}"
    printf '%s\n\n' "${G}${B}  ################################################################${X}"
  fi
}

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
TARGET_DIR=""
OUTPUT_FILE=""
MAX_KB=100
NO_TREE=0
NO_TOKENS=0
declare -a EXCLUDES=('.git' 'node_modules' '__pycache__' '.venv' 'venv' '*.pyc' '*.png' '*.jpg' '*.jpeg' '*.gif' '*.pdf' '*.docx' '*.xlsx' '*.zip' '*.tar*' '*.exe' '*.bin' 'package-lock.json' 'yarn.lock' '.DS_Store')
declare -a EXTRA_EXCLUDES=()
INCLUDE_EXTS=""

# ── Arg parse ─────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)   OUTPUT_FILE="$2"; shift 2 ;;
    -x|--exclude)  EXTRA_EXCLUDES+=("$2"); shift 2 ;;
    -m|--max-kb)   MAX_KB="$2"; shift 2 ;;
    -e|--ext)      INCLUDE_EXTS="$2"; shift 2 ;;
    --no-tree)     NO_TREE=1; shift ;;
    --no-tokens)   NO_TOKENS=1; shift ;;
    -h|--help)
      printf 'Usage: %s [DIR] [-o FILE] [-x PATTERN] [-m KB] [-e exts] [--no-tree] [--no-tokens]\n' "$(basename "$0")"
      exit 0 ;;
    -*) printf 'Unknown option: %s\n' "$1"; exit 1 ;;
    *)  TARGET_DIR="$1"; shift ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  prompt_dir TARGET_DIR "Repository to pack" "pack-context.last_dir" || exit 1
else
  TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
  state_set "pack-context.last_dir" "$TARGET_DIR"
fi
[[ -d "$TARGET_DIR" ]] || { printf 'Not a directory: %s\n' "$TARGET_DIR"; exit 1; }

EXCLUDES+=("${EXTRA_EXCLUDES[@]}")

# ── File collection ───────────────────────────────────────────────────────────
is_excluded() {
  local f="$1" pat
  for pat in "${EXCLUDES[@]}"; do
    case "$f" in *"$pat"*) return 0 ;; esac
    [[ "$f" == $pat ]] && return 0
  done
  return 1
}

collect_files() {
  local find_args=("$TARGET_DIR" -type f -size "-${MAX_KB}k")
  if [[ -n "$INCLUDE_EXTS" ]]; then
    local -a ext_args=()
    IFS=',' read -ra exts <<< "$INCLUDE_EXTS"
    local first=1
    for ext in "${exts[@]}"; do
      [[ "$first" -eq 0 ]] && ext_args+=("-o")
      ext_args+=("-iname" "*.${ext// /}")
      first=0
    done
    find_args+=("(" "${ext_args[@]}" ")")
  fi
  local f
  while IFS= read -r -d '' f; do
    local rel="${f#${TARGET_DIR}/}"
    is_excluded "$rel" && continue
    # Skip binary files
    file "$f" 2>/dev/null | grep -qiE 'binary|data|executable' && continue
    printf '%s\n' "$f"
  done < <(find "${find_args[@]}" -print0 | sort -z)
}

# ── Token counting ────────────────────────────────────────────────────────────
count_tokens_file() {
  python3 - "$1" << 'PY'
import sys
try:
    import tiktoken
    enc = tiktoken.get_encoding("cl100k_base")
    text = open(sys.argv[1], 'r', errors='replace').read()
    print(len(enc.encode(text)))
except Exception:
    text = open(sys.argv[1], 'r', errors='replace').read()
    print(int(len(text.split()) * 1.35))
PY
}

count_tokens_text() {
  python3 - "$1" << 'PY'
import sys
try:
    import tiktoken
    enc = tiktoken.get_encoding("cl100k_base")
    print(len(enc.encode(sys.argv[1])))
except Exception:
    print(int(len(sys.argv[1].split()) * 1.35))
PY
}

# ── Build bundle ──────────────────────────────────────────────────────────────
build_bundle() {
  local repo_name; repo_name="$(basename "$TARGET_DIR")"
  local ts; ts="$(date '+%Y-%m-%d %H:%M')"
  local git_branch=""
  git_branch="$(git -C "$TARGET_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)" || true
  local git_sha=""
  git_sha="$(git -C "$TARGET_DIR" rev-parse --short HEAD 2>/dev/null)" || true

  mapfile -t FILES < <(collect_files)
  local file_count="${#FILES[@]}"

  {
    printf '# AI CONTEXT BUNDLE\n'
    printf '# Repo: %s\n' "$repo_name"
    printf '# Date: %s\n' "$ts"
    [[ -n "$git_branch" ]] && printf '# Branch: %s  SHA: %s\n' "$git_branch" "$git_sha"
    printf '# Files: %d\n' "$file_count"
    printf '# ─────────────────────────────────────────────────────\n\n'

    if [[ "$NO_TREE" -eq 0 ]] && command -v tree >/dev/null 2>&1; then
      printf '## DIRECTORY TREE\n\n```\n'
      tree -a --gitignore -I '.git' "$TARGET_DIR" 2>/dev/null | head -200
      printf '```\n\n'
    elif [[ "$NO_TREE" -eq 0 ]]; then
      printf '## DIRECTORY TREE\n\n```\n'
      find "$TARGET_DIR" -not -path '*/.git/*' -not -name '.git' \
        | sed "s|${TARGET_DIR}/||" | sort | head -200
      printf '```\n\n'
    fi

    printf '## FILE CONTENTS\n\n'
    local f rel
    for f in "${FILES[@]}"; do
      rel="${f#${TARGET_DIR}/}"
      local ext="${f##*.}"
      printf '### %s\n\n```%s\n' "$rel" "$ext"
      cat "$f"
      printf '\n```\n\n'
    done
  }
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  if [[ "$IS_TTY" -eq 1 ]]; then
    banner
    print_rule
    printf "  ${B}TARGET${X}   %s\n" "$TARGET_DIR"
    printf "  ${B}MAX SIZE${X} %s KB per file\n" "$MAX_KB"
    [[ -n "$OUTPUT_FILE" ]] && printf "  ${B}OUTPUT${X}   %s\n" "$OUTPUT_FILE"
    print_rule; printf '\n'
  fi

  local tmp; tmp="$(mktemp)"

  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum spin --title "  Packing context..." -- bash -c "
      $(declare -f collect_files is_excluded count_tokens_file build_bundle)
      TARGET_DIR='${TARGET_DIR}' NO_TREE=${NO_TREE} NO_TOKENS=${NO_TOKENS} \
        build_bundle > '${tmp}'
    "
  else
    printf '%s\n' "${Y}  Packing...${X}"
    build_bundle > "$tmp"
  fi

  local line_count; line_count="$(wc -l < "$tmp")"
  local char_count; char_count="$(wc -c < "$tmp")"

  local tokens=0
  if [[ "$NO_TOKENS" -eq 0 ]]; then
    tokens="$(count_tokens_file "$tmp")"
  fi

  if [[ -n "$OUTPUT_FILE" ]]; then
    cp "$tmp" "$OUTPUT_FILE"
    print_ok "Written to ${B}${OUTPUT_FILE}${X}"
  else
    cat "$tmp"
  fi
  rm -f "$tmp"

  if [[ "$IS_TTY" -eq 1 ]]; then
    printf '\n'; print_rule
    printf "  ${G}${B}%s lines${X}  ${C}%s chars${X}" "$line_count" "$char_count"
    [[ "$NO_TOKENS" -eq 0 ]] && printf "  ${Y}~%s tokens${X}" "$tokens"
    printf '\n'; print_rule
  fi
}

main "$@"
