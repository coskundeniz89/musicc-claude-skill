# Tests for mpv-ipc.ps1 - run without mpv by emulating the IPC pipe server.
# Usage: pwsh -File tests/mpv-ipc.test.ps1
$ErrorActionPreference = 'Stop'
$ipcScript = Join-Path $PSScriptRoot '..\skills\claudoremi\mpv-ipc.ps1'
$script:failures = 0

function Assert([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "  ok   - $Message" }
    else { Write-Host "  FAIL - $Message"; $script:failures++ }
}

function Start-PipeServer([string]$Name, [string[]]$Reply) {
    Start-Job -ScriptBlock {
        param($Name, $Reply)
        $server = New-Object System.IO.Pipes.NamedPipeServerStream($Name, [System.IO.Pipes.PipeDirection]::InOut)
        $server.WaitForConnection()
        $reader = New-Object System.IO.StreamReader($server)
        $received = $reader.ReadLine()
        if ($Reply.Count -gt 0) {
            $writer = New-Object System.IO.StreamWriter($server)
            $writer.AutoFlush = $true
            foreach ($line in $Reply) { $writer.WriteLine($line) }
            Start-Sleep -Milliseconds 500   # let the client finish reading before closing
        }
        $server.Close()
        $received
    } -ArgumentList $Name, $Reply
}

Write-Host 'mpv-ipc.ps1 tests'

# --- fire-and-forget: command reaches the pipe verbatim ---
$pipeName = "claudoremi-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$job = Start-PipeServer -Name $pipeName -Reply @()
Start-Sleep -Seconds 2
$json = '{"command":["cycle","pause"]}'
$out = & $ipcScript -Json $json -PipeName $pipeName -TimeoutMs 10000
$received = Receive-Job -Job $job -Wait
Remove-Job -Job $job -Force
Assert ($LASTEXITCODE -eq 0) 'fire-and-forget exits 0'
Assert ($received -eq $json) 'server received the exact JSON line'
Assert ([string]::IsNullOrEmpty($out)) 'no output without -Read'

# --- -Read: returns the reply line, skipping unsolicited event lines ---
$pipeName = "claudoremi-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$job = Start-PipeServer -Name $pipeName -Reply @(
    '{"event":"property-change","name":"volume"}',
    '{"data":55.0,"request_id":7,"error":"success"}'
)
Start-Sleep -Seconds 2
$out = & $ipcScript -Json '{"command":["get_property","volume"],"request_id":7}' -PipeName $pipeName -TimeoutMs 10000 -Read
Receive-Job -Job $job -Wait | Out-Null
Remove-Job -Job $job -Force
Assert ($out -match '"request_id":7') '-Read returns the matching reply'
Assert ($out -notmatch 'property-change') 'event lines are skipped'

# --- no pipe: clean failure ---
$out = & $ipcScript -Json '{"command":["quit"]}' -PipeName 'claudoremi-test-does-not-exist' -TimeoutMs 500
Assert ($LASTEXITCODE -eq 1) 'missing pipe exits 1'
Assert ($out -match 'not running') 'missing pipe prints a clear message'

if ($script:failures -gt 0) {
    Write-Host "`n$($script:failures) test(s) FAILED"
    exit 1
}
Write-Host "`nAll mpv-ipc tests passed."
exit 0
