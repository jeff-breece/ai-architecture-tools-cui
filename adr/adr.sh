#!/usr/bin/env bash
# adr — Architecture Decision Record manager
# Usage: adr <command> [args]
#   new [TITLE]        Create new ADR from template
#   list               List all ADRs
#   search [TERM]      Search ADR content
#   status [N] [S]     Update status of ADR N to S
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
print_fail() { printf '%s\n' "${R}  [ FAIL ] ${1}${X}"; }
pause()      { printf '\n%s' "${Y}  Press ENTER...${X}"; read -r _; }
clr()        { [[ "$IS_TTY" -eq 1 ]] && printf '\033[2J\033[H'; }

banner() {
  clr; printf '\n'
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 3" \
      "A D R   M A N A G E R" "" "Architecture Decision Records"
    printf '\n'
  else
    printf '%s\n'   "${G}${B}  ################################################################${X}"
    printf '%s\n'   "${G}${B}  #    A D R   M A N A G E R                                    #${X}"
    printf '%s\n\n' "${G}${B}  ################################################################${X}"
  fi
}

ADR_DIR="${ADR_DIR:-./docs/adr}"
STATUSES=("Proposed" "Accepted" "Deprecated" "Superseded" "Rejected")

ensure_dir() { mkdir -p "$ADR_DIR"; }

next_number() {
  local max=0 n
  for f in "$ADR_DIR"/ADR-*.md; do
    [[ -f "$f" ]] || continue
    n="$(basename "$f" | grep -oE '[0-9]+' | head -1)"
    (( n > max )) && max=$n
  done
  printf '%03d' $(( max + 1 ))
}

cmd_new() {
  ensure_dir
  local title="${*}"
  if [[ -z "$title" ]]; then
    if [[ "$HAS_GUM" -eq 1 ]]; then
      title="$(gum input --placeholder "Short imperative title (e.g., Use PostgreSQL for persistence)" \
        --prompt "  ADR Title: " --prompt.foreground "#ffdd00" --width 60)"
    else
      printf "${Y}  ADR Title: ${X}"; read -r title
    fi
  fi
  [[ -z "$title" ]] && { print_warn "Title required."; return 1; }

  local status="Proposed"
  if [[ "$HAS_GUM" -eq 1 ]]; then
    status="$(printf '%s\n' "${STATUSES[@]}" | \
      gum choose --header "  Initial status:")" || status="Proposed"
  fi

  local num; num="$(next_number)"
  local slug; slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')"
  local filename="ADR-${num}-${slug}.md"
  local filepath="${ADR_DIR}/${filename}"
  local date; date="$(date '+%Y-%m-%d')"

  cat > "$filepath" << TEMPLATE
# ADR-${num}: ${title}

**Date:** ${date}
**Status:** ${status}
**Decision owner:** 
**Decision scope:** 

---

## Context

*What is the issue that we are seeing that is motivating this decision or change?*

## Decision

*What is the change that we're proposing and/or doing?*

## Consequences

*What becomes easier or more difficult to do and any risks introduced by the change?*

## Alternatives Considered

*What other options were evaluated?*
TEMPLATE

  print_ok "Created ${B}${filepath}${X}"
  if command -v "${EDITOR:-}" >/dev/null 2>&1; then
    "${EDITOR}" "$filepath"
  elif [[ "$HAS_GUM" -eq 1 ]]; then
    gum confirm "  Open in \$EDITOR?" && "${EDITOR:-vi}" "$filepath" || true
  fi
}

cmd_list() {
  ensure_dir
  local count=0
  printf '\n'; print_rule
  printf "  ${B}ADRs${X}  ${D}%s${X}\n" "$ADR_DIR"; print_rule; printf '\n'
  printf "  ${G}${B}%-8s  %-14s  %s${X}\n" "Number" "Status" "Title"
  printf "  ${G}%-8s  %-14s  %s${X}\n" "────────" "──────────────" "──────────────────────────────────────"
  local f num status title col
  for f in "$ADR_DIR"/ADR-*.md; do
    [[ -f "$f" ]] || { printf '\n  ${D}No ADRs found in %s${X}\n' "$ADR_DIR"; return; }
    num="$(basename "$f" | grep -oE 'ADR-[0-9]+')"
    status="$(grep -m1 '^\*\*Status:\*\*' "$f" | sed 's/\*\*Status:\*\*[[:space:]]*//')"
    title="$(head -1 "$f" | sed 's/^# //')"
    status="${status:-Unknown}"
    case "$status" in
      Accepted)   col="${G}" ;;
      Proposed)   col="${Y}" ;;
      Deprecated|Superseded|Rejected) col="${R}" ;;
      *)          col="${D}" ;;
    esac
    printf "  ${C}%-8s${X}  ${col}%-14s${X}  %s\n" "$num" "$status" "$title"
    count=$(( count + 1 ))
  done
  printf '\n  %d ADR(s)\n\n' "$count"
}

