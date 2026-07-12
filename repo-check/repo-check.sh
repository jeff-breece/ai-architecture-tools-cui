#!/usr/bin/env bash
# repo-check — Score repository health
set -uo pipefail
IS_TTY=0; [[ -t 1 ]] && IS_TTY=1
HAS_GUM=0; [[ "$IS_TTY" -eq 1 ]] && command -v gum >/dev/null 2>&1 && HAS_GUM=1
if [[ "$IS_TTY" -eq 1 ]]; then
  G=$'\e[32m' C=$'\e[36m' Y=$'\e[33m' R=$'\e[31m' B=$'\e[1m' D=$'\e[2m' X=$'\e[0m'
else
  G='' C='' Y='' R='' B='' D='' X=''
fi
print_rule() { printf '%s\n' "${G}  ──────────────────────────────────────────────────────────────${X}"; }
clr()        { [[ "$IS_TTY" -eq 1 ]] && printf '\033[2J\033[H'; }
banner() {
  clr; printf '\n'
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 3" \
      "R E P O   C H E C K" "" "Repository Health Score"
    printf '\n'
  else
    printf '%s\n' "${G}${B}  ################################################################${X}"
    printf '%s\n\n' "${G}${B}  #    R E P O   C H E C K                                      #${X}"
  fi
}
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  prompt_dir TARGET "Repository to check" "repo-check.last_dir" || exit 1
else
  TARGET="$(cd "$TARGET" && pwd)"
  state_set "repo-check.last_dir" "$TARGET"
fi
SCORE=0; MAX=0
check() {
  local label="$1" weight="$2"; shift 2
  MAX=$(( MAX + weight ))
  if "$@" >/dev/null 2>&1; then
    SCORE=$(( SCORE + weight ))
    printf "  ${G}  ✓${X}  %-45s ${D}+%d${X}\n" "$label" "$weight"
  else
    printf "  ${R}  ✗${X}  %-45s ${D}+0/%d${X}\n" "$label" "$weight"
  fi
}
exists() { [[ -f "$TARGET/$1" ]] || [[ -d "$TARGET/$1" ]]; }
main() {
  banner
  print_rule; printf "  ${B}HEALTH CHECK${X}  ${D}%s${X}\n" "$TARGET"; print_rule; printf '\n'
  check "README.md exists"                  10 exists "README.md"
  check ".gitignore exists"                  5 exists ".gitignore"
  check "LICENSE exists"                     5 exists "LICENSE"
  check "CHANGELOG exists"                   5 exists "CHANGELOG.md"
  check "Is a git repository"              10 bash -c "git -C '$TARGET' rev-parse --git-dir"
  check "Has at least one commit"            5 bash -c "git -C '$TARGET' log -1 2>/dev/null"
  check "Has git tags"                       5 bash -c "git -C '$TARGET' tag 2>/dev/null | grep -q ."
  check "tests/ directory exists"          10 bash -c "ls '$TARGET'/test* '$TARGET'/tests* 2>/dev/null"
  check ".github/ CI directory exists"       5 exists ".github"
  check "docs/ directory exists"             5 bash -c "ls '$TARGET'/doc* 2>/dev/null"
  check "ADR files exist"                    5 bash -c "find '$TARGET' -name 'ADR-*.md' 2>/dev/null | grep -q ."
  check "No FIXME/HACK in source"            5 bash -c "! grep -rn 'FIXME\|HACK\b' '$TARGET' --include='*.sh' --include='*.py' --include='*.js' 2>/dev/null"
  check ".editorconfig or formatter config"  5 bash -c "ls '$TARGET'/.editorconfig '$TARGET'/.prettierrc* 2>/dev/null"
  check "SETUP.md or CONTRIBUTING.md"        5 bash -c "ls '$TARGET'/SETUP.md '$TARGET'/CONTRIBUTING.md 2>/dev/null"
  check "RUNBOOK.md or ops guide"            5 bash -c "ls '$TARGET'/RUNBOOK.md '$TARGET'/OPERATIONS.md 2>/dev/null"
  printf '\n'; print_rule
  local pct=$(( SCORE * 100 / MAX ))
  local grade col
  if   (( pct >= 90 )); then grade="A"; col="${G}"
  elif (( pct >= 75 )); then grade="B"; col="${C}"
  elif (( pct >= 60 )); then grade="C"; col="${Y}"
  else                       grade="D"; col="${R}"
  fi
  printf "  ${B}SCORE${X}  ${col}${B}%d/%d (%d%%) — Grade: %s${X}\n" "$SCORE" "$MAX" "$pct" "$grade"
  print_rule; printf '\n'
}
main "$@"
