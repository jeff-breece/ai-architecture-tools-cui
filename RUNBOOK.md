# Runbook — Scripts Hub

> Operations guide for the Scripts Hub AI & Developer Utilities collection.  
> For installation, see [SETUP.md](SETUP.md). For tool reference, see [README.md](README.md).

---

## Quick Reference

| Task | Command |
|---|---|
| Launch interactive hub | `./launch.sh` |
| Run a tool directly | `./pack-context/pack-context.sh .` |
| Run all tests | `./tests/run-tests.sh` |
| Run tests for one tool | `./tests/run-tests.sh adr` |
| Run tests verbosely | `./tests/run-tests.sh --verbose` |
| Update gum | `~/.local/bin/gum --version` → re-run install if outdated |
| Check OCR backend | `cat ~/.config/scripts-hub/config` |

---

## Day-to-Day Workflows

### Bundle a repo for AI review
```bash
cd /path/to/project
/home/jeff/src/scripts/pack-context/pack-context.sh . -o context.txt
# Paste context.txt into your AI chat using the explain-codebase prompt
```

### Get a git brief before a PR
```bash
cd /path/to/project
/home/jeff/src/scripts/git-brief/git-brief.sh . -f both -o brief.md
# Paste brief.md into your AI chat using the pr-description prompt
```

### OCR a screenshot (Jetson Orin on lab switch)
```bash
# Plug into the lab switch (10.0.100.x) first
img-to-text screenshot.png -o ./output
# If Jetson not reachable, falls back to local Tesseract automatically
```

### OCR a video recording
```bash
export OCR_BACKEND=jetson   # or set in ~/.config/scripts-hub/config
img-to-text recording.mp4 -o ./output
# Produces per-frame text + summary in output/recording.txt
```

### Create an ADR
```bash
cd /path/to/project
/home/jeff/src/scripts/adr/adr.sh new "Use Redis for session cache"
# Or launch from hub → option 5
```

### Generate a CHANGELOG before a release
```bash
cd /path/to/project
/home/jeff/src/scripts/changelog/changelog.sh . -o CHANGELOG.md
git add CHANGELOG.md && git commit -m "docs: update CHANGELOG"
```

### Scan Azure resource groups for network inventory
```bash
# 1. Create a CSV of RG names (one per line)
printf 'ResourceGroup\nmy-rg-prod\nmy-rg-dev\n' > rgs-to-scan.csv

# 2. Run the scan (reads az CLI current context)
/home/jeff/src/scripts/azure-rg-delta-scan/rg-delta-scan.sh -f rgs-to-scan.csv -o ./scan-output

# Delta comparison — point -o at a previous scan dir to get a diff
/home/jeff/src/scripts/azure-rg-delta-scan/rg-delta-scan.sh \
  -f rgs-to-scan.csv -o ./scan-output-new

# Requires: az CLI (az login), jq
```

### Audit Azure public-access exposure
```bash
# config.json must contain a "resource_groups" array
cat > config.json <<'EOF'
{
  "resource_groups": ["my-rg-prod", "my-rg-dev"]
}
EOF

/home/jeff/src/scripts/azure-security-scan/audit-public-access.sh config.json
/home/jeff/src/scripts/azure-security-scan/audit-public-access.sh config.json --output report.txt

# Requires: az CLI (az login), jq
```

---

## Configuration

### User config file
All user-specific defaults live in `~/.config/scripts-hub/config`.

```bash
cat ~/.config/scripts-hub/config
```

Current settings:
| Variable | Default | Description |
|---|---|---|
| `OCR_BACKEND` | `jetson` | OCR engine: `local` or `jetson` |
| `JETSON_OCR_URL` | `http://10.0.100.30:8002` | Jetson Orin on lab switch |
| `OCR_LANG` | `eng` | Tesseract language code |

**Override priority**: CLI flag > env var > `~/.config/scripts-hub/config` > built-in default.

