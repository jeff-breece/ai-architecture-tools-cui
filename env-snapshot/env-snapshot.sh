#!/usr/bin/env bash
# env-snapshot — Capture current development environment
# Usage: env-snapshot [-o FILE]
set -uo pipefail
IS_TTY=0; [[ -t 1 ]] && IS_TTY=1
HAS_GUM=0; [[ "$IS_TTY" -eq 1 ]] && command -v gum >/dev/null 2>&1 && HAS_GUM=1
if [[ "$IS_TTY" -eq 1 ]]; then
  G=$'\e[32m' B=$'\e[1m' X=$'\e[0m'
else
  G='' B='' X=''
fi
print_ok()   { printf '%s\n' "${G}  [  OK  ]${X} ${1}"; }
print_rule() { printf '%s\n' "${G}  ──────────────────────────────────────────────────────────────${X}"; }
clr()        { [[ "$IS_TTY" -eq 1 ]] && printf '\033[2J\033[H'; }
banner() {
  clr; printf '\n'
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 3" \
      "E N V   S N A P S H O T" "" "Dev Environment Capture"
    printf '\n'
  fi
}
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in -o|--output) OUTPUT="$2"; shift 2 ;; *) shift ;; esac
done
generate() {
  printf '# Environment Snapshot\n'
  printf '# Generated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf '# Host: %s\n\n' "$(hostname)"
  printf '## OS\n\n```\n'
  uname -a 2>/dev/null || true
  [[ -f /etc/os-release ]] && grep -E '^(NAME|VERSION)=' /etc/os-release | tr -d '"'
  printf '```\n\n## Runtimes\n\n| Tool | Version |\n|---|---|\n'
  for t in python3 node npm go java rust; do
    v="$(command -v "$t" >/dev/null 2>&1 && "$t" --version 2>&1 | head -1 || printf 'not installed')"
    printf '| `%s` | %s |\n' "$t" "$v"
  done
  printf '\n## Tools\n\n| Tool | Version |\n|---|---|\n'
  for t in git pandoc mmdc gum fzf jq docker make; do
    v="$(command -v "$t" >/dev/null 2>&1 && "$t" --version 2>&1 | head -1 || printf 'not installed')"
    printf '| `%s` | %s |\n' "$t" "$v"
  done
  printf '\n## PATH\n\n```\n'
  printf '%s\n' "$PATH" | tr ':' '\n'
  printf '```\n'
}
main() {
  [[ "$IS_TTY" -eq 1 ]] && banner
  local out
  if [[ "$HAS_GUM" -eq 1 ]]; then
    local tmp; tmp="$(mktemp)"
    gum spin --title "  Capturing environment..." -- bash -c "$(declare -f generate); generate > '${tmp}'"
    out="$(cat "$tmp")"; rm -f "$tmp"
  else
    out="$(generate)"
  fi
  if [[ -n "$OUTPUT" ]]; then
    printf '%s\n' "$out" > "$OUTPUT"
    print_ok "Written to ${B}${OUTPUT}${X}"
  else
    printf '%s\n' "$out"
  fi
}
main "$@"
