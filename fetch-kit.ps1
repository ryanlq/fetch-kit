#!/usr/bin/env pwsh
<#
.SYNOPSIS
fetch-kit — Unified installer for ryanlq CLI tools

.DESCRIPTION
One-click install, update, version check, and skill installation
for ai-experience-learner, akshare-cli, get-news, and mail-send.

.EXAMPLE
.\fetch-kit.ps1 install
.\fetch-kit.ps1 status
.\fetch-kit.ps1 skills -Target claude
#>

$ErrorActionPreference = "Stop"
$VERSION = "0.2.0"

# ──────────────────────────────────────────────
# Tool registry
# Format: cmd|repo|type|pkg|branch|skill_name|has_refs
# To add a new tool: just append one line below.
# ──────────────────────────────────────────────
$script:Owner = "ryanlq"

$script:ToolRegistry = @(
    "xp|ai-experience-learner|python|ai-experience-learner|master|experience-learner|no"
    "ak|akshare-cli|python|akcli|main|akshare-cli|yes"
    "get-news|get-news|python|get-news|main|get-news|yes"
    "mail-send|mail-send|go|mail-send|main|mail-send|no"
)

# ──────────────────────────────────────────────
# Registry accessor
# ──────────────────────────────────────────────
function tget {
    param([string]$Tool, [string]$Field)
    $idx = switch ($Field) {
        "cmd"      { 0 }
        "repo"     { 1 }
        "type"     { 2 }
        "pkg"      { 3 }
        "branch"   { 4 }
        "skill"    { 5 }
        "has_refs" { 6 }
        default    { return "" }
    }
    foreach ($entry in $script:ToolRegistry) {
        $parts = $entry -split '\|'
        if ($parts[0] -eq $Tool) {
            return $parts[$idx]
        }
    }
    return ""
}

function All-Tools {
    $script:ToolRegistry | ForEach-Object { ($_ -split '\|')[0] }
}

# ──────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────
function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Blue }
function Write-Ok($msg)    { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# ──────────────────────────────────────────────
# Platform detection
# ──────────────────────────────────────────────
function Get-Platform {
    $os = "windows"
    $arch = if ([Environment]::Is64BitProcess -or [Environment]::Is64BitOperatingSystem) { "amd64" } else { "arm64" }
    # Detect if running under WSL or native
    if ($IsLinux) { $os = "linux" }
    elseif ($IsMacOS) { $os = "darwin" }
    return "${os}-${arch}"
}

# ──────────────────────────────────────────────
# GitHub API
# ──────────────────────────────────────────────
function Invoke-GhGet {
    param([string]$Url)
    try {
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            $apiPath = $Url -replace '^https://api\.github\.com', ''
            $result = gh api $apiPath --jq '.' 2>$null
            if ($LASTEXITCODE -eq 0 -and $result) { return $result }
        }
    } catch {}
    try {
        $resp = Invoke-RestMethod -Uri $Url -Headers @{ Accept = "application/vnd.github+json" } -ErrorAction Stop
        return ($resp | ConvertTo-Json -Depth 10)
    } catch {
        return ""
    }
}

function Get-LatestReleaseTag {
    param([string]$Repo)
    $json = Invoke-GhGet "https://api.github.com/repos/$script:Owner/$Repo/releases/latest"
    if (-not $json) { return "" }
    try {
        $data = $json | ConvertFrom-Json
        return $data.tag_name
    } catch {
        if ($json -match '"tag_name"\s*:\s*"([^"]+)"') { return $Matches[1] }
        return ""
    }
}