### Prompt library
Prompts are stored as Markdown files in `~/.config/scripts-hub/prompts/`.

```bash
ls ~/.config/scripts-hub/prompts/     # list all prompts
$EDITOR ~/.config/scripts-hub/prompts/code-review.md   # edit directly
```

---

## Adding a New Tool

1. **Create the directory and script:**
   ```bash
   mkdir -p /home/jeff/src/scripts/my-tool
   cp /home/jeff/src/scripts/env-snapshot/env-snapshot.sh /home/jeff/src/scripts/my-tool/my-tool.sh
   # Edit my-tool.sh — keep the IS_TTY/HAS_GUM pattern, banner(), print_ok/fail/warn
   chmod +x /home/jeff/src/scripts/my-tool/my-tool.sh
   ```

2. **Add it to the hub launcher** (`launch.sh`):
   - Add a `printf` line to `show_text_menu()` with the next available number
   - Add a `route_text` case for that number pointing to `my-tool/my-tool.sh`

3. **Add tests** (`tests/run-tests.sh`):
   - Add a `section "MY-TOOL"` block with at least:
     - Syntax check (handled by the SYNTAX CHECKS loop — just add the path there)
     - `assert_output` for expected output
     - `assert_ok` for file output if applicable

4. **Update docs** (`README.md` tool table, `SETUP.md` if new dependencies).

5. **Commit:**
   ```bash
   cd /home/jeff/src/scripts
   git add my-tool/ launch.sh tests/run-tests.sh README.md
   git commit -m "feat(my-tool): add <description>"
   ```

### Prompt-for-dir behavior

Tools that operate on a repository (`repo-check`, `pack-context`, `git-brief`, `changelog`,
`readme-gen`, `dep-graph`, `token-counter`, `mermaid`) accept an optional positional
directory argument. When omitted, the tool shows an interactive directory prompt.

**First run (no saved state):** the field is blank — you must type the path. There is
no silent default, so tools never accidentally target the wrong directory.

**Repeat runs:** the last-used path is pre-filled (gum mode) or shown with
"Enter to keep" (plain text mode) — press Enter to reuse it or type a new path.

```bash
# Explicit path (no prompt):
repo-check /path/to/my-project

# No arg — first run (blank prompt, must type):
repo-check
#   Repository to check: _

# No arg — repeat run (pre-filled with last-used path):
repo-check
#   Repository to check: /path/to/my-project
```

**State file:** `~/.config/scripts-hub/state` — override with `SCRIPTS_HUB_STATE` env var.  
**Tests** use `SCRIPTS_HUB_STATE="$TMPROOT/hub-state"` (isolated throwaway file) so test
runs never pollute the production last-used paths.

```bash
# Clear a stale entry manually if needed:
sed -i '/^repo-check\.last_dir=/d' ~/.config/scripts-hub/state
```

---

## Troubleshooting

### Tool targets the scripts directory instead of my project

```
Symptom: repo-check / token-counter / etc. scores or counts the scripts hub dir
Cause:   ~/.config/scripts-hub/state has a stale last_dir entry from a previous run
         against the hub installation, or tests were run without state isolation.
Fix:
  # Clear all stale entries in one go:
  python3 -c "
  from pathlib import Path
  f = Path.home() / '.config/scripts-hub/state'
  lines = [l for l in f.read_text().splitlines() if '=' in l and Path(l.split('=',1)[1]).is_dir()]
  f.write_text('\n'.join(lines) + '\n' if lines else '')
  "

  # Or delete the whole state file to start fresh (tools fall back to \$HOME):
  rm ~/.config/scripts-hub/state
```

### Hub menu does not appear
```
Symptom: Banner shows, then "Goodbye." immediately
Cause:   gum choose exits non-zero (TTY/stdout issue)
Fix:     launch.sh now uses plain ANSI text menu — should not recur.
         If banner is also missing, check: command -v gum && gum --version
```

