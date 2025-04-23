# PSSEShell (Initial PoC) – PowerShell SSE-Based Reverse Shell

This is the **initial proof-of-concept** for a reverse shell built using Server-Sent Events (SSE) in pure PowerShell.  
It demonstrates the core idea of pushing commands from a server to a connected client over plain HTTP, with synchronous output handling.

## Components

- **Server:** Listens for incoming `/stream` connections, pushes commands via SSE, and receives output via `/result`.
- **Client:** Connects to the SSE stream, executes received commands, and sends output back to the server.

## How it works

1. The client connects to `/stream`.
2. The server waits for input via `Read-Host` and pushes commands over SSE.
3. The client executes the command and POSTs the result to `/result`.
4. Server prints the output.
5. Repeat.

## Important Note

This setup is fully synchronous:
- While waiting for a command (`Read-Host`) or receiving output (`GetContext()`), the server pauses all other activity.
- Only one client can be served at a time.
- This design ensures simplicity and direct control, but blocks further execution until each step completes.

## Shutting Down

You can cleanly shut down the server by running:

```powershell
iwr http://localhost:11170/shutdown

## Disclaimer

This project is provided for **educational and research purposes only**.  
Any use of this code for unauthorized access, control, or tampering with systems you do not own or have explicit permission to test is strictly prohibited.

The author assumes **no responsibility** for any misuse or damages caused by this project.  
Use it **at your own risk**, and always stay within the bounds of ethical security practices.

