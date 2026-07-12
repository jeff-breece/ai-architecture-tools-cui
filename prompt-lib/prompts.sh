#!/usr/bin/env bash
# prompts — Prompt library manager
# Usage: prompts [COMMAND]
#   list / search    Browse and copy prompts
#   add [NAME]       Add a new prompt
#   edit [NAME]      Edit existing prompt
#   delete [NAME]    Delete a prompt
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
pause()      { printf '\n%s' "${Y}  Press ENTER...${X}"; read -r _; }

banner() {
  clr; printf '\n'
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 3" \
      "P R O M P T   L I B R A R Y" "" "Store · Search · Copy"
    printf '\n'
  else
    printf '%s\n'   "${G}${B}  ################################################################${X}"
    printf '%s\n'   "${G}${B}  #    P R O M P T   L I B R A R Y                              #${X}"
    printf '%s\n\n' "${G}${B}  ################################################################${X}"
  fi
}

PROMPT_DIR="${PROMPT_DIR:-${HOME}/.config/scripts-hub/prompts}"
mkdir -p "$PROMPT_DIR"

copy_to_clipboard() {
  local text="$1"
  if command -v xclip >/dev/null 2>&1; then
    printf '%s' "$text" | xclip -selection clipboard && print_ok "Copied to clipboard"
  elif command -v xsel >/dev/null 2>&1; then
    printf '%s' "$text" | xsel --clipboard --input && print_ok "Copied to clipboard"
  elif command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$text" | pbcopy && print_ok "Copied to clipboard"
  else
    print_warn "No clipboard tool found (install xclip)"
  fi
}

cmd_browse() {
  local files=(); mapfile -t files < <(ls "$PROMPT_DIR"/*.md "$PROMPT_DIR"/*.txt 2>/dev/null | sort)
  if [[ "${#files[@]}" -eq 0 ]]; then
    print_info "No prompts yet."
    printf "${Y}  Add your first prompt now? [y/N] ${X}"; read -r yn
    [[ "$yn" =~ ^[Yy] ]] && cmd_add
    return
  fi

  local names=()
  for f in "${files[@]}"; do names+=("$(basename "${f%.*}")"); done

  local chosen
  if [[ "$HAS_GUM" -eq 1 ]]; then
    chosen="$(printf '%s\n' "${names[@]}" | \
      gum filter --placeholder "Search prompts..." \
        --prompt "  > " --prompt.foreground "#ffdd00" \
        --header "  Select a prompt:" \
        --header.foreground "#33bb55")" || return
  else
    print_rule; printf '%s\n' "${B}  PROMPTS${X}"; print_rule; printf '\n'
    local i=1
    for name in "${names[@]}"; do
      printf "  ${G}[%d]${X} %s\n" "$i" "$name"; i=$(( i+1 ))
    done
    printf '\n'; printf "${Y}  Select (number): ${X}"; read -r idx
    [[ "$idx" =~ ^[0-9]+$ ]] || return
    chosen="${names[$(( idx-1 ))]}"
  fi

  [[ -z "$chosen" ]] && return
  local filepath
  filepath="$(ls "$PROMPT_DIR"/"${chosen}".* 2>/dev/null | head -1)"
  [[ -z "$filepath" ]] && return

  local content; content="$(cat "$filepath")"
  printf '\n'; print_rule; printf "  ${B}%s${X}\n" "$chosen"; print_rule; printf '\n'
  printf '%s\n\n' "$content"
  print_rule

  local action="Copy"
  if [[ "$HAS_GUM" -eq 1 ]]; then
    action="$(printf 'Copy to clipboard\nEdit\nDelete\nBack' | \
      gum choose --header "  Action:")" || action="Back"
  else
    printf "  ${G}[c]${X} Copy  ${G}[e]${X} Edit  ${G}[d]${X} Delete  ${G}[b]${X} Back\n"
    printf "${Y}  > ${X}"; read -r a
    case "$a" in c|C) action="Copy to clipboard" ;; e|E) action="Edit" ;; d|D) action="Delete" ;; *) action="Back" ;; esac
  fi

  case "$action" in
    "Copy"*) copy_to_clipboard "$content" ;;
    "Edit")  "${EDITOR:-vi}" "$filepath" ;;
    "Delete")
      rm -f "$filepath"; print_ok "Deleted ${chosen}" ;;
  esac
}

cmd_add() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    if [[ "$HAS_GUM" -eq 1 ]]; then
      name="$(gum input --placeholder "prompt-name (no spaces)" \
        --prompt "  Name: " --prompt.foreground "#ffdd00")"
    else
      printf "${Y}  Name: ${X}"; read -r name
    fi
  fi
  [[ -z "$name" ]] && return
  name="$(printf '%s' "$name" | tr ' ' '-' | tr -cd '[:alnum:]-_')"
  local filepath="${PROMPT_DIR}/${name}.md"
  [[ -f "$filepath" ]] && { print_warn "Prompt '${name}' already exists. Use 'edit' to modify it."; return; }

  cat > "$filepath" << TEMPLATE
# ${name}

<!-- Tags: general -->
<!-- Model: gpt-4 / claude -->

TEMPLATE

  "${EDITOR:-vi}" "$filepath"
  print_ok "Saved ${B}${filepath}${X}"
}

main() {
  local cmd="${1:-}"; [[ $# -gt 0 ]] && shift
  case "$cmd" in
    add)    banner; cmd_add "$@" ;;
    edit)   banner; local f="${PROMPT_DIR}/${1:-}.md"; [[ -f "$f" ]] && "${EDITOR:-vi}" "$f" || cmd_browse ;;
    delete) banner; local f; f="$(ls "$PROMPT_DIR"/"${1:-}"* 2>/dev/null | head -1)"; [[ -f "$f" ]] && rm -f "$f" && print_ok "Deleted" || print_warn "Not found" ;;
    list|search|browse) banner; cmd_browse ;;
    -h|--help)
      printf 'Usage: %s [list|add|edit|delete]\n' "$(basename "$0")"
      printf 'Env: PROMPT_DIR (default: ~/.config/scripts-hub/prompts)\n' ;;
    '') interactive ;;
    *)  banner; cmd_browse ;;
  esac
}

show_menu() {
  print_rule
  printf "  ${G}[1]${X}  Browse / search prompts\n"
  printf "  ${G}[2]${X}  Add a new prompt\n"
  printf "  ${R}[q]${X}  Exit\n"
  print_rule; printf '\n'
  printf "${Y}  Choice: ${X}"
}

interactive() {
  local choice
  while true; do
    banner
    local count; count="$(ls "$PROMPT_DIR"/*.md "$PROMPT_DIR"/*.txt 2>/dev/null | wc -l)"
    printf "  ${D}%d prompt(s) stored in %s${X}\n\n" "$count" "$PROMPT_DIR"
    show_menu
    read -r choice
    case "$choice" in
      1) cmd_browse; pause ;;
      2) cmd_add; pause ;;
      q|Q|'') break ;;
      *) ;;
    esac
  done
}

main "$@"