### Gum not found
```bash
# Reinstall gum
GUM_VERSION="0.17.0"
curl -sL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_x86_64.tar.gz" \
  | tar -xz -C ~/.local/bin gum
chmod +x ~/.local/bin/gum
```

### Jetson OCR not reachable
```
Symptom: [ WARN ] Jetson OCR not reachable at http://10.0.100.30:8002
Cause:   Laptop not connected to lab switch (10.0.100.x network)
Fix:     Connect to lab switch. Tool falls back to local Tesseract automatically.

To check service on Jetson:
  ssh jeff@10.0.100.30
  systemctl status ocr-service
  # Or: cd resonance-lab/jetson/ocr-service && uvicorn app:app --host 0.0.0.0 --port 8000
```

### Pandoc errors on MD→DOCX
```
Symptom: [ FAIL ] DOCX conversion
Cause:   Pandoc version mismatch (using 2.9.2.1)
Fix:     The fix-table-widths.lua filter supports both old and new AST.
         If new error: check pandoc --version, update lua filter if needed.
         Workaround: SOURCE_DIR=. convert.sh --batch
```

### Token counter falls back to word-count estimate
```
Symptom: "tiktoken not available — using word estimate"
Cause:   tiktoken Python package not installed
Fix:     pip install tiktoken
```

### dep-graph shows no edges
```
Symptom: Mermaid .mmd contains only node declarations, no arrows
Cause:   Files use relative imports or non-standard import syntax
Check:   cat the generated .mmd file — nodes present but no edges
Fix:     Use -l flag to set language explicitly: dep-graph . -l python
```

### Tests fail unexpectedly
```bash
# Run with verbose output to see actual vs expected
./tests/run-tests.sh --verbose adr

# Run a specific section only
./tests/run-tests.sh json-fmt

# Check if required tools are installed
pandoc --version
python3 -c "import tiktoken; print('ok')"
~/.local/bin/gum --version
```

---

## Maintenance

### Update Gum TUI
```bash
GUM_VERSION="$(curl -s https://api.github.com/repos/charmbracelet/gum/releases/latest | grep tag_name | cut -d'"' -f4 | tr -d v)"
curl -sL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_x86_64.tar.gz" \
  | tar -xz -C ~/.local/bin gum
gum --version
```

### Rotate starter prompts
```bash
ls ~/.config/scripts-hub/prompts/
$EDITOR ~/.config/scripts-hub/prompts/code-review.md
# Add new prompt:
/home/jeff/src/scripts/prompt-lib/prompts.sh add my-new-prompt
```

### Check repo health score
```bash
# With a path argument:
/home/jeff/src/scripts/repo-check/repo-check.sh /home/jeff/src/scripts

# Without a path — prompts for the repo root interactively:
/home/jeff/src/scripts/repo-check/repo-check.sh
# Items that will improve the score:
#   - Add a LICENSE file      (+5)
#   - Add git tags            (+5)
#   - Add a tests/ dir        (+5) ← already done
#   - Add CI workflow         (+10)
```

### Cut a release
```bash
cd /home/jeff/src/scripts
./changelog/changelog.sh . -o CHANGELOG.md   # regenerate
git add CHANGELOG.md
git commit -m "chore: update CHANGELOG for v<version>"
git tag -a v<version> -m "release v<version>"
git push && git push --tags
```

---

## Environment

| Component | Version / Location |
|---|---|
| Gum | `~/.local/bin/gum` v0.17.0 |
| Pandoc | `/usr/bin/pandoc` 2.9.2.1 |
| Python | `/usr/bin/python3` 3.10.12 |
| tiktoken | `pip show tiktoken` 0.12.0 |
| mmdc | `/snap/bin/mmdc` 11.12.0 |
| Tesseract | not installed locally (use Jetson backend) |
| Jetson Orin | `http://10.0.100.30:8002` (on lab switch) |
| Config | `~/.config/scripts-hub/config` |
| Prompts | `~/.config/scripts-hub/prompts/` |

---

*Last updated: 2026-07-11*
