#!/usr/bin/env bash
# img-to-text — OCR image/video files to text
#
# Backends (set via OCR_BACKEND env var or --backend flag):
#   local   Use local Tesseract installation (default)
#   jetson  POST to Jetson OCR Service (resonance-lab/jetson/ocr-service)
#           Falls back to local Tesseract automatically if the service is
#           unreachable (e.g. laptop not on the lab network).
#
# Usage:
#   img-to-text [FILE ...] [-o OUTPUT_DIR] [--backend local|jetson] [--url URL]
#
# Config file (lowest priority, overridden by env vars and flags):
#   ~/.config/scripts-hub/config
#
# Env vars:
#   OCR_BACKEND      local | jetson  (default: local)
#   JETSON_OCR_URL   http://host:8002
#   OCR_LANG         Tesseract language code, e.g. eng (default: eng)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

IS_TTY=0; [[ -t 1 ]] && IS_TTY=1
HAS_GUM=0; [[ "$IS_TTY" -eq 1 ]] && command -v gum >/dev/null 2>&1 && HAS_GUM=1
if [[ "$IS_TTY" -eq 1 ]]; then
  G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' C=$'\e[36m' B=$'\e[1m' D=$'\e[2m' X=$'\e[0m'
else
  G='' Y='' R='' C='' B='' D='' X=''
fi

print_ok()   { printf '%s\n' "${G}  [  OK  ]${X} ${1}"; }
print_fail() { printf '%s\n' "${R}  [ FAIL ] ${1}${X}"; }
print_info() { printf '%s\n' "${C}  [ INFO ]${X} ${1}"; }
print_warn() { printf '%s\n' "${Y}  [ WARN ]${X} ${1}"; }
print_rule() { printf '%s\n' "${G}  ──────────────────────────────────────────────────────────────${X}"; }
clr()        { [[ "$IS_TTY" -eq 1 ]] && printf '\033[2J\033[H'; }

# ── Load user config (lowest priority) ───────────────────────────────────────
# Config sets OCR_BACKEND, JETSON_OCR_URL, OCR_LANG as defaults.
# Env vars already exported take precedence; CLI flags override everything.
_CFG="${HOME}/.config/scripts-hub/config"
if [[ -f "$_CFG" ]]; then
  # Source only assignment lines — skip comments and blank lines safely
  while IFS= read -r _line; do
    [[ "$_line" =~ ^[[:space:]]*# ]] && continue
    [[ "$_line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$_line" =~ ^[A-Z_]+=  ]] || continue
    _key="${_line%%=*}"
    _val="${_line#*=}"
    # Only set if not already in environment (env var takes precedence)
    [[ -z "${!_key+x}" ]] && export "${_key}=${_val}"
  done < "$_CFG"
fi

# ── Defaults (applied after config file) ─────────────────────────────────────
OCR_BACKEND="${OCR_BACKEND:-local}"
JETSON_OCR_URL="${JETSON_OCR_URL:-}"
OCR_LANG="${OCR_LANG:-eng}"
OUTPUT_DIR="."
declare -a FILES=()

# ── Argument parsing (highest priority — overrides env + config) ──────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)   OUTPUT_DIR="$2"; shift 2 ;;
    --backend)     OCR_BACKEND="$2"; shift 2 ;;
    --url)         JETSON_OCR_URL="$2"; shift 2 ;;
    --lang)        OCR_LANG="$2"; shift 2 ;;
    -h|--help)
      printf 'Usage: %s [FILE ...] [-o DIR] [--backend local|jetson] [--url URL] [--lang LANG]\n' \
        "$(basename "$0")"
      printf '\nConfig: ~/.config/scripts-hub/config\n'
      printf 'Env:    OCR_BACKEND, JETSON_OCR_URL, OCR_LANG\n'
      exit 0 ;;
    -*) shift ;;
    *)  FILES+=("$1"); shift ;;
  esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
  clr; printf '\n'
  local subtitle="OCR Screenshot → Text  •  backend: ${OCR_BACKEND}"
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 3" \
      "I M G   T O   T E X T" "" "$subtitle"
    printf '\n'
  else
    printf '%s\n'   "${G}${B}  ################################################################${X}"
    printf '%s\n'   "${G}${B}  #    I M G   T O   T E X T                                    #${X}"
    printf "${G}${B}  #    %-58s#${X}\n" "$subtitle"
    printf '%s\n\n' "${G}${B}  ################################################################${X}"
  fi
}
banner

