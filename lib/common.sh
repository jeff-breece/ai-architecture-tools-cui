#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  lib/common.sh — Shared utilities for Scripts Hub tools
#
#  Source this file from any tool script:
#    source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
#
#  Requires: IS_TTY, HAS_GUM, and colour vars (G/Y/R/C/B/D/X) to already be
#  set by the sourcing script.
# ─────────────────────────────────────────────────────────────────────────────

# ── Persistent state store ────────────────────────────────────────────────────
# State file: ~/.config/scripts-hub/state  (override with SCRIPTS_HUB_STATE env var)
# Format: KEY=value (one per line)
# Keys are namespaced by tool, e.g. pack-context.last_dir
_HUB_STATE="${SCRIPTS_HUB_STATE:-${HOME}/.config/scripts-hub/state}"

# state_get KEY → prints value, returns 1 if not found
state_get() {
  [[ -f "$_HUB_STATE" ]] || return 1
  local val
  val="$(grep -m1 "^${1}=" "$_HUB_STATE" 2>/dev/null | cut -d= -f2-)"
  [[ -n "$val" ]] || return 1
  printf '%s' "$val"
}

# state_set KEY VALUE
state_set() {
  mkdir -p "$(dirname "$_HUB_STATE")"
  if [[ -f "$_HUB_STATE" ]] && grep -q "^${1}=" "$_HUB_STATE" 2>/dev/null; then
    # Update in-place — use a temp file for portability
    local tmp; tmp="$(mktemp)"
    sed "s|^${1}=.*|${1}=${2}|" "$_HUB_STATE" > "$tmp" && mv "$tmp" "$_HUB_STATE"
  else
    printf '%s=%s\n' "$1" "$2" >> "$_HUB_STATE"
  fi
}

# ── prompt_dir ────────────────────────────────────────────────────────────────
# Interactive prompt for a directory path.
# - First run (no state): blank field — user must type a path.
# - Repeat run: pre-filled (gum) or "Enter to keep" (text) with the last-used path.
# - Last-used path is persisted per tool in the state store.
# - Override state file with SCRIPTS_HUB_STATE env var (used by tests for isolation).
#
# Usage:
#   prompt_dir VARNAME LABEL STATE_KEY
#
# Returns 1 if the user cancels, enters nothing, or enters a non-directory path.
prompt_dir() {
  local _varname="$1" _label="${2:-Target directory}" _key="${3:-hub.last_dir}"

  # Try to get last-used dir from state — empty string if none saved or invalid
  local _last=""
  _last="$(state_get "$_key" 2>/dev/null)" || _last=""
  # URL-decode stored path (e.g. %20 → space) before using as display/default
  if [[ "$_last" == *%[0-9A-Fa-f][0-9A-Fa-f]* ]]; then
    _last="$(python3 -c \
      "import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]),end='')" \
      "$_last" 2>/dev/null)" || true
  fi
  [[ -d "$_last" ]] || _last=""

  local _chosen=""
  if [[ "${HAS_GUM:-0}" -eq 1 ]]; then
    if [[ -n "$_last" ]]; then
      # Repeat run: show last-used as info text, leave field blank (ghost hint)
      # so typing always replaces rather than concatenates with pre-filled text
      printf '\n  %s%s%s\n  %sLast used: %s%s\n' \
        "${Y:-}" "${_label}" "${X:-}" "${D:-}" "$_last" "${X:-}"
      _chosen="$(gum input \
        --placeholder "$_last" \
        --prompt "  › " \
        --prompt.foreground "#ffdd00" \
        --width 70 2>/dev/null)" || true
      [[ -z "$_chosen" ]] && _chosen="$_last"
    else
      # First run: print label + hint, blank field — user must type a path
      printf '\n  %s%s%s\n  %sEnter the full path and press ENTER:%s\n' \
        "${Y:-}" "${_label}" "${X:-}" "${D:-}" "${X:-}"
      _chosen="$(gum input \
        --placeholder "/path/to/repo" \
        --prompt "  › " \
        --prompt.foreground "#ffdd00" \
        --width 70 2>/dev/null)" || true
    fi
  else
    if [[ -n "$_last" ]]; then
      printf '\n  %s%s%s\n  Last used: %s%s%s\n' \
        "${Y:-}" "${_label}" "${X:-}" "${D:-}" "$_last" "${X:-}"
      printf '  Path [Enter to keep]: '
      read -r _chosen
      _chosen="${_chosen:-$_last}"
    else
      printf '\n  %s%s%s\n  Enter the full path:\n' "${Y:-}" "${_label}" "${X:-}"
      printf '  Path: '
      read -r _chosen
    fi
  fi

  # URL-decode %xx sequences (paths pasted from file managers / browsers)
  if [[ "$_chosen" == *%[0-9A-Fa-f][0-9A-Fa-f]* ]]; then
    _chosen="$(python3 -c \
      "import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]),end='')" \
      "$_chosen" 2>/dev/null)" || true
  fi

  # Expand ~ to $HOME
  _chosen="${_chosen/#\~/$HOME}"
  # Strip trailing slash
  _chosen="${_chosen%/}"

  if [[ -z "$_chosen" ]]; then
    printf '%s\n' "${R:-}  No path entered — cancelled.${X:-}" >&2
    return 1
  fi

  if [[ ! -d "$_chosen" ]]; then
    printf '%s\n' "${R:-}  Not a directory: ${_chosen}${X:-}" >&2
    return 1
  fi

  _chosen="$(cd "$_chosen" && pwd)"
  state_set "$_key" "$_chosen"
  # Assign to the caller's variable by name
  printf -v "$_varname" '%s' "$_chosen"
}
