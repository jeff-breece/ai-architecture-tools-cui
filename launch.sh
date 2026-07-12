#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  launch.sh — Scripts Hub  (entry point for all developer utilities)
# ─────────────────────────────────────────────────────────────────────────────
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IS_TTY=0; [[ -t 1 ]] && IS_TTY=1
HAS_GUM=0; [[ "$IS_TTY" -eq 1 ]] && command -v gum >/dev/null 2>&1 && HAS_GUM=1

if [[ "$IS_TTY" -eq 1 ]]; then
  G=$'\e[32m' C=$'\e[36m' Y=$'\e[33m' R=$'\e[31m'
  B=$'\e[1m'  D=$'\e[2m'  X=$'\e[0m'
else
  G='' C='' Y='' R='' B='' D='' X=''
fi

# Shared gum theme (inherited by child scripts)
export GUM_CHOOSE_CURSOR="▶ "
export GUM_CHOOSE_CURSOR_FOREGROUND="#00cc44"
export GUM_CHOOSE_HEADER_FOREGROUND="#33bb55"
export GUM_CHOOSE_SELECTED_FOREGROUND="#00ff66"
export GUM_CONFIRM_PROMPT_FOREGROUND="#ffdd00"
export GUM_CONFIRM_SELECTED_FOREGROUND="#00cc44"
export GUM_SPIN_SPINNER="dot"
export GUM_SPIN_SPINNER_FOREGROUND="#00cc44"

clr() { [[ "$IS_TTY" -eq 1 ]] && printf '\033[2J\033[H'; }
print_rule() { printf '%s\n' "${G}  ──────────────────────────────────────────────────────────────${X}"; }

draw_header() {
  clr; printf '\n'
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style \
      --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 4" \
      "S C R I P T S   H U B" "" \
      "AI & Developer Utilities" "v 1.0"
    printf '\n'
  else
    local W=62
    local LINE="  $(printf '%.0s#' {1..64})"
    printf '%s' "${G}${B}"
    printf '%s\n'         "$LINE"
    printf "  #%-${W}s#\n" "    S C R I P T S   H U B"
    printf "  #%-${W}s#\n" "    AI & Developer Utilities                    v 1 . 0"
    printf "  #%-${W}s#\n" ""
    printf '%s\n'         "$LINE"
    printf '%s\n'         "${X}"
  fi
}

run_tool() {
  local script="${SCRIPTS_DIR}/$1"
  if [[ ! -x "$script" ]]; then
    printf '%s\n' "${R}  Not found: ${script}${X}"; sleep 1; return
  fi
  bash "$script" "${@:2}"
  printf '\n%s' "${Y}  Press ENTER to return to hub...${X}"; read -r _
}

# ── Menu definitions ─────────────────────────────────────────────────────────
declare -a MENU_LABELS=(
  "  ── AI Context ──────────────────────"
  "  pack-context    Package repo for AI consumption"
  "  git-brief       Git log/diff → AI-ready summary"
  "  token-counter   Count LLM tokens in files/dirs"
  "  prompt-lib      Store, search & copy prompts"
  "  ── Documentation ───────────────────"
  "  adr             Architecture Decision Records"
  "  changelog       Generate CHANGELOG from git"
  "  readme-gen      Scaffold README.md"
  "  ── Conversion ──────────────────────"
  "  md-docx         Markdown ↔ DOCX converter"
  "  mermaid         Mermaid .mmd → PNG renderer"
  "  csv-to-md       CSV → Markdown table"
  "  json-fmt        JSON/YAML formatter & validator"
  "  img-to-text     OCR image → text (Tesseract)"
  "  ── Analysis ────────────────────────"
  "  repo-check      Repository health score"
  "  dep-graph       Import dependency → Mermaid"
  "  env-snapshot    Capture dev environment"
  "  ── Cloud ───────────────────────────"
  "  az-rg-scan      Azure RG inventory & delta scan"
  "  az-sec-audit    Azure public access security audit"
  "  ── ─────────────────────────────────"
  "  Exit"
)

