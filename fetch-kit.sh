#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# fetch-kit — Unified installer for ryanlq CLI tools
# ──────────────────────────────────────────────

VERSION="0.4.0"
OWNER="ryanlq"
SCRIPT_URL="https://raw.githubusercontent.com/${OWNER}/fetch-kit/main/fetch-kit.sh"
INSTALL_DIR="${HOME}/.local/bin"

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()  { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
bold()  { printf "${BOLD}%s${NC}\n" "$*"; }

# ──────────────────────────────────────────────
# Tool registry
#
# Format: cmd|repo|type|pkg|branch|skill_name|has_refs
#   cmd       — CLI command name
#   repo      — GitHub repo name
#   type      — python | go
#   pkg       — Python package name (for uv/pip) or binary name (for go)
#   branch    — default git branch (main/master)
#   skill     — skill folder name under repo's skill/ directory
#   has_refs  — yes if skill has a references/ subdirectory
#
# To add a new tool: just append one line below.
# ──────────────────────────────────────────────

TOOL_REGISTRY=(
    "xp|ai-experience-learner|python|ai-experience-learner|master|experience-learner|no"
    "ak|akshare-cli|python|akcli|main|akshare-cli|yes"
    "get-news|get-news|python|get-news|main|get-news|yes"
    "olk|olkcli|go|olk|main|olk|no"
    "sequoia|Sequoia-X|python|sequoia_x|master|sequoia-x|no"
)

# ──────────────────────────────────────────────
# Registry accessor
# ──────────────────────────────────────────────
# Returns the requested field for a given tool cmd.
# Usage: tget xp repo  =>  ai-experience-learner
tget() {
    local tool="$1" field="$2"
    local idx
    case "$field" in
        cmd)   idx=0 ;;
        repo)  idx=1 ;;
        type)  idx=2 ;;
        pkg)   idx=3 ;;
        branch) idx=4 ;;
        skill) idx=5 ;;
        has_refs) idx=6 ;;
        *)     echo ""; return 1 ;;
    esac
    for entry in "${TOOL_REGISTRY[@]}"; do
        IFS='|' read -ra p <<< "$entry"
        if [[ "${p[0]}" == "$tool" ]]; then
            echo "${p[$idx]}"
            return
        fi
    done
    echo ""
    return 1
}

all_tools() {
    local result=()
    for entry in "${TOOL_REGISTRY[@]}"; do
        IFS='|' read -ra p <<< "$entry"
        result+=("${p[0]}")
    done
    echo "${result[*]}"
}

# ──────────────────────────────────────────────
# Platform detection
# ──────────────────────────────────────────────
detect_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"
    case "$os" in
        linux)   os="linux" ;;
        darwin)  os="darwin" ;;
        *)       err "Unsupported OS: $os"; exit 1 ;;
    esac
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)             err "Unsupported arch: $arch"; exit 1 ;;
    esac
    echo "${os}-${arch}"
}

# ──────────────────────────────────────────────
# GitHub API helpers
# ──────────────────────────────────────────────
gh_get() {
    local url="$1"
    if command -v gh &>/dev/null; then
        gh api "${url#https://api.github.com}" --jq '.' 2>/dev/null && return
    fi
    curl -sL -H "Accept: application/vnd.github+json" "$url"
}