cmd_search() {
  local term="${*}"
  if [[ -z "$term" ]]; then
    if [[ "$HAS_GUM" -eq 1 ]]; then
      term="$(gum input --placeholder "Search term" --prompt "  Search: " --prompt.foreground "#ffdd00")"
    else
      printf "${Y}  Search: ${X}"; read -r term
    fi
  fi
  [[ -z "$term" ]] && return
  printf '\n'; print_rule; printf "  Search: ${B}%s${X}\n" "$term"; print_rule; printf '\n'
  grep -rli "$term" "$ADR_DIR"/*.md 2>/dev/null | while IFS= read -r f; do
    local num; num="$(basename "$f" | grep -oE 'ADR-[0-9]+')"
    local title; title="$(head -1 "$f" | sed 's/^# //')"
    printf "  ${C}%-10s${X} %s\n" "$num" "$title"
    grep -n --color=never "$term" "$f" | head -3 | while IFS= read -r line; do
      printf "  ${D}  %s${X}\n" "$line"
    done
    printf '\n'
  done
}

cmd_status() {
  local num="${1:-}" new_status="${2:-}"
  if [[ -z "$num" ]]; then
    local files=(); mapfile -t files < <(ls "$ADR_DIR"/ADR-*.md 2>/dev/null)
    [[ "${#files[@]}" -eq 0 ]] && { print_warn "No ADRs found."; return; }
    local choice
    if [[ "$HAS_GUM" -eq 1 ]]; then
      choice="$(printf '%s\n' "${files[@]}" | xargs -I{} basename {} | \
        gum choose --header "  Select ADR:")" || return
      num="$(printf '%s' "$choice" | grep -oE 'ADR-[0-9]+')"
    else
      cmd_list
      printf "${Y}  ADR number (e.g. 001): ${X}"; read -r num
      num="ADR-$num"
    fi
  fi

  local filepath; filepath="$(ls "$ADR_DIR"/${num}*.md 2>/dev/null | head -1)"
  [[ -z "$filepath" ]] && { print_fail "ADR not found: $num"; return 1; }

  if [[ -z "$new_status" ]]; then
    if [[ "$HAS_GUM" -eq 1 ]]; then
      new_status="$(printf '%s\n' "${STATUSES[@]}" | \
        gum choose --header "  New status for ${num}:")" || return
    else
      printf '%s\n' "${STATUSES[@]}" | nl -w2 -s') '
      printf "${Y}  New status: ${X}"; read -r new_status
    fi
  fi

  sed -i "s/^\*\*Status:\*\*.*/\*\*Status:\*\* ${new_status}/" "$filepath"
  print_ok "${num} status → ${B}${new_status}${X}"
}

usage() {
  printf 'Usage: %s <command>\n\n' "$(basename "$0")"
  printf '  new [TITLE]       Create a new ADR\n'
  printf '  list              List all ADRs\n'
  printf '  search [TERM]     Search ADR content\n'
  printf '  status [N] [S]    Update ADR status\n\n'
  printf 'Env: ADR_DIR (default: ./docs/adr)\n'
}

show_menu() {
  print_rule
  printf "  ${G}[1]${X}  new      Create a new ADR\n"
  printf "  ${G}[2]${X}  list     List all ADRs\n"
  printf "  ${G}[3]${X}  search   Search ADR content\n"
  printf "  ${G}[4]${X}  status   Update ADR status\n"
  printf "  ${R}[q]${X}  Exit\n"
  print_rule; printf '\n'
  printf "${Y}  Choice: ${X}"
}

interactive() {
  local choice
  while true; do
    banner
    show_menu
    read -r choice
    case "$choice" in
      1) cmd_new ;;
      2) cmd_list; pause ;;
      3) cmd_search ;;
      4) cmd_status ;;
      q|Q|'') break ;;
      *) ;;
    esac
  done
}

main() {
  local cmd="${1:-}"; [[ $# -gt 0 ]] && shift
  case "$cmd" in
    new)      banner; cmd_new "$@" ;;
    list)     banner; cmd_list ;;
    search)   banner; cmd_search "$@" ;;
    status)   banner; cmd_status "$@" ;;
    -h|--help) banner; usage ;;
    '')       interactive ;;
    *) printf 'Unknown command: %s\n' "$cmd"; usage; exit 1 ;;
  esac
}

main "$@"
