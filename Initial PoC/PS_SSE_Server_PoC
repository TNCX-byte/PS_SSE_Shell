$port = 11170
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()

Write-Host "SSE server running at http://localhost:$port/stream" -ForegroundColor Green
Write-Host "Stop with: iwr http://localhost:$port/shutdown" -ForegroundColor Green

$Shutdown = $false
$NextCommand = $null
$SSEWriter = $null

while (-not $Shutdown) {
    if ($SSEWriter -and -not $NextCommand) {
        $NextCommand = Read-Host '( PSSEShell )>>'
    }

    if ($NextCommand -and $SSEWriter -and $SSEWriter.BaseStream.CanWrite) {
        $SSEWriter.Write("data: $NextCommand`n`n")
        $SSEWriter.Flush()
        $NextCommand = $null
    }

    # Block until request comes in
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    switch ($request.Url.AbsolutePath) {
        "/shutdown" {
            $response.StatusCode = 200
            $response.OutputStream.Close()
            $Shutdown = $true
            $listener.Stop()
            $listener.Close()
            Write-Host "[x] Server shut down."
            break
        }

        "/stream" {
            $response.StatusCode = 200
            $response.ContentType = "text/event-stream"
            $response.Headers.Add("Cache-Control", "no-cache")
            $response.Headers.Add("Connection", "keep-alive")

            $SSEWriter = New-Object System.IO.StreamWriter($response.OutputStream)
            Write-Host "[+] Client connected to /stream"

            # Don't close keep it open
            continue
        }

        "/result" {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $output = $reader.ReadToEnd()
            $reader.Close()

            if (-not [string]::IsNullOrWhiteSpace($output)) {
                Write-Host "`n[Client Output] >>" -ForegroundColor Yellow
                Write-Host $output -ForegroundColor Cyan
            } else {
                Write-Warning "Received empty result payload."
            }

            $response.StatusCode = 200
            $response.Close()
            continue
        }

        default {
            $response.StatusCode = 404
            $response.Close()
        }
    }

    Start-Sleep -Milliseconds 100
}