get_latest_release_tag() {
    local repo="$1"
    local tag
    tag=$(gh_get "https://api.github.com/repos/${OWNER}/${repo}/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' || true)
    echo "${tag}"
}

# ──────────────────────────────────────────────
# Version helpers
# ──────────────────────────────────────────────
get_installed_version() {
    local cmd="$1" type="$2" pkg="$3"
    local ver=""

    # 1) Try --version (universal, preferred)
    ver=$(${cmd} --version 2>/dev/null || true)

    # 2) Fallback: ask uv for the installed version
    if [[ -z "$ver" ]] && [[ "$type" == "python" ]] && command -v uv &>/dev/null; then
        ver=$(uv tool list 2>/dev/null | grep -A1 "^${pkg} " | head -1 | grep -oP 'v\K\d+\.\d+\.\d+' || true)
    fi

    echo "$ver" | grep -oP '\d+\.\d+\.\d+' | head -1 || true
}

# ──────────────────────────────────────────────
# Install
# ──────────────────────────────────────────────
check_uv() {
    if ! command -v uv &>/dev/null; then
        warn "uv not found. Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        if ! command -v uv &>/dev/null; then
            err "Failed to install uv. Please install manually: https://docs.astral.sh/uv/"
            exit 1
        fi
        ok "uv installed"
    fi
}

install_tool() {
    local tool="$1"
    local repo  repo=$(tget "$tool" repo)
    local type; type=$(tget "$tool" type)
    local pkg;   pkg=$(tget "$tool" pkg)

    local tag
    tag=$(get_latest_release_tag "$repo")
    if [[ -z "$tag" ]]; then
        err "Could not determine latest version for ${tool}"
        return 1
    fi

    case "$type" in
        python)
            check_uv
            info "Installing ${tool} (${tag})..."
            uv tool install "git+https://github.com/${OWNER}/${repo}.git" --force 2>/dev/null \
                || uv tool install "https://github.com/${OWNER}/${repo}/releases/download/${tag}/${pkg}-${tag#v}-py3-none-any.whl" --force
            ;;
        go)
            local platform; platform=$(detect_platform)
            local install_dir="${HOME}/.local/bin"
            mkdir -p "$install_dir"
            info "Downloading ${tool} (${tag}) for ${platform}..."
            local tmpfile; tmpfile=$(mktemp)
            local ver_clean="${tag#v}"
            # Try goreleaser tar.gz first, fall back to bare binary
            local platform_underscore="${platform//-/_}"
            local archive_url="https://github.com/${OWNER}/${repo}/releases/download/${tag}/${tool}_${ver_clean}_${platform_underscore}.tar.gz"
            local bare_url="https://github.com/${OWNER}/${repo}/releases/download/${tag}/${tool}-${platform}"
            if curl -sLf "$archive_url" -o "$tmpfile" 2>/dev/null; then
                tar xzf "$tmpfile" -C "$install_dir" "$tool" 2>/dev/null \
                    || tar xzf "$tmpfile" -C "$install_dir" 2>/dev/null
                rm -f "$tmpfile"
                chmod +x "${install_dir}/${tool}"
            elif curl -sLf "$bare_url" -o "$tmpfile" 2>/dev/null; then
                chmod +x "$tmpfile"
                mv "$tmpfile" "${install_dir}/${tool}"
            else
                rm -f "$tmpfile"
                err "Failed to download ${tool}"
                return 1
            fi
            ;;
    esac

    if command -v "$tool" &>/dev/null; then
        ok "${tool} installed: $(${tool} --version 2>/dev/null || echo "${tag}")"
    else
        warn "${tool} installed but command not in PATH. Run: source ~/.profile or restart shell"
    fi
}

# ──────────────────────────────────────────────
# Update
# ──────────────────────────────────────────────
update_tool() {
    local tool="$1"
    local repo;  repo=$(tget "$tool" repo)
    local type;  type=$(tget "$tool" type)
    local pkg;   pkg=$(tget "$tool" pkg)

    local current
    current=$(get_installed_version "$tool" "$type" "$pkg")
    local latest
    latest=$(get_latest_release_tag "$repo")
    local latest_clean="${latest#v}"

    if [[ -z "$current" ]]; then
        warn "${tool} not installed. Installing..."
        install_tool "$tool"
        return
    fi

    if [[ "$current" == "$latest_clean" ]]; then
        ok "${tool} is up to date (${current})"
        return
    fi

    info "Updating ${tool}: ${current} -> ${latest_clean}"
    case "$type" in
        python)
            check_uv
            uv tool upgrade "$pkg" 2>/dev/null || install_tool "$tool"
            ;;
        go)
            install_tool "$tool"
            ;;
    esac
    ok "${tool} updated to ${latest_clean}"
}

# ──────────────────────────────────────────────
# Uninstall
# ──────────────────────────────────────────────
uninstall_tool() {
    local tool="$1"
    local type; type=$(tget "$tool" type)
    local pkg;  pkg=$(tget "$tool" pkg)

    case "$type" in
        python)
            check_uv
            uv tool uninstall "$pkg" 2>/dev/null && ok "${tool} uninstalled" \
                || warn "${tool} not installed via uv"
            ;;
        go)
            local target="${HOME}/.local/bin/${tool}"
            if [[ -f "$target" ]]; then
                rm -f "$target" && ok "${tool} uninstalled"
            else
                warn "${tool} binary not found at ${target}"
            fi
            ;;
    esac
}