# ── File prompt (when launched interactively with no args) ───────────────────
if [[ "${#FILES[@]}" -eq 0 ]]; then
  if [[ "$IS_TTY" -eq 0 ]]; then
    printf '%s\n\n' "${Y}  Usage: img-to-text FILE [...] [-o outdir] [--backend local|jetson]${X}"
    exit 1
  fi

  print_rule
  printf '\n'
  _prompt_files() {
    local _label="$1" _input=""
    if [[ "$HAS_GUM" -eq 1 ]]; then
      printf '  %s%s%s\n' "$Y" "$_label" "$X"
      _input="$(gum input \
        --placeholder "/home/jeff/Pictures/Screenshots/Screenshot from 2026-07-11 20-48-36.png" \
        --prompt "  › " \
        --prompt.foreground "#ffdd00" \
        --width 70 2>/dev/null)" || true
    else
      printf '  %s%s%s\n  › ' "$Y" "$_label" "$X"
      read -r _input
    fi
    printf '%s' "$_input"
  }

  _raw="$(_prompt_files "File path (space-separated for multiple):")"
  if [[ -z "$_raw" ]]; then
    printf '%s\n\n' "${R}  No file entered — cancelled.${X}"
    exit 1
  fi
  read -ra FILES <<< "$_raw"

  # Also prompt for output dir if not set via flag
  if [[ "$OUTPUT_DIR" == "." ]]; then
    if [[ "$HAS_GUM" -eq 1 ]]; then
      _outdir="$(gum input \
        --placeholder "$(dirname "${FILES[0]}")" \
        --prompt "  Output dir (Enter for same as file): " \
        --prompt.foreground "#ffdd00" \
        --width 70 2>/dev/null)" || true
      [[ -n "$_outdir" ]] && OUTPUT_DIR="$_outdir"
    else
      printf '  Output dir [Enter for file location]: '
      read -r _outdir
      [[ -n "$_outdir" ]] && OUTPUT_DIR="$_outdir"
    fi
    # Default to directory of first file
    [[ "$OUTPUT_DIR" == "." ]] && OUTPUT_DIR="$(dirname "${FILES[0]}")"
  fi
  printf '\n'
fi

# ── Video extensions (Jetson service only) ────────────────────────────────────
is_video() {
  local ext="${1##*.}"
  case "${ext,,}" in mp4|avi|mov|mkv|ts|m4v) return 0 ;; *) return 1 ;; esac
}

# ═════════════════════════════════════════════════════════════════════════════
#  BACKEND: jetson
# ═════════════════════════════════════════════════════════════════════════════
run_jetson() {
  if [[ -z "$JETSON_OCR_URL" ]]; then
    print_warn "JETSON_OCR_URL is not set — falling back to local Tesseract"
    run_local; return
  fi

  # Strip trailing slash
  JETSON_OCR_URL="${JETSON_OCR_URL%/}"

  print_rule
  print_info "Trying Jetson OCR Service: ${JETSON_OCR_URL}"

  # ── Try to reach the service (graceful fallback if offline) ────────────────
  local health
  health="$(curl -sf --max-time 3 "${JETSON_OCR_URL}/health" 2>/dev/null)" || {
    print_warn "Jetson OCR not reachable at ${JETSON_OCR_URL}"
    print_info "This is expected when the laptop is not on the lab switch (10.0.100.x)."
    printf '\n'
    if command -v tesseract >/dev/null 2>&1; then
      print_info "Falling back to local Tesseract automatically."
      print_rule; printf '\n'
      run_local
    else
      print_warn "No OCR backend available."
      printf '\n  Options:\n'
      printf '    1. Connect to the lab switch to reach the Jetson at %s\n' "$JETSON_OCR_URL"
      printf '    2. Install local Tesseract: sudo apt install tesseract-ocr\n\n'
    fi
    return
  }

  local tess_ver; tess_ver="$(printf '%s' "$health" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tesseract_version','?'))" 2>/dev/null || echo "?")"
  local trt; trt="$(printf '%s' "$health" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if d.get('tensorrt_available') else 'no')" 2>/dev/null || echo "?")"
  print_ok "Service healthy — Tesseract ${tess_ver}  TensorRT: ${trt}"
  print_rule; printf '\n'

  mkdir -p "$OUTPUT_DIR"
  local ok=0 fail=0

  for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || { print_fail "Not found: ${f}"; fail=$(( fail+1 )); continue; }
    local base out endpoint
    base="$(basename "${f%.*}")"
    out="${OUTPUT_DIR}/${base}.txt"

    if is_video "$f"; then
      endpoint="/v1/analyze-video"
      print_info "Video → frame OCR: $(basename "$f")"
    else
      endpoint="/v1/ocr"
    fi

    local response
    if [[ "$HAS_GUM" -eq 1 ]]; then
      response="$(gum spin --title "  Sending to Jetson: $(basename "$f")" -- \
        curl -sf -X POST "${JETSON_OCR_URL}${endpoint}" \
          -F "file=@${f}" 2>/dev/null)"
    else
      printf '  Sending: %s ...\n' "$(basename "$f")"
      response="$(curl -sf -X POST "${JETSON_OCR_URL}${endpoint}" \
        -F "file=@${f}" 2>/dev/null)"
    fi

    if [[ $? -ne 0 || -z "$response" ]]; then
      print_fail "$(basename "$f") — no response from service"
      fail=$(( fail+1 )); continue
    fi

    # Extract text (image) or per-frame texts + summary (video)
    if is_video "$f"; then
      python3 - "$response" "$out" <<'PYEOF'
