# Scripts Hub — AI & Developer Utilities

> **Purpose:** A personal terminal toolkit for AI-assisted development in a lab environment.  
> These utilities solve the daily friction of working with LLMs alongside code — packaging repos
> for context windows, counting tokens before you hit limits, managing ADRs, generating changelogs,
> and routing OCR work to a dedicated Jetson Orin edge device.  
> Every tool works standalone or through a single `./launch.sh` hub. No cloud dependencies.
> Runs on Linux (Pop!\_OS / Ubuntu). Built to be shared, forked, and extended.

A collection of 15 terminal utilities for AI-assisted development workflows,
built with a consistent retro terminal aesthetic and [Gum](https://github.com/charmbracelet/gum) TUI.

## Quick Start

```bash
# Launch interactive hub
./launch.sh

# Or run any tool directly
./pack-context/pack-context.sh .
./token-counter/token-count.sh ./src
./git-brief/git-brief.sh -o brief.md
```

## Tools

### AI Context

| Tool | Usage | Description |
|------|-------|-------------|
| **pack-context** | `pack-context [DIR] [-o FILE]` | Bundles a repo into a single AI-ready text file: tree + file contents + token count |
| **git-brief** | `git-brief [DIR] [-f log\|diff\|both] [-o FILE]` | Formats git log/diff as a structured Markdown brief for AI code review |
| **token-counter** | `token-count [FILE\|DIR ...]` | Counts LLM tokens (tiktoken/cl100k_base) per file and total — know your context budget |
| **prompt-lib** | `prompts [list\|add\|edit\|delete]` | Personal prompt library stored in `~/.config/scripts-hub/prompts/`; fuzzy search + clipboard copy |

### Documentation

| Tool | Usage | Description |
|------|-------|-------------|
| **adr** | `adr <new\|list\|search\|status>` | Full ADR lifecycle: create from template, list by status, search, update status |
| **changelog** | `changelog [DIR] [-o FILE] [-s REF]` | Generates `CHANGELOG.md` from git commits (conventional commit grouping) |
| **readme-gen** | `readme-gen [DIR] [-o FILE] [-f]` | Scaffolds `README.md` from repo structure: detects language, scripts, dependencies. `-o` defaults to `DIR/README.md` |

### Conversion

| Tool | Usage | Description |
|------|-------|-------------|
| **md-docx** | `convert.sh [--batch]` | Bidirectional Markdown ↔ DOCX via Pandoc; Gantt-aware, Lua filter for table widths |
| **mermaid** | `convert-mmd-to-png.sh [DIR]` | Renders `.mmd` files to PNG via Mermaid CLI; auto-sizes Gantt diagrams |
| **csv-to-md** | `csv-to-md [FILE] [-a l\|c\|r]` | Converts CSV to a Markdown table; reads from stdin |
| **json-fmt** | `json-fmt [FILE] [--to-yaml]` | Validates and pretty-prints JSON or YAML; converts between formats; reads from stdin |
| **img-to-text** | `img-to-text FILE ... [-o DIR] [--backend local\|jetson] [--url URL]` | OCR images/video to text. **local** backend: Tesseract. **jetson** backend: posts to the [resonance-lab Jetson OCR Service](https://github.com/jeff-breece/resonance-lab/tree/main/jetson/ocr-service) — supports video frame extraction. Configure via `OCR_BACKEND` and `JETSON_OCR_URL` env vars. |

### Analysis

| Tool | Usage | Description |
|------|-------|-------------|
| **repo-check** | `repo-check [DIR]` | Scores repo health (0–100): README, .gitignore, tests, CI, ADRs, CHANGELOG |
| **dep-graph** | `dep-graph [DIR] [-l python\|js]` | Parses imports and generates a Mermaid dependency graph |
| **env-snapshot** | `env-snapshot [-o FILE]` | Captures OS, runtime versions, global packages, PATH — useful before/after AI changes |

### Cloud

| Tool | Usage | Description |
|------|-------|-------------|
| **az-rg-scan** | `rg-delta-scan.sh -f <rg_list.csv> [-o DIR] [-s SUBSCRIPTION]` | Read-only Azure RG inventory across network resources (NIC/PEP/PDNS/VNET/NSG); compares against a previous scan to produce a delta report. Requires `az` CLI + `jq`. |
| **az-sec-audit** | `audit-public-access.sh <config.json> [--output FILE]` | Scans Azure resource groups for public-access exposure; lists associated NICs and private endpoints. Requires `az` CLI + `jq`. |

## Architecture

```
scripts/
├── launch.sh                  # Hub entry point
├── pack-context/
├── git-brief/
├── token-counter/
├── prompt-lib/
├── adr/
├── changelog/
├── readme-gen/
├── markdow-converter/         # MD ↔ DOCX (Pandoc + Lua filter)
├── mermaid-converter/         # .mmd → PNG (Mermaid CLI)
├── csv-to-md/
├── json-fmt/
├── img-to-text/
├── repo-check/
├── dep-graph/
├── env-snapshot/
├── azure-rg-delta-scan/       # Azure RG inventory & delta scan
└── azure-security-scan/       # Azure public access security audit
```

## Design Conventions

- **Gum TUI**: all tools use [Gum](https://github.com/charmbracelet/gum) when available + IS_TTY; graceful text fallback
- **Theme**: `#00cc44` green on dark, `#ffdd00` prompts — inherited via `GUM_*` env vars from the hub
- **Batch-safe**: `HAS_GUM` gated on `IS_TTY`; no UI bleed-through in pipes or cron
- **Standalone**: every tool works independently without going through `launch.sh`
- **Prompt-for-dir**: tools that operate on a repo (`repo-check`, `pack-context`, `git-brief`, `changelog`, `readme-gen`, `dep-graph`, `token-counter`, `mermaid`) prompt the user for the target directory when no positional path argument is supplied. **First run:** blank field — user must type a path (no silent default). **Repeat runs:** last-used path is pre-filled (gum) or shown as "Enter to keep" (text). State is persisted in `~/.config/scripts-hub/state` (override with `SCRIPTS_HUB_STATE`). Tests use an isolated throwaway state file.

## Setup

See [SETUP.md](SETUP.md) for installation instructions.