# ──────────────────────────────────────────────
# Skill installation
# ──────────────────────────────────────────────
install_skill_for_tool() {
    local tool="$1"
    local target="${2:-claude}"
    local repo;    repo=$(tget "$tool" repo)
    local branch;  branch=$(tget "$tool" branch)
    local skill;   skill=$(tget "$tool" skill)
    local has_refs; has_refs=$(tget "$tool" has_refs)

    if [[ -z "$skill" ]]; then
        warn "${tool} has no skill definition"
        return
    fi

    info "Installing skill '${skill}' for ${target}..."

    local skill_dir
    case "$target" in
        claude) skill_dir="${HOME}/.claude/skills/${skill}" ;;
        codex)  skill_dir="${HOME}/.codex/skills/${skill}" ;;
        *)      err "Unknown target: ${target}. Use 'claude' or 'codex'"; return 1 ;;
    esac
    mkdir -p "$skill_dir"

    local base_url="https://raw.githubusercontent.com/${OWNER}/${repo}/${branch}/skill/${skill}"
    local root_url="https://raw.githubusercontent.com/${OWNER}/${repo}/${branch}"

    # Try skill/ subdirectory first, fall back to root SKILL.md
    curl -sL "${base_url}/SKILL.md" -o "${skill_dir}/SKILL.md"
    if [[ ! -s "${skill_dir}/SKILL.md" ]]; then
        curl -sL "${root_url}/SKILL.md" -o "${skill_dir}/SKILL.md"
    fi
    if [[ ! -s "${skill_dir}/SKILL.md" ]]; then
        err "Failed to download SKILL.md for ${skill}"
        rm -rf "$skill_dir"
        return 1
    fi

    if [[ "$has_refs" == "yes" ]]; then
        mkdir -p "${skill_dir}/references"
        info "Downloading references..."
        for ref_file in $(gh_get "https://api.github.com/repos/${OWNER}/${repo}/contents/skill/${skill}/references?ref=${branch}" \
            | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    for f in data:
        if f.get('type') == 'file':
            print(f['name'])
" 2>/dev/null); do
            curl -sL "${base_url}/references/${ref_file}" -o "${skill_dir}/references/${ref_file}"
        done
    fi

    ok "Skill '${skill}' installed to ${skill_dir}"
}

# ──────────────────────────────────────────────
# Status
# ──────────────────────────────────────────────
show_status() {
    bold "fetch-kit — Tool Status"
    echo ""
    printf "  %-15s %-12s %-12s %-10s\n" "TOOL" "INSTALLED" "LATEST" "STATUS"
    printf "  %-15s %-12s %-12s %-10s\n" "────" "─────────" "──────" "──────"

    local tools; tools=$(all_tools)
    for tool in $tools; do
        local repo;  repo=$(tget "$tool" repo)
        local type;  type=$(tget "$tool" type)
        local pkg;   pkg=$(tget "$tool" pkg)

        local current
        current=$(get_installed_version "$tool" "$type" "$pkg" 2>/dev/null || true)
        [[ -z "$current" ]] && current="-"

        local latest
        latest=$(get_latest_release_tag "$repo" 2>/dev/null || true)
        latest="${latest#v}"
        [[ -z "$latest" ]] && latest="?"

        local status
        if [[ "$current" == "-" ]]; then
            status="${RED}missing${NC}"
        elif [[ "$latest" == "?" ]]; then
            status="${YELLOW}unknown${NC}"
        elif [[ "$current" == "$latest" ]]; then
            status="${GREEN}up to date${NC}"
        else
            status="${YELLOW}update available${NC}"
        fi

        printf "  %-15s %-12s %-12s " "$tool" "$current" "$latest"
        echo -e "$status"
    done
    echo ""
}

# ──────────────────────────────────────────────
# Main CLI
# ──────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}fetch-kit${NC} v${VERSION} — Unified installer for ryanlq CLI tools

${BOLD}Usage:${NC}
  fetch-kit <command> [options]

${BOLD}Commands:${NC}
  install [TOOL...]     Install one or more tools (default: all)
  update  [TOOL...]     Update one or more tools (default: all)
  upgrade              Update fetch-kit itself to the latest version
  status                Show installed versions vs latest
  skills  [TOOL...] -t TARGET
                        Install skills to target (claude|codex)
  uninstall [TOOL...]   Uninstall one or more tools

