#!/usr/bin/env bash
# git-brief — Format git log/diff as an AI-ready brief
# Usage: git-brief [REPO_DIR] [OPTIONS]
#   -n, --count N        Last N commits (default: 20)
#   -s, --since REF      Since tag/sha/date (overrides --count)
#   -f, --format TYPE    log | diff | both (default: both)
#   -o, --output FILE    Write to file
#       --no-diff        Alias for -f log
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
print_fail() { printf '%s\n' "${R}  [ FAIL ] ${1}${X}"; }
clr()        { [[ "$IS_TTY" -eq 1 ]] && printf '\033[2J\033[H'; }

banner() {
  clr; printf '\n'
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 3" \
      "G I T   B R I E F" "" "AI-Ready Git Summary"
    printf '\n'
  else
    printf '%s\n'   "${G}${B}  ################################################################${X}"
    printf '%s\n'   "${G}${B}  #    G I T   B R I E F                                        #${X}"
    printf '%s\n\n' "${G}${B}  ################################################################${X}"
  fi
}

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
REPO_DIR=""
COUNT=20
SINCE=""
FORMAT="both"
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--count)   COUNT="$2"; shift 2 ;;
    -s|--since)   SINCE="$2"; shift 2 ;;
    -f|--format)  FORMAT="$2"; shift 2 ;;
    -o|--output)  OUTPUT_FILE="$2"; shift 2 ;;
    --no-diff)    FORMAT="log"; shift ;;
    -h|--help)
      printf 'Usage: %s [DIR] [-n N] [-s REF] [-f log|diff|both] [-o FILE]\n' "$(basename "$0")"; exit 0 ;;
    -*) printf 'Unknown: %s\n' "$1"; exit 1 ;;
    *)  REPO_DIR="$1"; shift ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  prompt_dir REPO_DIR "Repository root" "git-brief.last_dir" || exit 1
else
  REPO_DIR="$(cd "$REPO_DIR" && pwd)"
  state_set "git-brief.last_dir" "$REPO_DIR"
fi
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || { printf '%s\n' "${R}  Not a git repo: ${REPO_DIR}${X}"; exit 1; }

# ── Build brief ───────────────────────────────────────────────────────────────
build_brief() {
  local repo_name; repo_name="$(basename "$REPO_DIR")"
  local branch; branch="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  local ts; ts="$(date '+%Y-%m-%d %H:%M')"

  # Resolve range
  local range=""
  if [[ -n "$SINCE" ]]; then
    range="${SINCE}..HEAD"
  else
    local last_tag; last_tag="$(git -C "$REPO_DIR" describe --tags --abbrev=0 2>/dev/null)" || true
    if [[ -n "$last_tag" ]]; then
      range="${last_tag}..HEAD"
    else
      range="HEAD~${COUNT}..HEAD"
    fi
  fi

  printf '# GIT BRIEF\n'
  printf '# Repo:   %s\n' "$repo_name"
  printf '# Branch: %s\n' "$branch"
  printf '# Range:  %s\n' "$range"
  printf '# Date:   %s\n' "$ts"
  printf '# ─────────────────────────────────────────────────────\n\n'

  if [[ "$FORMAT" == "log" || "$FORMAT" == "both" ]]; then
    printf '## COMMIT LOG\n\n'

    # Group by conventional commit type if possible
    local has_conventional=0
    git -C "$REPO_DIR" log "$range" --oneline 2>/dev/null \
      | grep -qE '^[a-f0-9]+ (feat|fix|docs|chore|refactor|test|style|ci|perf|build)(\(.+\))?:' \
      && has_conventional=1

    if [[ "$has_conventional" -eq 1 ]]; then
      for type in feat fix docs refactor test chore ci perf build style; do
        local commits
        commits="$(git -C "$REPO_DIR" log "$range" --oneline 2>/dev/null \
          | grep -E "^[a-f0-9]+ ${type}(\(.+\))?:" || true)"
        if [[ -n "$commits" ]]; then
          printf '### %s\n\n' "$(printf '%s' "$type" | tr '[:lower:]' '[:upper:]')"
          while IFS= read -r line; do
            printf '%s\n' "- $line"
          done <<< "$commits"
          printf '\n'
        fi
      done
    else
      git -C "$REPO_DIR" log "$range" \
        --format='- %h %s  (%an, %ar)' 2>/dev/null | head -100
      printf '\n'
    fi

    printf '## STATS\n\n```\n'
    git -C "$REPO_DIR" diff --stat "$range" 2>/dev/null | tail -5
    printf '```\n\n'
  fi

  if [[ "$FORMAT" == "diff" || "$FORMAT" == "both" ]]; then
    printf '## DIFF\n\n```diff\n'
    git -C "$REPO_DIR" diff "$range" 2>/dev/null | head -2000
    printf '```\n'
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  [[ "$IS_TTY" -eq 1 ]] && banner

  local tmp; tmp="$(mktemp)"

  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum spin --title "  Generating brief..." -- bash -c "
      $(declare -f build_brief)
      REPO_DIR='${REPO_DIR}' SINCE='${SINCE}' COUNT='${COUNT}' FORMAT='${FORMAT}' build_brief > '${tmp}'
    "
  else
    [[ "$IS_TTY" -eq 1 ]] && printf '%s\n' "${Y}  Generating...${X}"
    build_brief > "$tmp"
  fi

  if [[ -n "$OUTPUT_FILE" ]]; then
    cp "$tmp" "$OUTPUT_FILE"
    print_ok "Written to ${B}${OUTPUT_FILE}${X}"
  else
    cat "$tmp"
  fi
  rm -f "$tmp"
}

main "$@"
