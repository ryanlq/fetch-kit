# fetch-kit

Unified installer for ryanlq CLI tools. One command to install, update, check versions, and deploy skills.

## Tools

| Tool | Command | Language | Description |
|------|---------|----------|-------------|
| [ai-experience-learner](https://github.com/ryanlq/ai-experience-learner) | `xp` | Python | Distill past interactions into reusable lessons, recall to improve inference |
| [akshare-cli](https://github.com/ryanlq/akshare-cli) | `ak` | Python | 1092+ Chinese financial data functions via CLI |
| [get-news](https://github.com/ryanlq/get-news) | `get-news` | Python | Multi-step web scraper with rule-driven extraction |
| [olkcli](https://github.com/rlrghb/olkcli) | `olk` | Go | Microsoft Outlook CLI via Graph API (mail, calendar, contacts, todo, OneDrive) |

## Quick Start

```bash
# One command to install fetch-kit and all tools
curl -sL https://raw.githubusercontent.com/ryanlq/fetch-kit/main/fetch-kit.sh | bash
```

This installs `fetch-kit` to `~/.local/bin/` and all managed tools. After that, use `fetch-kit` as a regular command.

## Usage

```bash
fetch-kit install              # Install all tools
fetch-kit install xp ak        # Install specific tools
fetch-kit update               # Update all tools to latest
fetch-kit update olk           # Update a specific tool
fetch-kit upgrade              # Update fetch-kit itself
fetch-kit status               # Show installed vs latest versions
fetch-kit uninstall            # Uninstall all tools
```

### Install Skills

Deploy skills to Claude Code or Codex so AI assistants know how to use these tools.

```bash
fetch-kit skills -t claude     # All skills for Claude Code
fetch-kit skills -t codex      # All skills for OpenAI Codex
fetch-kit skills ak -t claude  # Only akshare-cli skill
```

Skills are downloaded from each repo's `skill/` folder and placed in:
- Claude Code: `~/.claude/skills/<skill-name>/`
- Codex: `~/.codex/skills/<skill-name>/`

## Windows (PowerShell)

```powershell
# Install all tools
.\fetch-kit.ps1 install

# Check versions
.\fetch-kit.ps1 status

# Install skills for Claude Code
.\fetch-kit.ps1 skills -t claude

# Update everything
.\fetch-kit.ps1 update
```

## How It Works

- **Python tools** — installed via `uv tool install` (auto-installs uv if missing)
- **Go tools** — downloads the platform binary (tar.gz or bare) to `~/.local/bin/`
- **Version check** — tries `--version` first, falls back to `uv tool list`
- **GitHub API** — prefers authenticated `gh` CLI (5000 req/hr), falls back to anonymous curl

## Adding a New Tool

Append one line to `TOOL_REGISTRY`:

```bash
# Format: cmd|repo|type|pkg|branch|skill_name|has_refs
"my-tool|my-tool-repo|python|my-pkg|main|my-tool|yes"
```

Fields:
- `cmd` — CLI command name (e.g. `ak`)
- `repo` — GitHub repo name under `ryanlq/`
- `type` — `python` or `go`
- `pkg` — Python package name (for uv) or binary name (for go)
- `branch` — default git branch (`main` or `master`)
- `skill` — skill folder name in the repo's `skill/` directory
- `has_refs` — `yes` if the skill has a `references/` subdirectory to download

That's it — install, update, status, skills all work automatically.

## Requirements

- **Bash**: macOS / Linux (or WSL on Windows)
- **PowerShell**: Windows (PowerShell 7+ recommended)
- `curl` or `gh` CLI (for GitHub API access)
- `uv` for Python tools (auto-installed if missing)

## License

MIT
