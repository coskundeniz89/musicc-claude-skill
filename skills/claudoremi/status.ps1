# Prints a one-line status: Windows master volume, mpv volume/mute, what's playing, position.
# Always run this before adjusting volume - the user changes knobs by hand too.
$ErrorActionPreference = 'SilentlyContinue'
$mu = $PSScriptRoot

$master = & "$mu\master-volume.ps1"

function Get-MpvProp([string]$Prop, [int]$Id) {
    $line = & "$mu\mpv-ipc.ps1" -Json ('{"command":["get_property","' + $Prop + '"],"request_id":' + $Id + '}') -Read
    if ($LASTEXITCODE -eq 0 -and $line -match '"request_id"') { ($line | ConvertFrom-Json).data }
}

$title = Get-MpvProp 'media-title' 1
if ($null -ne $title) {
    $vol = [math]::Round((Get-MpvProp 'volume' 2))
    $mute = Get-MpvProp 'mute' 3
    $pos = Get-MpvProp 'playback-time' 4
    $time = if ($null -ne $pos) { [timespan]::FromSeconds([math]::Round($pos)).ToString('hh\:mm\:ss') } else { '?' }
    "$master | mpv: $vol% (mute: $mute) | playing: $title @ $time"
} else {
    "$master | mpv: not running"
}
exit 0
