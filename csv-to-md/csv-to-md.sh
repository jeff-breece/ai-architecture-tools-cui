#!/usr/bin/env bash
# csv-to-md — Convert CSV to Markdown table
# Usage: csv-to-md [FILE] [-o OUTPUT] [-a l|c|r] [-d DELIM]
#   Reads from stdin if no FILE given: cat data.csv | csv-to-md
set -uo pipefail
OUTPUT="" ALIGN="l" DELIM="," INPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)    OUTPUT="$2"; shift 2 ;;
    -a|--align)     ALIGN="$2"; shift 2 ;;
    -d|--delimiter) DELIM="$2"; shift 2 ;;
    -h|--help) printf 'Usage: %s [FILE] [-o OUT] [-a l|c|r] [-d DELIM]\n' "$(basename "$0")"; exit 0 ;;
    -*) shift ;; *)  INPUT="$1"; shift ;;
  esac
done
# Capture stdin to temp if no file given
CLEANUP=0
if [[ -z "$INPUT" ]]; then
  TMP_IN="$(mktemp)"; cat > "$TMP_IN"; INPUT="$TMP_IN"; CLEANUP=1
fi
trap '[[ "$CLEANUP" -eq 1 ]] && rm -f "$TMP_IN"' EXIT

python3 - "${INPUT}" "${OUTPUT}" "${ALIGN}" "${DELIM}" << 'PY'
import sys, csv, io
inp, outp, align, delim = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
sep = {'l': ':---', 'c': ':---:', 'r': '---:'}.get(align, ':---')
text = open(inp).read()
rows = list(csv.reader(io.StringIO(text), delimiter=delim))
if not rows: sys.exit("No data")
cols = max(len(r) for r in rows)
rows = [r + [''] * (cols - len(r)) for r in rows]
w = [max(len(r[i]) for r in rows) for i in range(cols)]
def fmt(r): return '| ' + ' | '.join(c.ljust(w[i]) for i, c in enumerate(r)) + ' |'
out = '\n'.join([fmt(rows[0]),
                 '| ' + ' | '.join(sep.ljust(w[i]) for i in range(cols)) + ' |'] +
                [fmt(r) for r in rows[1:]]) + '\n'
open(outp, 'w').write(out) if outp else print(out, end='')
PY
