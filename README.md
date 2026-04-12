# Vibe Anywhere

Control AI coding agents from your phone. Lightweight daemon + iOS app.

```
[iOS App] ←WebSocket (v2)→ [TS Daemon] ←ACP/stdio→ [Claude / Codex / Gemini]
```

## What

- Start coding sessions in any project directory from your iPhone
- Stream responses, tool calls, and token usage in real-time
- Approve/deny file writes and shell commands from a permission modal
- Switch models and modes mid-session
- Secure: Tailscale + bearer token, no cloud relay

## Structure

```
daemon/    # TypeScript, Node.js — WebSocket server + ACP agent manager
app/       # Swift, SwiftUI — iOS client (Xcode project)
docs/      # Design documents and PRDs
```

## Prerequisites

- **Node.js** ≥ 20
- **Claude Code** CLI installed and authenticated (`claude` in PATH)
- **Xcode** 16+ (for iOS app, macOS only)
- **Tailscale** (recommended for secure remote access)

---

## Daemon Setup

### 1. Install dependencies

```bash
cd daemon
npm install
```

### 2. Configure

First run auto-generates `~/.vibe-anywhere/config.yaml` with a random token:

```bash
npm run dev
```

Or create it manually:

```yaml
# ~/.vibe-anywhere/config.yaml
port: 7842
bind: 0.0.0.0
token: <your-secure-token>    # auto-generated on first run
allowedDirs:                   # directories agents are allowed to work in
  - ~/projects
  - ~/work
defaultAgent: claude           # default agent type (claude, codex, gemini)
acpx:
  path: npx                   # path to ACP executor
  permissionMode: prompt       # prompt | approve-all | deny-all
  timeout: 120                 # seconds per permission prompt
```

> **Security:** Config file is created with `0600` permissions. The token is shown once on first run — copy it to your iOS app.

### 3. Run (development)

```bash
cd daemon
npm run dev    # tsx watch — auto-restarts on file changes
```

### 4. Run (production)

```bash
cd daemon
npm run build
npm start
```

### 5. Test

```bash
cd daemon
npm test
```

---

## iOS App Setup

### 1. Open in Xcode

```bash
open app/VibeAnywhere.xcodeproj
```

### 2. Configure signing

- Select the `VibeAnywhere` target
- Under **Signing & Capabilities**, select your development team

### 3. Build & run

- Select an iOS 17+ simulator or device
- ⌘R to build and run

### 4. Connect to daemon

In the app:
1. Tap the ⚙️ gear icon
2. Enter your daemon's **host** (IP or Tailscale hostname)
3. Enter **port** (default: `7842`)
4. Enter the **bearer token** from your config
5. Tap **Connect**

### 5. Test

```bash
cd app
xcodebuild test \
  -project VibeAnywhere.xcodeproj \
  -scheme VibeAnywhere \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

---

## Architecture

### Daemon

| Module | Role |
|--------|------|
| `config.ts` | YAML config loader, token management, path validation |
| `server.ts` | WebSocket server with bearer token auth, ping/pong keepalive |
| `acp-manager.ts` | Multi-agent process manager via ACP protocol (stdio JSON-RPC) |
| `sessions.ts` | Session lifecycle: create, list, resume, destroy with 5-min reconnect window |
| `index.ts` | Entry point, wires everything together |

### iOS App

| Module | Role |
|--------|------|
| `WebSocketService` | URLSessionWebSocketTask with auto-reconnect (exponential backoff) |
| `KeychainService` | Secure token storage in iOS Keychain |
| `SessionViewModel` | Session CRUD, forwards events to active chat, LRU cache |
| `ChatViewModel` | Message list, tool call tracking, permission handling, mode/model control |
| `ChatView` | Chat UI with auto-scroll, cancel, permission modal overlay |
| `SessionSettingsSheet` | Mode/model picker, session info, permission history |
| `PermissionViews` | Permission approval modal + history list |
| `SessionListView` | Active sessions with resume on tap, swipe-to-delete |
| `SettingsView` | Server config form with connection status |

### Protocol (WebSocket JSON, v2)

**Client → Daemon:**
```json
{"type": "session/create", "cwd": "/path", "agent": "claude"}
{"type": "session/list"}
{"type": "session/resume", "sessionId": "uuid"}
{"type": "session/message", "sessionId": "uuid", "content": "hello"}
{"type": "session/cancel", "sessionId": "uuid"}
{"type": "session/destroy", "sessionId": "uuid"}
{"type": "session/set-mode", "sessionId": "uuid", "mode": "code"}
{"type": "session/set-model", "sessionId": "uuid", "model": "opus"}
{"type": "permission/respond", "sessionId": "uuid", "requestId": "r1", "optionId": "o1"}
```

**Daemon → Client:**
```json
{"type": "session/created", "sessionId": "uuid", "cwd": "/path"}
{"type": "session/list", "sessions": [{"sessionId": "...", "cwd": "...", "agent": "claude"}]}
{"type": "event/text", "sessionId": "uuid", "content": "partial text"}
{"type": "event/tool_call", "sessionId": "uuid", "toolCallId": "tc1", "tool": "read", "status": "running"}
{"type": "event/tool_call_update", "sessionId": "uuid", "toolCallId": "tc1", "status": "done"}
{"type": "event/permission_request", "sessionId": "uuid", "requestId": "r1", "tool": "write", "options": [...]}
{"type": "event/usage", "sessionId": "uuid", "inputTokens": 500, "outputTokens": 200}
{"type": "event/turn_end", "sessionId": "uuid", "stopReason": "end_turn"}
{"type": "event/session_info", "sessionId": "uuid", "agent": "claude", "models": ["opus", "sonnet"]}
{"type": "error", "message": "description"}
```

---

## Network Setup

The daemon binds to `0.0.0.0:7842` by default. For remote access:

**Option A: Tailscale (recommended)**
- Install Tailscale on both your Mac and iPhone
- Use the Tailscale IP/hostname as the host
- Traffic is encrypted end-to-end, no port forwarding needed

**Option B: Local network**
- Use your Mac's local IP (e.g., `192.168.1.x`)
- Both devices must be on the same WiFi

> ⚠️ **Do not expose the daemon to the public internet** without additional security.

---

## CI

GitHub Actions runs on every push to `main` and PRs:
- **Daemon job:** Node 20 — type check, build, test
- **iOS job:** macOS — Xcode build and test on iOS Simulator

## License

MIT
