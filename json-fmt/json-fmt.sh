#!/usr/bin/env bash
# json-fmt — Validate and pretty-print JSON or YAML; convert between formats
# Usage: json-fmt [FILE] [-o OUTPUT] [--to-yaml] [--to-json]
#   Reads from stdin if no FILE given: cat data.json | json-fmt
set -uo pipefail
INPUT="" OUTPUT="" TO_YAML=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) OUTPUT="$2"; shift 2 ;;
    --to-yaml)   TO_YAML=1; shift ;;
    --to-json)   TO_YAML=0; shift ;;
    -h|--help) printf 'Usage: %s [FILE] [-o OUT] [--to-yaml|--to-json]\n' "$(basename "$0")"; exit 0 ;;
    -*) shift ;; *)  INPUT="$1"; shift ;;
  esac
done
CLEANUP=0
if [[ -z "$INPUT" ]]; then
  TMP_IN="$(mktemp)"; cat > "$TMP_IN"; INPUT="$TMP_IN"; CLEANUP=1
fi
trap '[[ "$CLEANUP" -eq 1 ]] && rm -f "$TMP_IN"' EXIT

python3 - "${INPUT}" "${OUTPUT}" "${TO_YAML}" << 'PY'
import sys, json
inp, outp, to_yaml = sys.argv[1], sys.argv[2], sys.argv[3] == '1'
try:
    import yaml; HAS_YAML = True
except ImportError:
    HAS_YAML = False
text = open(inp).read()
is_yaml = inp.endswith(('.yml', '.yaml'))
data = None
parse_err = None
# Try JSON first (unless file extension says YAML)
if not is_yaml:
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        parse_err = str(e)
# Fall back to YAML for .yml/.yaml files or if explicitly YAML
if data is None and HAS_YAML:
    try:
        parsed = yaml.safe_load(text)
        # yaml.safe_load("plain string") returns a str — that's not structured data
        if isinstance(parsed, (dict, list)):
            data = parsed; is_yaml = True
    except Exception:
        pass
if data is None:
    print(f"Error: cannot parse input as JSON or YAML" + (f": {parse_err}" if parse_err else ""), file=sys.stderr)
    sys.exit(1)
out = (yaml.dump(data, default_flow_style=False, allow_unicode=True)
       if (to_yaml and HAS_YAML)
       else json.dumps(data, indent=2, ensure_ascii=False) + '\n')
if outp:
    open(outp, 'w').write(out)
    print(f"✓ Valid {'YAML' if is_yaml else 'JSON'} → {outp}")
else:
    print(out, end='')
PY