import sys, json
resp, out_path = sys.argv[1], sys.argv[2]
d = json.loads(resp)
with open(out_path, 'w') as fh:
    fh.write(f"# OCR Summary\n{d.get('summary','')}\n\n")
    for fr in d.get('frames', []):
        ts = fr.get('timestamp_sec', '')
        txt = fr.get('text', '').strip()
        if txt:
            fh.write(f"## Frame {fr['frame']} ({ts}s)\n{txt}\n\n")
PYEOF
    else
      python3 - "$response" "$out" <<'PYEOF'
import sys, json
resp, out_path = sys.argv[1], sys.argv[2]
d = json.loads(resp)
text = d.get('text', '')
summary = d.get('summary', '')
with open(out_path, 'w') as fh:
    fh.write(text)
    if summary:
        fh.write(f"\n\n---\n{summary}\n")
PYEOF
    fi

    print_ok "$(basename "$f") → ${out}"
    ok=$(( ok+1 ))
  done

  _summary "$ok" "$fail"
}

# ═════════════════════════════════════════════════════════════════════════════
#  BACKEND: local (Tesseract)
# ═════════════════════════════════════════════════════════════════════════════
run_local() {
  if ! command -v tesseract >/dev/null 2>&1; then
    printf '%s\n' "${R}  Tesseract not installed${X}"
    printf '\n  ${Y}Install:${X}\n'
    printf '    sudo apt install tesseract-ocr\n'
    printf '    brew install tesseract\n\n'
    printf '  Or use the Jetson OCR backend:\n'
    printf '    export OCR_BACKEND=jetson\n'
    printf '    export JETSON_OCR_URL=http://<jetson-ip>:8002\n\n'
    exit 1
  fi

  local tess_ver; tess_ver="$(tesseract --version 2>&1 | head -1)"
  print_rule
  print_info "Local Tesseract: ${tess_ver}  lang: ${OCR_LANG}"
  print_rule; printf '\n'

  mkdir -p "$OUTPUT_DIR"
  local ok=0 fail=0

  for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || { print_fail "Not found: ${f}"; fail=$(( fail+1 )); continue; }

    if is_video "$f"; then
      print_warn "Video files require the jetson backend (--backend jetson)"
      fail=$(( fail+1 )); continue
    fi

    local base out
    base="$(basename "${f%.*}")"
    out="${OUTPUT_DIR}/${base}"

    if [[ "$HAS_GUM" -eq 1 ]]; then
      gum spin --title "  OCR: $(basename "$f")" -- \
        tesseract "$f" "$out" -l "$OCR_LANG" 2>/dev/null \
        && { print_ok "$(basename "$f") → ${out}.txt"; ok=$(( ok+1 )); } \
        || { print_fail "$(basename "$f")"; fail=$(( fail+1 )); }
    else
      tesseract "$f" "$out" -l "$OCR_LANG" 2>/dev/null \
        && { print_ok "$(basename "$f") → ${out}.txt"; ok=$(( ok+1 )); } \
        || { print_fail "$(basename "$f")"; fail=$(( fail+1 )); }
    fi
  done

  _summary "$ok" "$fail"
}

# ── Summary footer ─────────────────────────────────────────────────────────
_summary() {
  local ok="$1" fail="$2"
  printf '\n'; print_rule
  printf "  ${B}DONE${X}  ${G}%d OK${X}" "$ok"
  [[ "$fail" -gt 0 ]] && printf "  ${R}  %d failed${X}" "$fail"
  printf '\n'; print_rule; printf '\n'
}

# ── Dispatch ───────────────────────────────────────────────────────────────
case "$OCR_BACKEND" in
  jetson) run_jetson ;;
  local)  run_local  ;;
  *) printf '%s\n' "${R}  Unknown backend: ${OCR_BACKEND}  (use: local | jetson)${X}"; exit 1 ;;
esac
