#!/usr/bin/env bash
# dep-graph — Generate import dependency graph as Mermaid diagram
# Usage: dep-graph [DIR] [-o FILE] [-l python|js]
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
      "D E P   G R A P H" "" "Import Graph → Mermaid Diagram"
    printf '\n'
  fi
}
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

TARGET=""; OUTPUT=""; LANG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) OUTPUT="$2"; shift 2 ;;
    -l|--lang)   LANG="$2"; shift 2 ;;
    -*) shift ;; *)  TARGET="$1"; shift ;;
  esac
done
if [[ -z "$TARGET" ]]; then
  prompt_dir TARGET "Repository or source directory" "dep-graph.last_dir" || exit 1
else
  TARGET="$(cd "$TARGET" && pwd)"
  state_set "dep-graph.last_dir" "$TARGET"
fi
LANG="${LANG}" OUTPUT="${OUTPUT:-${TARGET}/dependency-graph.mmd}" \
python3 - "${TARGET}" << 'PY'
import sys, re, os
from pathlib import Path
target = Path(sys.argv[1])
lang = os.environ.get("LANG_OPT","").lower()
out_file = os.environ.get("OUTPUT","dependency-graph.mmd")
SKIP = {".git","node_modules","__pycache__",".venv","venv","dist","build"}
if not lang:
    py = len(list(target.rglob("*.py")))
    js = len(list(target.rglob("*.js"))) + len(list(target.rglob("*.ts")))
    lang = "python" if py >= js else "js"
def short(p):
    rel = str(p.relative_to(target))
    return re.sub(r"\.py$|\.js$|\.ts$","",rel).replace("/",".").replace("-","_")
edges = set()
if lang == "python":
    for f in target.rglob("*.py"):
        if any(p in SKIP for p in f.parts): continue
        try: text = f.read_text(errors="replace")
        except: continue
        for m in re.finditer(r"^(?:from\s+(\S+)|import\s+(\S+))", text, re.MULTILINE):
            imp = (m.group(1) or m.group(2)).split(".")[0]
            ip = target / (imp + ".py")
            if ip.exists(): edges.add((short(f), short(ip)))
else:
    for f in list(target.rglob("*.js")) + list(target.rglob("*.ts")):
        if any(p in SKIP for p in f.parts): continue
        try: text = f.read_text(errors="replace")
        except: continue
        for m in re.finditer(r"""(?:import|require)\s*[\('"]([^'"\)\s]+)['"]""", text):
            imp = m.group(1)
            if imp.startswith("."):
                ip = (f.parent / imp).resolve()
                for ext in [".js",".ts",""]:
                    candidate = ip.with_suffix(ext) if ext else ip
                    if candidate.exists(): edges.add((short(f), short(candidate))); break
lines = ["graph TD"]
if not edges:
    lines.append("    A[No internal imports detected]")
else:
    for src,dst in sorted(edges):
        sid = re.sub(r"[^a-zA-Z0-9_]","_",src)
        did = re.sub(r"[^a-zA-Z0-9_]","_",dst)
        lines.append(f"    {sid}[\"{src}\"] --> {did}[\"{dst}\"]")
Path(out_file).write_text("\n".join(lines)+"\n")
print(f"Written {out_file}")
PY
print_ok "Mermaid → ${B}${OUTPUT:-dependency-graph.mmd}${X}"
printf '\n  ${G}Render with:${X} mermaid-converter/convert-mmd-to-png.sh <dir>\n\n'