# ──────────────────────────────────────────────
# Version helpers
# ──────────────────────────────────────────────
function Get-InstalledVersion {
    param([string]$Cmd, [string]$Type, [string]$Pkg)
    $ver = ""

    # 1) Try --version (preferred)
    try {
        $ver = & $Cmd --version 2>$null
        if ($ver -and $ver -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    } catch {}

    # 2) Fallback: uv tool list for Python tools
    if ($Type -eq "python" -and (Get-Command uv -ErrorAction SilentlyContinue)) {
        $list = uv tool list 2>$null
        $line = $list | Where-Object { $_ -match "^$Pkg " } | Select-Object -First 1
        if ($line -match 'v(\d+\.\d+\.\d+)') { return $Matches[1] }
    }

    return ""
}

# ──────────────────────────────────────────────
# Install
# ──────────────────────────────────────────────
function Install-Tool {
    param([string]$Tool)
    $repo   = tget $Tool repo
    $type   = tget $Tool type
    $pkg    = tget $Tool pkg
    $branch = tget $Tool branch

    $tag = Get-LatestReleaseTag $repo
    if (-not $tag) {
        Write-Err "Could not determine latest version for $Tool"
        return
    }

    switch ($type) {
        "python" {
            Check-Uv
            Write-Info "Installing $Tool ($tag)..."
            try {
                uv tool install "git+https://github.com/$script:Owner/$repo.git" --force 2>$null
            } catch {
                $whlUrl = "https://github.com/$script:Owner/$repo/releases/download/$tag/$pkg-$($tag.TrimStart('v'))-py3-none-any.whl"
                uv tool install $whlUrl --force
            }
        }
        "go" {
            $platform = Get-Platform
            $installDir = Join-Path $env:USERPROFILE ".local\bin"
            New-Item -ItemType Directory -Force -Path $installDir | Out-Null

            # Windows uses .exe suffix
            $binaryName = if ($platform -match "windows") { "$Tool-$platform.exe" } else { "$Tool-$platform" }
            $url = "https://github.com/$script:Owner/$repo/releases/download/$tag/$binaryName"
            $dest = Join-Path $installDir "$Tool.exe"

            Write-Info "Downloading $Tool ($tag) for $platform..."
            try {
                Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
            } catch {
                # Fallback: try without .exe in asset name (some releases use just os-arch)
                $binaryName2 = "$Tool-$platform"
                $url2 = "https://github.com/$script:Owner/$repo/releases/download/$tag/$binaryName2"
                try {
                    Invoke-WebRequest -Uri $url2 -OutFile $dest -ErrorAction Stop
                } catch {
                    Write-Err "Failed to download $Tool"
                    return
                }
            }
        }
    }

    $cmd = Get-Command $Tool -ErrorAction SilentlyContinue
    if ($cmd) {
        $ver = try { & $Tool --version 2>$null } catch { $tag }
        Write-Ok "$Tool installed: $ver"
    } else {
        Write-Warn "$Tool installed but not in PATH. Restart your shell."
    }
}

function Check-Uv {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Warn "uv not found. Installing uv..."
        try {
            $installScript = Invoke-RestMethod -Uri "https://astral.sh/uv/install.ps1"
            $installScript | Invoke-Expression
        } catch {
            Write-Err "Failed to install uv. See: https://docs.astral.sh/uv/"
            return
        }
        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            Write-Err "uv still not found after install. Restart your shell."
            return
        }
        Write-Ok "uv installed"
    }
}

# ──────────────────────────────────────────────
# Update
# ──────────────────────────────────────────────
function Update-Tool {
    param([string]$Tool)
    $repo = tget $Tool repo
    $type = tget $Tool type
    $pkg  = tget $Tool pkg

    $current = Get-InstalledVersion $Tool $type $pkg
    $latest  = Get-LatestReleaseTag $repo
    $latestClean = $latest.TrimStart("v")

    if (-not $current) {
        Write-Warn "$Tool not installed. Installing..."
        Install-Tool $Tool
        return
    }

    if ($current -eq $latestClean) {
        Write-Ok "$Tool is up to date ($current)"
        return
    }

    Write-Info "Updating $Tool: $current -> $latestClean"
    switch ($type) {
        "python" {
            Check-Uv
            try { uv tool upgrade $pkg 2>$null } catch { Install-Tool $Tool }
        }
        "go" {
            Install-Tool $Tool
        }
    }
    Write-Ok "$Tool updated to $latestClean"
}