${BOLD}Tools:${NC}
  xp          ai-experience-learner (Python) — distill & recall experience
  ak          akshare-cli (Python) — Chinese financial data CLI
  get-news    get-news (Python) — multi-step web scraper
  olk         olkcli (Go) — Microsoft Outlook CLI via Graph API
  sequoia     Sequoia-X (Python) — A股量化选股系统

${BOLD}Adding a new tool:${NC}
  Append one line to TOOL_REGISTRY in this script:
    "cmd|repo-name|type|pkg-name|branch|skill-folder|has_refs"

${BOLD}Examples:${NC}
  fetch-kit install              # Install all tools
  fetch-kit install xp ak        # Install specific tools
  fetch-kit update               # Update all tools
  fetch-kit status               # Check versions
  fetch-kit skills -t claude     # Install all skills for Claude Code
  fetch-kit skills ak -t codex   # Install akshare-cli skill for Codex

EOF
}

resolve_tools() {
    local args=("$@")
    if [[ ${#args[@]} -eq 0 ]]; then
        all_tools
        return
    fi
    local resolved=()
    local all; all=$(all_tools)
    for arg in "${args[@]}"; do
        if [[ " $all " == *" $arg "* ]]; then
            resolved+=("$arg")
        else
            # Try matching by repo name
            for entry in "${TOOL_REGISTRY[@]}"; do
                IFS='|' read -ra p <<< "$entry"
                if [[ "${p[1]}" == "$arg" ]]; then
                    resolved+=("${p[0]}")
                    break
                fi
            done
        fi
    done
    echo "${resolved[*]}"
}

cmd_install() {
    local tools; tools=$(resolve_tools "$@")
    for tool in $tools; do
        echo ""
        install_tool "$tool"
    done
}

cmd_update() {
    local tools; tools=$(resolve_tools "$@")
    for tool in $tools; do
        echo ""
        update_tool "$tool"
    done
}

cmd_uninstall() {
    local tools; tools=$(resolve_tools "$@")
    for tool in $tools; do
        uninstall_tool "$tool"
    done
}

cmd_skills() {
    local target=""
    local tools_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--target) target="$2"; shift 2 ;;
            *) tools_args+=("$1"); shift ;;
        esac
    done

    if [[ -z "$target" ]]; then
        err "Missing target. Use: -t claude or -t codex"
        exit 1
    fi

    local tools; tools=$(resolve_tools "${tools_args[@]}")
    for tool in $tools; do
        echo ""
        install_skill_for_tool "$tool" "$target"
    done
}

cmd_self_update() {
    info "Updating fetch-kit..."
    local tmpfile; tmpfile=$(mktemp)
    if ! curl -sL "$SCRIPT_URL" -o "$tmpfile"; then
        rm -f "$tmpfile"
        err "Failed to download latest fetch-kit"
        return 1
    fi
    chmod +x "$tmpfile"
    mkdir -p "$INSTALL_DIR"
    mv "$tmpfile" "${INSTALL_DIR}/fetch-kit"
    local new_ver; new_ver=$("${INSTALL_DIR}/fetch-kit" --version 2>/dev/null || echo "unknown")
    ok "fetch-kit updated to ${new_ver}"
}

cmd_upgrade() {
    cmd_self_update
}

# ──────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────
# When piped via curl (no args, stdin is a pipe), self-install then install all tools.
if [[ $# -eq 0 ]] && [[ ! -t 0 ]]; then
    bold "Welcome to fetch-kit!"
    echo ""
    info "Installing fetch-kit to ${INSTALL_DIR}..."
    mkdir -p "$INSTALL_DIR"
    curl -sL "$SCRIPT_URL" -o "${INSTALL_DIR}/fetch-kit"
    chmod +x "${INSTALL_DIR}/fetch-kit"
    ok "fetch-kit v${VERSION} installed"
    echo ""
    export PATH="${INSTALL_DIR}:${PATH}"
    cmd_install
    echo ""
    bold "Done! Run 'fetch-kit status' to verify."
    exit 0
fi

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

command="$1"
shift

case "$command" in
    install)     cmd_install "$@" ;;
    update)      cmd_update "$@" ;;
    upgrade)     cmd_upgrade ;;
    uninstall)   cmd_uninstall "$@" ;;
    status)      show_status ;;
    skills)      cmd_skills "$@" ;;
    -h|--help|help) usage ;;
    -v|--version) echo "fetch-kit v${VERSION}" ;;
    *)           err "Unknown command: ${command}"; usage; exit 1 ;;
esac
