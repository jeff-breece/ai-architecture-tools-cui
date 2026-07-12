#!/usr/bin/env bash
# changelog — Generate CHANGELOG.md from git commits
# Usage: changelog [REPO_DIR] [-o FILE] [-s SINCE] [--append]
set -uo pipefail

IS_TTY=0; [[ -t 1 ]] && IS_TTY=1
HAS_GUM=0; [[ "$IS_TTY" -eq 1 ]] && command -v gum >/dev/null 2>&1 && HAS_GUM=1
if [[ "$IS_TTY" -eq 1 ]]; then
  G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' C=$'\e[36m' B=$'\e[1m' D=$'\e[2m' X=$'\e[0m'
else
  G='' Y='' R='' C='' B='' D='' X=''
fi
print_ok()   { printf '%s\n' "${G}  [  OK  ]${X} ${1}"; }
print_rule() { printf '%s\n' "${G}  ──────────────────────────────────────────────────────────────${X}"; }
clr()        { [[ "$IS_TTY" -eq 1 ]] && printf '\033[2J\033[H'; }

banner() {
  clr; printf '\n'
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 3" \
      "C H A N G E L O G" "" "Git → Markdown Release Notes"
    printf '\n'
  else
    printf '%s\n'   "${G}${B}  ################################################################${X}"
    printf '%s\n'   "${G}${B}  #    C H A N G E L O G   G E N E R A T O R                   #${X}"
    printf '%s\n\n' "${G}${B}  ################################################################${X}"
  fi
}

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

REPO_DIR="" OUTPUT_FILE="" SINCE="" APPEND=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
    -s|--since)  SINCE="$2"; shift 2 ;;
    --append)    APPEND=1; shift ;;
    -h|--help)   printf 'Usage: %s [DIR] [-o FILE] [-s REF] [--append]\n' "$(basename "$0")"; exit 0 ;;
    -*) printf 'Unknown: %s\n' "$1"; exit 1 ;;
    *)  REPO_DIR="$1"; shift ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  prompt_dir REPO_DIR "Repository root" "changelog.last_dir" || exit 1
else
  REPO_DIR="$(cd "$REPO_DIR" && pwd)"
  state_set "changelog.last_dir" "$REPO_DIR"
fi
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || { printf 'Not a git repo: %s\n' "$REPO_DIR"; exit 1; }

generate() {
  local range=""
  if [[ -n "$SINCE" ]]; then
    range="${SINCE}..HEAD"
  else
    local last; last="$(git -C "$REPO_DIR" describe --tags --abbrev=0 2>/dev/null)" || true
    range="${last:+${last}..HEAD}"
  fi

  local version; version="$(git -C "$REPO_DIR" describe --tags --abbrev=0 2>/dev/null)" || version="Unreleased"
  local date; date="$(date '+%Y-%m-%d')"
  local repo; repo="$(basename "$REPO_DIR")"

  printf '# Changelog — %s\n\n' "$repo"
  printf '## [%s] — %s\n\n' "$version" "$date"

  declare -A SECTIONS
  SECTIONS=(
    [feat]="### ✨ Features"
    [fix]="### 🐛 Bug Fixes"
    [docs]="### 📚 Documentation"
    [refactor]="### ♻️  Refactoring"
    [perf]="### ⚡ Performance"
    [test]="### 🧪 Tests"
    [ci]="### 🔧 CI/CD"
    [build]="### 🏗️  Build"
    [chore]="### 🔨 Chores"
  )

  declare -A ENTRIES
  local printed_other=0

  while IFS= read -r line; do
    local sha="${line%% *}"
    local msg="${line#* }"
    if [[ "$msg" =~ ^([a-z]+)([\(][^\)]+[\)])?(!)?:\ (.+)$ ]]; then
      local type="${BASH_REMATCH[1]}"
      local scope="${BASH_REMATCH[2]}"
      local breaking="${BASH_REMATCH[3]}"
      local desc="${BASH_REMATCH[4]}"
      local entry="- ${breaking:+**BREAKING:** }${scope:+\`${scope:1:-1}\` }${desc}  \`${sha}\`"
      ENTRIES[$type]+="${entry}"$'\n'
    else
      ENTRIES[other]+="- ${msg}  \`${sha}\`"$'\n'
    fi
  done < <(git -C "$REPO_DIR" log ${range} --format='%h %s' 2>/dev/null | head -500)

  for type in feat fix docs refactor perf test ci build chore; do
    if [[ -n "${ENTRIES[$type]:-}" ]]; then
      printf '%s\n\n' "${SECTIONS[$type]}"
      printf '%s\n' "${ENTRIES[$type]}"
    fi
  done

  if [[ -n "${ENTRIES[other]:-}" ]]; then
    printf '### 📦 Other\n\n%s\n' "${ENTRIES[other]}"
  fi
}

main() {
  [[ "$IS_TTY" -eq 1 ]] && banner
  local output
  if [[ "$HAS_GUM" -eq 1 ]]; then
    local tmp; tmp="$(mktemp)"
    gum spin --title "  Generating changelog..." -- bash -c "
      $(declare -f generate)
      REPO_DIR='${REPO_DIR}' SINCE='${SINCE}' generate > '${tmp}'
    "
    output="$(cat "$tmp")"; rm -f "$tmp"
  else
    output="$(generate)"
  fi

  if [[ -n "$OUTPUT_FILE" ]]; then
    if [[ "$APPEND" -eq 1 && -f "$OUTPUT_FILE" ]]; then
      printf '%s\n\n---\n\n%s' "$output" "$(cat "$OUTPUT_FILE")" > "$OUTPUT_FILE"
    else
      printf '%s\n' "$output" > "$OUTPUT_FILE"
    fi
    print_ok "Written to ${B}${OUTPUT_FILE}${X}"
  else
    printf '%s\n' "$output"
  fi
}

main "$@"
