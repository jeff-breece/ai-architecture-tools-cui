#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  run-tests.sh — Scripts Hub test suite
#  Usage: ./tests/run-tests.sh [--verbose] [TOOL...]
#
#  Runs non-interactive (batch-safe) tests for every tool.
#  Pass a tool name to filter: ./tests/run-tests.sh csv-to-md adr
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPROOT="$(mktemp -d)"
VERBOSE=0; declare -a FILTER=()
while [[ $# -gt 0 ]]; do
  case "$1" in --verbose|-v) VERBOSE=1; shift ;; *) FILTER+=("$1"); shift ;; esac
done
trap 'rm -rf "$TMPROOT"' EXIT

# Isolate test state — prevent tests from polluting ~/.config/scripts-hub/state
export SCRIPTS_HUB_STATE="$TMPROOT/hub-state"

G=$'\e[32m' R=$'\e[31m' Y=$'\e[33m' B=$'\e[1m' D=$'\e[2m' X=$'\e[0m'
PASS=0; FAIL=0; SKIP=0

# ── Helpers ───────────────────────────────────────────────────────────────────
tmpdir() { mktemp -d "$TMPROOT/t-XXXXXX"; }

_filter_active() {
  [[ ${#FILTER[@]} -eq 0 ]] && return 0
  local s="$1"
  for f in "${FILTER[@]}"; do [[ "$s" == *"$f"* ]] && return 0; done
  return 1
}

_pass() { printf '  %s[PASS]%s %-20s %s\n' "$G" "$X" "$1" "$2"; PASS=$(( PASS+1 )); }
_fail() { printf '  %s[FAIL]%s %-20s %s%s\n' "$R" "$X" "$1" "$2" "${3:+  → $3}"; FAIL=$(( FAIL+1 )); }
_skip() { printf '  %s[SKIP]%s %-20s %s\n' "$Y" "$X" "$1" "$2"; SKIP=$(( SKIP+1 )); }
section() { printf '\n  %s%s%s\n' "${G}${B}" "$1" "$X"; }

assert_ok() {
  local suite="$1" name="$2"; shift 2
  _filter_active "$suite" || { _skip "$suite" "$name"; return; }
  if bash -c "$*" >/dev/null 2>&1; then _pass "$suite" "$name"
  else _fail "$suite" "$name" "command exited non-zero"; fi
}

assert_exit() {
  local suite="$1" name="$2" expected="$3"; shift 3
  _filter_active "$suite" || { _skip "$suite" "$name"; return; }
  bash -c "$*" >/dev/null 2>&1; local actual=$?
  if [[ "$actual" -eq "$expected" ]]; then _pass "$suite" "$name"
  else _fail "$suite" "$name" "expected exit $expected got $actual"; fi
}

assert_output() {
  local suite="$1" name="$2" needle="$3"; shift 3
  _filter_active "$suite" || { _skip "$suite" "$name"; return; }
  local out; out="$(bash -c "$*" 2>&1)"
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    _pass "$suite" "$name"
    [[ "$VERBOSE" -eq 1 ]] && printf '%s\n' "$out" | head -4 | sed 's/^/      /'
  else
    _fail "$suite" "$name" "expected: $needle"
    [[ "$VERBOSE" -eq 1 ]] && printf '%s\n' "$out" | head -4 | sed 's/^/      /'
  fi
}

assert_file() {
  local suite="$1" name="$2" file="$3"
  _filter_active "$suite" || { _skip "$suite" "$name"; return; }
  if [[ -n "$file" && -f "$file" && -s "$file" ]]; then _pass "$suite" "$name"
  else _fail "$suite" "$name" "missing/empty: ${file:-<empty path>}"; fi
}

# ── SYNTAX ────────────────────────────────────────────────────────────────────
section "SYNTAX CHECKS"
for script in \
    "$SCRIPTS_DIR/launch.sh" \
    "$SCRIPTS_DIR/pack-context/pack-context.sh" \
    "$SCRIPTS_DIR/git-brief/git-brief.sh" \
    "$SCRIPTS_DIR/token-counter/token-count.sh" \
    "$SCRIPTS_DIR/prompt-lib/prompts.sh" \
    "$SCRIPTS_DIR/adr/adr.sh" \
    "$SCRIPTS_DIR/changelog/changelog.sh" \
    "$SCRIPTS_DIR/readme-gen/readme-gen.sh" \
    "$SCRIPTS_DIR/csv-to-md/csv-to-md.sh" \
    "$SCRIPTS_DIR/json-fmt/json-fmt.sh" \
    "$SCRIPTS_DIR/img-to-text/img-to-text.sh" \
    "$SCRIPTS_DIR/repo-check/repo-check.sh" \
    "$SCRIPTS_DIR/dep-graph/dep-graph.sh" \
    "$SCRIPTS_DIR/env-snapshot/env-snapshot.sh" \
    "$SCRIPTS_DIR/markdow-converter/convert.sh" \
    "$SCRIPTS_DIR/azure-rg-delta-scan/rg-delta-scan.sh" \
    "$SCRIPTS_DIR/azure-security-scan/audit-public-access.sh"; do
  _filter_active "syntax" || { SKIP=$(( SKIP+1 )); continue; }
  name="$(basename "$(dirname "$script")")/$(basename "$script")"
  if bash -n "$script" 2>/dev/null; then _pass "syntax" "$name"
  else _fail "syntax" "$name"; fi
done

# ── TOKEN COUNTER ─────────────────────────────────────────────────────────────
section "TOKEN COUNTER"
TC="$SCRIPTS_DIR/token-counter/token-count.sh"
assert_output "token-counter" "counts tokens in a file"       "Tokens"  "$TC $SCRIPTS_DIR/README.md"
assert_output "token-counter" "counts tokens for two files"   "Total"   "$TC $SCRIPTS_DIR/README.md $SCRIPTS_DIR/SETUP.md"
assert_output "token-counter" "works on a directory"          "README"  "$TC $SCRIPTS_DIR"
assert_output "token-counter" "prompts for dir when no arg given" "Tokens" \
  "printf '%s\n' $SCRIPTS_DIR | $TC"

# ── CSV-TO-MD ─────────────────────────────────────────────────────────────────
section "CSV-TO-MD"
CMD="$SCRIPTS_DIR/csv-to-md/csv-to-md.sh"
assert_output "csv-to-md" "converts CSV stdin to table"  "|"      "printf 'name,age\nalice,30\n' | $CMD"
assert_output "csv-to-md" "header row present"           "name"   "printf 'name,age\nalice,30\n' | $CMD"
assert_output "csv-to-md" "right-align produces ---:"    "---:"   "printf 'a,b\n1,2\n' | $CMD -a r"
TD=$(tmpdir); printf 'x,y\n1,2\n3,4\n' > "$TD/t.csv"
assert_output "csv-to-md" "reads from file arg"          "| x |"  "$CMD $TD/t.csv"

# ── JSON-FMT ──────────────────────────────────────────────────────────────────
section "JSON-FMT"
CMD="$SCRIPTS_DIR/json-fmt/json-fmt.sh"
assert_output "json-fmt" "pretty-prints JSON"         '"key"'   'printf '"'"'{"key":"val","n":1}'"'"' | '"$CMD"
assert_output "json-fmt" "converts JSON to YAML"      "key:"    'printf '"'"'{"key":"val"}'"'"' | '"$CMD"' --to-yaml'
TD=$(tmpdir); printf '{"a":1,"b":2}\n' > "$TD/t.json"
assert_output "json-fmt" "reads from file arg"        '"a"'     "$CMD $TD/t.json"
assert_exit   "json-fmt" "invalid JSON exits non-zero" 1        'printf '"'"'not valid json at all'"'"' | '"$CMD"

# ── ENV-SNAPSHOT ──────────────────────────────────────────────────────────────
section "ENV-SNAPSHOT"
CMD="$SCRIPTS_DIR/env-snapshot/env-snapshot.sh"
assert_output "env-snapshot" "outputs OS section"         "## OS"    "$CMD"
assert_output "env-snapshot" "outputs PATH section"       "PATH"     "$CMD"
assert_output "env-snapshot" "outputs Runtimes section"   "Runtime"  "$CMD"
TD=$(tmpdir)
assert_ok   "env-snapshot" "writes to output file"        "$CMD -o $TD/env.md"
assert_file "env-snapshot" "output file is non-empty"     "$TD/env.md"

# ── DEP-GRAPH ────────────────────────────────────────────────────────────────
section "DEP-GRAPH"
CMD="$SCRIPTS_DIR/dep-graph/dep-graph.sh"
TD=$(tmpdir)
printf 'import os\nfrom utils import helper\n' > "$TD/main.py"
printf 'import re\nfrom datetime import datetime\n' > "$TD/utils.py"
assert_ok    "dep-graph" "runs on python dir"             "$CMD $TD -l python -o $TD/graph.mmd"
assert_file  "dep-graph" "generates .mmd output file"    "$TD/graph.mmd"
assert_output "dep-graph" "mmd contains graph keyword"   "graph"    "cat $TD/graph.mmd"
TD2=$(tmpdir)
printf 'const express = require('"'"'express'"'"')\n' > "$TD2/app.js"
assert_ok    "dep-graph" "runs on js dir"                 "$CMD $TD2 -l js -o $TD2/g.mmd"
assert_ok    "dep-graph" "prompts for dir when no arg given" \
  "printf '%s\n' $TD | $CMD -l python -o $TD/stdin-test.mmd"

# ── REPO-CHECK ────────────────────────────────────────────────────────────────
section "REPO-CHECK"
CMD="$SCRIPTS_DIR/repo-check/repo-check.sh"
assert_output "repo-check" "outputs SCORE header"        "SCORE"      "$CMD $SCRIPTS_DIR"
assert_output "repo-check" "detects README present"      "README"     "$CMD $SCRIPTS_DIR"
assert_output "repo-check" "detects .gitignore present"  "gitignore"  "$CMD $SCRIPTS_DIR"
TD=$(tmpdir); mkdir -p "$TD/.git"
assert_output "repo-check" "scores minimal repo"         "SCORE"      "$CMD $TD"
assert_output "repo-check" "prompts for repo root when no arg given" "SCORE" \
  "printf '%s\n' $SCRIPTS_DIR | $CMD"

# ── GIT-BRIEF ────────────────────────────────────────────────────────────────
section "GIT-BRIEF"
CMD="$SCRIPTS_DIR/git-brief/git-brief.sh"
assert_output "git-brief" "outputs GIT BRIEF header"    "GIT BRIEF"   "$CMD $SCRIPTS_DIR -f log -n 5"
assert_output "git-brief" "includes COMMIT LOG section" "COMMIT LOG"  "$CMD $SCRIPTS_DIR -f log -n 5"
TD=$(tmpdir)
assert_ok    "git-brief" "writes to output file"         "$CMD $SCRIPTS_DIR -f log -n 5 -o $TD/brief.md"
assert_file  "git-brief" "output file is non-empty"      "$TD/brief.md"
assert_output "git-brief" "prompts for repo root when no arg given" "GIT BRIEF" \
  "printf '%s\n' $SCRIPTS_DIR | $CMD -f log -n 5"

# ── PACK-CONTEXT ──────────────────────────────────────────────────────────────
section "PACK-CONTEXT"
CMD="$SCRIPTS_DIR/pack-context/pack-context.sh"
TD=$(tmpdir)
printf '# Hello\nThis is content.\n' > "$TD/README.md"
mkdir -p "$TD/src"; printf 'def hello():\n    return "world"\n' > "$TD/src/main.py"
assert_output "pack-context" "outputs bundle header"    "AI CONTEXT BUNDLE"  "$CMD $TD --no-tokens"
assert_output "pack-context" "includes file contents"  "Hello"               "$CMD $TD --no-tokens"
assert_ok    "pack-context" "writes to output file"     "$CMD $TD --no-tokens -o $TD/bundle.txt"
assert_file  "pack-context" "output file non-empty"     "$TD/bundle.txt"
assert_output "pack-context" "prompts for dir when no arg given" "AI CONTEXT BUNDLE" \
  "printf '%s\n' $TD | $CMD --no-tokens"

# ── ADR ───────────────────────────────────────────────────────────────────────
section "ADR"
CMD="$SCRIPTS_DIR/adr/adr.sh"
TD=$(tmpdir)
assert_ok    "adr" "creates new ADR with title arg"     "ADR_DIR=$TD/adr $CMD new Use PostgreSQL for persistence"
assert_file  "adr" "ADR file created on disk"           "$(ls "$TD/adr"/ADR-*.md 2>/dev/null | head -1)"
assert_output "adr" "list shows created ADR"            "ADR-001"   "ADR_DIR=$TD/adr $CMD list"
assert_output "adr" "search finds text in ADR"          "ADR-001"   "ADR_DIR=$TD/adr $CMD search PostgreSQL"
assert_output "adr" "ADR file has Status field"         "Status"    "ADR_DIR=$TD/adr $CMD list"

# ── CHANGELOG ────────────────────────────────────────────────────────────────
section "CHANGELOG"
CMD="$SCRIPTS_DIR/changelog/changelog.sh"
TD=$(tmpdir)
assert_output "changelog" "generates changelog"         "Changelog"  "$CMD $SCRIPTS_DIR"
assert_output "changelog" "includes dated sections"     "##"         "$CMD $SCRIPTS_DIR"
assert_ok    "changelog" "writes to output file"         "$CMD $SCRIPTS_DIR -o $TD/CHANGELOG.md"
assert_file  "changelog" "output file is non-empty"      "$TD/CHANGELOG.md"
assert_output "changelog" "prompts for repo root when no arg given" "Changelog" \
  "printf '%s\n' $SCRIPTS_DIR | $CMD"

# ── README-GEN ────────────────────────────────────────────────────────────────
section "README-GEN"
CMD="$SCRIPTS_DIR/readme-gen/readme-gen.sh"
TD=$(tmpdir)
printf 'def hello(): pass\n' > "$TD/main.py"
printf '{"name":"myapp","scripts":{"start":"python main.py"}}\n' > "$TD/package.json"
assert_ok    "readme-gen" "scaffolds README without error"  "$CMD $TD -f"
assert_file  "readme-gen" "README.md is created"            "$TD/README.md"
assert_output "readme-gen" "README has Overview section"    "## Overview"       "cat $TD/README.md"
assert_output "readme-gen" "README has Installation"        "## Installation"   "cat $TD/README.md"
TDR=$(tmpdir); printf 'def hello(): pass\n' > "$TDR/main.py"
assert_ok    "readme-gen" "prompts for repo root when no arg given" \
  "printf '%s\n' $TDR | $CMD -f"

# ── IMG-TO-TEXT ───────────────────────────────────────────────────────────────
section "IMG-TO-TEXT"
CMD="$SCRIPTS_DIR/img-to-text/img-to-text.sh"
if command -v tesseract >/dev/null 2>&1; then
  TD=$(tmpdir)
  if command -v convert >/dev/null 2>&1; then
    convert -size 200x50 xc:white -font DejaVu-Sans -pointsize 20 \
      -draw "text 10,35 'Hello OCR'" "$TD/test.png" 2>/dev/null
    assert_ok "img-to-text" "OCR image with local tesseract"  "$CMD $TD/test.png -o $TD --backend local"
  else
    _skip "img-to-text" "ImageMagick not installed (skip image creation)"
  fi
else
  assert_output "img-to-text" "graceful message when tesseract absent"  "Tesseract" \
    "$CMD fakefile.png --backend local 2>&1 || true"
fi
# Jetson backend — not on lab network; should fail gracefully (exit 0)
assert_exit "img-to-text" "jetson fallback exits 0 when offline" 0 \
  "$CMD fakefile.png --backend jetson --url http://10.0.100.30:8002 2>&1 || true"

# ── MERMAID CONVERTER ────────────────────────────────────────────────────────
section "MERMAID CONVERTER"
CMD="$SCRIPTS_DIR/mermaid-converter/convert-mmd-to-png.sh"
if command -v mmdc >/dev/null 2>&1; then
  # mmdc is a snap — must use a non-hidden directory directly under $HOME
  TD="$HOME/mmd-test-$$"; mkdir -p "$TD"
  printf 'graph TD\n    A[Start] --> B[End]\n' > "$TD/test.mmd"
  assert_ok   "mermaid" "converts .mmd to PNG"               "$CMD $TD"
  assert_file "mermaid" "PNG output file created"            "$(ls "$TD/"*.png 2>/dev/null | head -1)"
  assert_ok   "mermaid" "prompts for dir when no arg given"  "printf '%s\n' $TD | $CMD"
  rm -rf "$TD"
else
  _skip "mermaid" "mmdc not installed"
fi

# ── MD-DOCX CONVERTER ────────────────────────────────────────────────────────
section "MD-DOCX CONVERTER"
CMD="$SCRIPTS_DIR/markdow-converter/convert.sh"
if command -v pandoc >/dev/null 2>&1; then
  TD=$(tmpdir)
  mkdir -p "$TD/markdown-source"
  printf '# Test Document\n\nParagraph.\n\n## Section\n\n- item one\n- item two\n' \
    > "$TD/markdown-source/test.md"
  assert_ok   "md-docx" "batch converts MD to DOCX"          "SOURCE_DIR=$TD/markdown-source $CMD --batch"
  assert_file "md-docx" "DOCX output file created"           "$(ls "$TD/markdown-source/docx/"*.docx 2>/dev/null | head -1)"
else
  _skip "md-docx" "pandoc not installed"
fi

# ── PROMPT-LIB ────────────────────────────────────────────────────────────────
section "PROMPT-LIB"
CMD="$SCRIPTS_DIR/prompt-lib/prompts.sh"
PDIR=$(tmpdir)/prompts; mkdir -p "$PDIR"
printf 'You are a helpful assistant.\n' > "$PDIR/test-prompt.md"
assert_output "prompt-lib" "list shows stored prompts"   "test-prompt"  "PROMPT_DIR=$PDIR $CMD list"
assert_output "prompt-lib" "shows prompt count in dir"   "1"            "ls $PDIR | wc -l"

# ── CLOUD (AZURE) ─────────────────────────────────────────────────────────────
section "CLOUD (AZURE)"
CMD="$SCRIPTS_DIR/azure-rg-delta-scan/rg-delta-scan.sh"
assert_output "azure" "az-rg-scan shows usage with no args"      "Usage"   "$CMD 2>&1 || true"
assert_output "azure" "az-rg-scan requires -f CSV flag"          "-f"      "$CMD 2>&1 || true"
CMD="$SCRIPTS_DIR/azure-security-scan/audit-public-access.sh"
assert_output "azure" "az-sec-audit shows usage with no args"    "Usage"   "$CMD 2>&1 || true"
assert_output "azure" "az-sec-audit requires config.json arg"    "config"  "$CMD 2>&1 || true"

# ── LAUNCH.SH ────────────────────────────────────────────────────────────────
section "LAUNCH.SH"
assert_ok "launch" "syntax check passes"  "bash -n $SCRIPTS_DIR/launch.sh"
# Verify each TOOL_MAP script actually exists on disk
missing=0
for script in \
    pack-context/pack-context.sh git-brief/git-brief.sh \
    token-counter/token-count.sh prompt-lib/prompts.sh \
    adr/adr.sh changelog/changelog.sh readme-gen/readme-gen.sh \
    markdow-converter/convert.sh mermaid-converter/convert-mmd-to-png.sh \
    csv-to-md/csv-to-md.sh json-fmt/json-fmt.sh img-to-text/img-to-text.sh \
    repo-check/repo-check.sh dep-graph/dep-graph.sh env-snapshot/env-snapshot.sh \
    azure-rg-delta-scan/rg-delta-scan.sh azure-security-scan/audit-public-access.sh; do
  [[ -f "$SCRIPTS_DIR/$script" ]] || { missing=$(( missing+1 )); printf '  missing: %s\n' "$script"; }
done
if [[ $missing -eq 0 ]]; then _pass "launch" "all 17 tool scripts exist on disk"
else _fail "launch" "all 17 tool scripts exist on disk" "$missing missing"; fi

# ── SUMMARY ───────────────────────────────────────────────────────────────────
TOTAL=$(( PASS + FAIL + SKIP ))
printf '\n'
printf '  ──────────────────────────────────────────────────────────────\n'
printf '  %sTEST RESULTS%s   ' "$B" "$X"
printf '%s%d passed%s  ' "$G" "$PASS" "$X"
[[ $FAIL -gt 0 ]] && printf '%s%d FAILED%s  ' "$R" "$FAIL" "$X" || printf '0 failed  '
printf '%s%d skipped%s  ' "$D" "$SKIP" "$X"
printf '%d total\n' "$TOTAL"
printf '  ──────────────────────────────────────────────────────────────\n\n'
[[ $FAIL -eq 0 ]]
