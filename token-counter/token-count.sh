#!/usr/bin/env bash
# token-count — Count LLM tokens in files or directories
# Usage: token-count [FILE|DIR ...]  [-m MODEL]
#   -m, --model MODEL  Encoding: cl100k_base (default/GPT-4) | p50k_base (GPT-3)
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
clr()        { [[ "$IS_TTY" -eq 1 ]] && printf '\033[2J\033[H'; }

banner() {
  clr; printf '\n'
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground "#00cc44" --border double --border-foreground "#00cc44" \
      --align center --width 60 --margin "0 2" --padding "1 3" \
      "T O K E N   C O U N T E R" "" "LLM Context Budget Analyzer"
    printf '\n'
  else
    printf '%s\n'   "${G}${B}  ################################################################${X}"
    printf '%s\n'   "${G}${B}  #    T O K E N   C O U N T E R                                #${X}"
    printf '%s\n\n' "${G}${B}  ################################################################${X}"
  fi
}

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

MODEL="cl100k_base"
declare -a TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--model) MODEL="$2"; shift 2 ;;
    -h|--help)  printf 'Usage: %s [FILE|DIR ...] [-m MODEL]\n' "$(basename "$0")"; exit 0 ;;
    -*) printf 'Unknown: %s\n' "$1"; exit 1 ;;
    *)  TARGETS+=("$1"); shift ;;
  esac
done

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  _tgt=""
  prompt_dir _tgt "Files or directory to count" "token-counter.last_dir" || exit 1
  TARGETS=("$_tgt")
else
  state_set "token-counter.last_dir" "${TARGETS[0]}"
fi

python3 - "${MODEL}" "${TARGETS[@]}" << 'PY'
import sys, os
from pathlib import Path

model = sys.argv[1]
targets = sys.argv[2:]

try:
    import tiktoken
    enc = tiktoken.get_encoding(model)
    def count(text): return len(enc.encode(text))
    engine = f"tiktoken/{model}"
except Exception:
    def count(text): return int(len(text.split()) * 1.35)
    engine = "estimate (tiktoken unavailable)"

SKIP_EXT = {'.png','.jpg','.jpeg','.gif','.pdf','.docx','.xlsx','.zip',
            '.tar','.gz','.exe','.bin','.pyc','.so','.o','.class'}
SKIP_DIRS = {'.git','node_modules','__pycache__','.venv','venv','dist','build'}

rows = []
for target in targets:
    p = Path(target)
    if p.is_file():
        try:
            text = p.read_text(errors='replace')
            rows.append((str(p), p.suffix, count(text), p.stat().st_size))
        except Exception:
            pass
    elif p.is_dir():
        for f in sorted(p.rglob('*')):
            if not f.is_file(): continue
            if any(part in SKIP_DIRS for part in f.parts): continue
            if f.suffix.lower() in SKIP_EXT: continue
            try:
                text = f.read_text(errors='replace')
                rows.append((str(f), f.suffix, count(text), f.stat().st_size))
            except Exception:
                pass

total = sum(r[2] for r in rows)

# Print table
print(f"\n  {'File':<55}  {'Tokens':>8}  {'KB':>6}")
print(f"  {'─'*55}  {'─'*8}  {'─'*6}")
for path, ext, toks, size in rows:
    display = path if len(path) <= 55 else '...' + path[-52:]
    print(f"  {display:<55}  {toks:>8,}  {size//1024:>5}k")
print(f"\n  {'─'*72}")
print(f"  Total: {total:,} tokens   ({total//4096} × 4K blocks, {total//128000} × 128K windows)")
print(f"  Engine: {engine}\n")
PY
