#Requires -Version 5.1
<#
claudoremi installer - copies the skill into ~/.claude/skills/claudoremi and sets up
dependencies. Run from the repo root:

    ./setup.ps1
#>
[CmdletBinding()]
param(
    [string]$Target = (Join-Path $HOME '.claude\skills\claudoremi')
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'skills\claudoremi'

Write-Host "Installing claudoremi skill -> $Target"
New-Item -ItemType Directory -Force -Path $Target | Out-Null
Copy-Item (Join-Path $src '*') $Target -Recurse -Force

# mpv - the actual audio player
$mpv = (Get-Command mpv -ErrorAction SilentlyContinue).Source
if (-not $mpv) {
    $mpv = @('C:\Program Files\MPV Player\mpv.exe', "$env:LOCALAPPDATA\Programs\mpv\mpv.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ($mpv) {
    Write-Host "mpv found: $mpv"
} else {
    Write-Host 'mpv not found - installing via winget (shinchiro.mpv)...'
    winget install -e --id shinchiro.mpv --accept-source-agreements --accept-package-agreements
}

# yt-dlp - always a fresh local copy (system copies are often outdated and break with YouTube)
Write-Host 'Downloading latest yt-dlp...'
Invoke-WebRequest 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' `
    -OutFile (Join-Path $Target 'yt-dlp.exe')

# Node.js - needed by yt-dlp's YouTube challenge solver and the cookie bridge
if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Host "Node.js found: $(node --version)"
} else {
    Write-Warning 'Node.js not found. YouTube playback needs it. Install with: winget install -e --id OpenJS.NodeJS.LTS'
}

Write-Host ''
Write-Host 'Done. Start a new Claude Code session and say: "play some music"'
