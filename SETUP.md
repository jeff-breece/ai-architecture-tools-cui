# Setup Guide — Scripts Hub

## System Requirements

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| Bash | 4.0+ | macOS ships Bash 3 — install via Homebrew |
| Python | 3.8+ | For preprocessing, token counting, format conversion |
| Pandoc | 2.9+ | Required for MD ↔ DOCX conversion |
| Node.js | 14+ | Required for Mermaid CLI (`mmdc`) |
| gum | 0.14+ | Optional but recommended — enables full TUI |

---

## 1. Install Gum (TUI Framework)

Gum enables the interactive menus, spinners, and styled output across all tools.

**Linux (x86_64):**
```bash
curl -sL https://github.com/charmbracelet/gum/releases/download/v0.17.0/gum_0.17.0_Linux_x86_64.tar.gz \
  | tar -xz --strip-components=1 -C ~/.local/bin gum_0.17.0_Linux_x86_64/gum
chmod +x ~/.local/bin/gum
```

**macOS:**
```bash
brew install charmbracelet/tap/gum
```

**Verify:** `gum --version`

---

## 2. Install Pandoc (MD ↔ DOCX)

**Ubuntu/Debian:**
```bash
sudo apt install pandoc
```

**macOS:**
```bash
brew install pandoc
```

**Verify:** `pandoc --version`

---

## 3. Install Mermaid CLI (.mmd → PNG)

Requires Node.js. Uses Chromium headless — first run downloads it automatically.

```bash
npm install -g @mermaid-js/mermaid-cli
```

**Verify:** `mmdc --version`

---

## 4. Install Python Dependencies

```bash
pip3 install tiktoken pyyaml
```

| Package | Used by |
|---------|---------|
| `tiktoken` | token-counter, pack-context |
| `pyyaml` | json-fmt (YAML support) |

**Verify:** `python3 -c "import tiktoken, yaml; print('OK')"`

---

## 5. Install Tesseract (img-to-text — optional)

```bash
# Ubuntu/Debian
sudo apt install tesseract-ocr

# macOS
brew install tesseract

# Additional language packs
sudo apt install tesseract-ocr-eng
```

**Verify:** `tesseract --version`

---

## 6. Clipboard Support (prompt-lib)

**Linux:** Install `xclip` or `xsel`:
```bash
sudo apt install xclip
```

**macOS:** `pbcopy` is built-in.

---

## 7. Make Scripts Executable

```bash
cd /home/jeff/src/scripts
chmod +x launch.sh
find . -name "*.sh" -exec chmod +x {} \;
```

---

## 8. Add Hub to PATH (Optional)

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="/home/jeff/src/scripts:$PATH"
alias hub="launch.sh"
```

---

## Environment Variables

All tools respect these optional overrides:

| Variable | Default | Tool |
|----------|---------|------|
| `SOURCE_DIR` | `./markdown-source` | md-docx |
| `OUTPUT_DOCX` | `SOURCE_DIR/docx` | md-docx |
| `OUTPUT_MD` | `SOURCE_DIR/converted-md` | md-docx |
| `LUA_FILTER` | `./fix-table-widths.lua` | md-docx |
| `REFERENCE_DOC` | *(none)* | md-docx |
| `ADR_DIR` | `./docs/adr` | adr |
| `PROMPT_DIR` | `~/.config/scripts-hub/prompts` | prompt-lib |

---

## Verify Full Stack

```bash
./launch.sh            # Hub launches (gum menus if installed)
./repo-check/repo-check.sh .   # Should score the hub itself
./token-counter/token-count.sh .  # Token count for all scripts
```