# ──────────────────────────────────────────────
# Uninstall
# ──────────────────────────────────────────────
function Uninstall-Tool {
    param([string]$Tool)
    $type = tget $Tool type
    $pkg  = tget $Tool pkg

    switch ($type) {
        "python" {
            Check-Uv
            try {
                uv tool uninstall $pkg 2>$null
                Write-Ok "$Tool uninstalled"
            } catch {
                Write-Warn "$Tool not installed via uv"
            }
        }
        "go" {
            $target = Join-Path $env:USERPROFILE ".local\bin\$Tool.exe"
            if (Test-Path $target) {
                Remove-Item $target -Force
                Write-Ok "$Tool uninstalled"
            } else {
                Write-Warn "$Tool binary not found at $target"
            }
        }
    }
}

# ──────────────────────────────────────────────
# Skill installation
# ──────────────────────────────────────────────
function Install-SkillForTool {
    param([string]$Tool, [string]$Target = "claude")
    $repo     = tget $Tool repo
    $branch   = tget $Tool branch
    $skill    = tget $Tool skill
    $has_refs = tget $Tool has_refs

    if (-not $skill) {
        Write-Warn "$Tool has no skill definition"
        return
    }

    Write-Info "Installing skill '$skill' for $Target..."

    $skillDir = switch ($Target) {
        "claude" { Join-Path $env:USERPROFILE ".claude\skills\$skill" }
        "codex"  { Join-Path $env:USERPROFILE ".codex\skills\$skill" }
        default  { Write-Err "Unknown target: $Target. Use 'claude' or 'codex'"; return }
    }
    New-Item -ItemType Directory -Force -Path $skillDir | Out-Null

    $baseUrl = "https://raw.githubusercontent.com/$script:Owner/$repo/$branch/skill/$skill"

    # Download SKILL.md
    $skillUrl = "$baseUrl/SKILL.md"
    $skillFile = Join-Path $skillDir "SKILL.md"
    try {
        Invoke-WebRequest -Uri $skillUrl -OutFile $skillFile -ErrorAction Stop
    } catch {
        Write-Err "Failed to download SKILL.md for $skill"
        Remove-Item $skillDir -Recurse -Force -ErrorAction SilentlyContinue
        return
    }

    # Download references
    if ($has_refs -eq "yes") {
        $refsDir = Join-Path $skillDir "references"
        New-Item -ItemType Directory -Force -Path $refsDir | Out-Null
        Write-Info "Downloading references..."

        $contentsUrl = "https://api.github.com/repos/$script:Owner/$repo/contents/skill/$skill/references?ref=$branch"
        $json = Invoke-GhGet $contentsUrl
        if ($json) {
            try {
                $data = $json | ConvertFrom-Json
                foreach ($item in $data) {
                    if ($item.type -eq "file") {
                        $refUrl = "$baseUrl/references/$($item.name)"
                        $refFile = Join-Path $refsDir $item.name
                        try { Invoke-WebRequest -Uri $refUrl -OutFile $refFile -ErrorAction Stop } catch {}
                    }
                }
            } catch {}
        }
    }

    Write-Ok "Skill '$skill' installed to $skillDir"
}