declare -A TOOL_MAP=(
  ["pack-context"]="pack-context/pack-context.sh"
  ["git-brief"]="git-brief/git-brief.sh"
  ["token-counter"]="token-counter/token-count.sh"
  ["prompt-lib"]="prompt-lib/prompts.sh"
  ["adr"]="adr/adr.sh"
  ["changelog"]="changelog/changelog.sh"
  ["readme-gen"]="readme-gen/readme-gen.sh"
  ["md-docx"]="markdow-converter/convert.sh"
  ["mermaid"]="mermaid-converter/convert-mmd-to-png.sh"
  ["csv-to-md"]="csv-to-md/csv-to-md.sh"
  ["json-fmt"]="json-fmt/json-fmt.sh"
  ["img-to-text"]="img-to-text/img-to-text.sh"
  ["repo-check"]="repo-check/repo-check.sh"
  ["dep-graph"]="dep-graph/dep-graph.sh"
  ["env-snapshot"]="env-snapshot/env-snapshot.sh"
  ["az-rg-scan"]="azure-rg-delta-scan/rg-delta-scan.sh"
  ["az-sec-audit"]="azure-security-scan/audit-public-access.sh"
)

show_text_menu() {
  print_rule; printf "  ${B}SELECT A TOOL${X}\n"; print_rule; printf '\n'
  printf "  ${G}── AI CONTEXT ─────────────────────────────────────────────${X}\n"
  printf "   ${G}[1]${X}  pack-context    Package repo for AI consumption\n"
  printf "   ${G}[2]${X}  git-brief       Git log/diff → AI-ready summary\n"
  printf "   ${G}[3]${X}  token-counter   Count LLM tokens in files/dirs\n"
  printf "   ${G}[4]${X}  prompt-lib      Store, search & copy prompts\n"
  printf "  ${G}── DOCUMENTATION ──────────────────────────────────────────${X}\n"
  printf "   ${G}[5]${X}  adr             Architecture Decision Records\n"
  printf "   ${G}[6]${X}  changelog       Generate CHANGELOG from git\n"
  printf "   ${G}[7]${X}  readme-gen      Scaffold README.md\n"
  printf "  ${G}── CONVERSION ─────────────────────────────────────────────${X}\n"
  printf "   ${G}[8]${X}  md-docx         Markdown ↔ DOCX converter\n"
  printf "   ${G}[9]${X}  mermaid         Mermaid .mmd → PNG renderer\n"
  printf "  ${G}[10]${X}  csv-to-md       CSV → Markdown table\n"
  printf "  ${G}[11]${X}  json-fmt        JSON/YAML formatter\n"
  printf "  ${G}[12]${X}  img-to-text     OCR image → text\n"
  printf "  ${G}── ANALYSIS ───────────────────────────────────────────────${X}\n"
  printf "  ${G}[13]${X}  repo-check      Repository health score\n"
  printf "  ${G}[14]${X}  dep-graph       Import dependency → Mermaid\n"
  printf "  ${G}[15]${X}  env-snapshot    Capture dev environment\n"
  printf "  ${G}── CLOUD ──────────────────────────────────────────────────${X}\n"
  printf "  ${G}[16]${X}  az-rg-scan      Azure RG inventory & delta scan\n"
  printf "  ${G}[17]${X}  az-sec-audit    Azure public access security audit\n"
  printf "   ${R}[q]${X}  Exit\n"
  printf '\n'; print_rule; printf '\n'
  printf "${Y}  Choice: ${X}"
}

route_text() {
  local c="$1"
  case "$c" in
    1)  run_tool "pack-context/pack-context.sh" ;;
    2)  run_tool "git-brief/git-brief.sh" ;;
    3)  run_tool "token-counter/token-count.sh" ;;
    4)  run_tool "prompt-lib/prompts.sh" ;;
    5)  run_tool "adr/adr.sh" ;;
    6)  run_tool "changelog/changelog.sh" ;;
    7)  run_tool "readme-gen/readme-gen.sh" ;;
    8)  run_tool "markdow-converter/convert.sh" ;;
    9)  run_tool "mermaid-converter/convert-mmd-to-png.sh" ;;
    10) run_tool "csv-to-md/csv-to-md.sh" ;;
    11) run_tool "json-fmt/json-fmt.sh" ;;
    12) run_tool "img-to-text/img-to-text.sh" ;;
    13) run_tool "repo-check/repo-check.sh" ;;
    14) run_tool "dep-graph/dep-graph.sh" ;;
    15) run_tool "env-snapshot/env-snapshot.sh" ;;
    16) run_tool "azure-rg-delta-scan/rg-delta-scan.sh" ;;
    17) run_tool "azure-security-scan/audit-public-access.sh" ;;
    q|Q|'') printf '\n%s\n\n' "${D}  Goodbye.${X}"; exit 0 ;;
    *) sleep 0.3 ;;
  esac
}

main() {
  local choice
  while true; do
    draw_header
    show_text_menu
    read -r choice
    route_text "$choice"
  done
}

main "$@"
