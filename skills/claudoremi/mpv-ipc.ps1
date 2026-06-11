# mpv IPC helper - sends a JSON command to the mpv named pipe.
# Use -Read for queries that expect a response (include "request_id" in the JSON).
param(
    [Parameter(Mandatory = $true)][string]$Json,
    [switch]$Read,
    [string]$PipeName = 'mpv-claude',
    [int]$TimeoutMs = 3000
)

$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
try {
    $pipe.Connect($TimeoutMs)
} catch {
    Write-Output 'mpv is not running (pipe not found)'
    exit 1
}

$writer = New-Object System.IO.StreamWriter($pipe)
$writer.AutoFlush = $true
$writer.WriteLine($Json)

if ($Read) {
    $reader = New-Object System.IO.StreamReader($pipe)
    # mpv also pushes unsolicited event lines on the pipe; skip until the actual reply
    for ($i = 0; $i -lt 10; $i++) {
        $line = $reader.ReadLine()
        if ($null -eq $line) { break }
        if ($line -match '"request_id"') { Write-Output $line; break }
    }
}

$pipe.Close()
exit 0