# ──────────────────────────────────────────────
# Status
# ──────────────────────────────────────────────
function Show-Status {
    Write-Host "fetch-kit - Tool Status" -ForegroundColor White
    Write-Host ""
    Write-Host ("  {0,-15} {1,-12} {2,-12} {3}" -f "TOOL", "INSTALLED", "LATEST", "STATUS")
    Write-Host ("  {0,-15} {1,-12} {2,-12} {3}" -f "----", "---------", "------", "------")

    foreach ($tool in (All-Tools)) {
        $repo = tget $tool repo
        $type = tget $tool type
        $pkg  = tget $tool pkg

        $current = Get-InstalledVersion $tool $type $pkg
        if (-not $current) { $current = "-" }

        $latest = Get-LatestReleaseTag $repo
        $latestClean = $latest.TrimStart("v")
        if (-not $latestClean) { $latestClean = "?" }

        $status = if ($current -eq "-") { "missing" }
                  elseif ($latestClean -eq "?") { "unknown" }
                  elseif ($current -eq $latestClean) { "up to date" }
                  else { "update available" }

        $statusColor = switch ($status) {
            "missing"           { "Red" }
            "up to date"        { "Green" }
            "update available"  { "Yellow" }
            default             { "Yellow" }
        }

        Write-Host ("  {0,-15} {1,-12} {2,-12} " -f $tool, $current, $latestClean) -NoNewline
        Write-Host $status -ForegroundColor $statusColor
    }
    Write-Host ""
}

# ──────────────────────────────────────────────
# Resolve tool names from args
# ──────────────────────────────────────────────
function Resolve-Tools {
    param([string[]]$Names)
    $all = @(All-Tools)
    if ($Names.Count -eq 0) { return $all }

    $resolved = @()
    foreach ($name in $Names) {
        if ($all -contains $name) {
            $resolved += $name
        } else {
            # Try matching by repo name
            foreach ($entry in $script:ToolRegistry) {
                $parts = $entry -split '\|'
                if ($parts[1] -eq $name) { $resolved += $parts[0]; break }
            }
        }
    }
    return $resolved
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
$Command = ""
$Target = ""
$ToolArgs = @()

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        { $_ -in @("install", "update", "uninstall", "status", "skills", "self-update", "-h", "--help", "help", "-v", "--version") } {
            $Command = $_
        }
        { $_ -in @("-t", "--target") } {
            $i++
            $Target = $args[$i]
        }
        default {
            $ToolArgs += $_
        }
    }
    $i++
}

if (-not $Command -or $Command -in @("-h", "--help", "help")) {
    Write-Host "fetch-kit v$VERSION - Unified installer for ryanlq CLI tools" -ForegroundColor White
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\fetch-kit.ps1 <command> [options]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  install [TOOL...]       Install one or more tools (default: all)"
    Write-Host "  update  [TOOL...]       Update one or more tools (default: all)"
    Write-Host "  status                  Show installed versions vs latest"
    Write-Host "  skills [TOOL...] -t T   Install skills to target (claude|codex)"
    Write-Host "  uninstall [TOOL...]     Uninstall one or more tools"
    Write-Host ""
    Write-Host "Tools:"
    Write-Host "  xp          ai-experience-learner (Python)"
    Write-Host "  ak          akshare-cli (Python)"
    Write-Host "  get-news    get-news (Python)"
    Write-Host "  mail-send   mail-send (Go)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\fetch-kit.ps1 install"
    Write-Host "  .\fetch-kit.ps1 update xp ak"
    Write-Host "  .\fetch-kit.ps1 skills -t claude"
    exit 0
}

if ($Command -eq "-v" -or $Command -eq "--version") {
    Write-Host "fetch-kit v$VERSION"
    exit 0
}

switch ($Command) {
    "install" {
        foreach ($tool in (Resolve-Tools $ToolArgs)) {
            Write-Host ""
            Install-Tool $tool
        }
    }
    "update" {
        foreach ($tool in (Resolve-Tools $ToolArgs)) {
            Write-Host ""
            Update-Tool $tool
        }
    }
    "uninstall" {
        foreach ($tool in (Resolve-Tools $ToolArgs)) {
            Uninstall-Tool $tool
        }
    }
    "status" {
        Show-Status
    }
    "skills" {
        if (-not $Target) {
            Write-Err "Missing target. Use: -t claude or -t codex"
            exit 1
        }
        foreach ($tool in (Resolve-Tools $ToolArgs)) {
            Write-Host ""
            Install-SkillForTool $tool $Target
        }
    }
    "self-update" {
        Write-Info "Self-update not yet available."
    }
}
