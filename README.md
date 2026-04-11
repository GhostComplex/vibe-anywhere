# Vibe Anywhere

Control Claude Code from your phone. Lightweight daemon + iOS app.

```
[iOS App] ←WebSocket→ [TS Daemon] ←stream-json/stdio→ [Claude Code]
```

## What

- Start Claude Code sessions in any project directory from your iPhone
- Stream responses and tool use in real-time
- Secure: Tailscale + bearer token, no cloud relay
- Tiny: ~2000 LOC total (daemon ~800, iOS ~600, tests ~600)

## Structure

```
daemon/    # TypeScript, Node.js — WebSocket server + stream-json bridge
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
token: <your-secure-token>    # auto-generated on first run, copy to iOS app
allowedDirs:                   # directories Claude Code is allowed to work in
  - ~/projects
  - ~/work
claudePath: claude             # path to claude CLI (default: "claude")
```

> **Security:** Config file is created with `0600` permissions. The token is shown once on first run — copy it to your iOS app. You can rotate it by editing the config.

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
npm test       # 18 tests using Node.js built-in test runner
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
- Bundle identifier: `com.ghostcomplex.VibeAnywhere` (or change to yours)

### 3. Build & run

- Select an iOS 17+ simulator or device
- ⌘R to build and run

### 4. Connect to daemon

In the app:
1. Tap the ⚙️ gear icon (top right)
2. Enter your daemon's **host** (IP or Tailscale hostname)
3. Enter **port** (default: `7842`)
4. Enter the **bearer token** from your config
5. Tap **Connect**

### 5. Test

```bash
cd app

# Build only (no signing required)
xcodebuild build \
  -project VibeAnywhere.xcodeproj \
  -scheme VibeAnywhere \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild test \
  -project VibeAnywhere.xcodeproj \
  -scheme VibeAnywhere \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

---

## Quick Start (TL;DR)

```bash
# Terminal 1 — start daemon
cd daemon && npm install && npm run dev

# Note the token printed on first run, then:
# Terminal 2 — open iOS app
open app/VibeAnywhere.xcodeproj
# Build & run on simulator, enter host/port/token in Settings
```

---

## Architecture

### Daemon

| Module | Role |
|--------|------|
| `config.ts` | YAML config loader, token management, path validation |
| `server.ts` | WebSocket server with bearer token auth, ping/pong keepalive |
| `acp.ts` | Spawns `claude` CLI with `--print --output-format stream-json`, manages stdio |
| `sessions.ts` | Session lifecycle: create, list, resume, destroy with 5-min reconnect window |
| `index.ts` | Entry point, wires everything together |

### iOS App

| Module | Role |
|--------|------|
| `WebSocketService` | URLSessionWebSocketTask with auto-reconnect (exponential backoff) |
| `KeychainService` | Secure token storage in iOS Keychain |
| `SessionViewModel` | Session CRUD, forwards stream events to active chat |
| `ChatViewModel` | Message list with streaming text append, tool_use tracking |
| `ChatView` | Chat UI with auto-scroll, send button, streaming cursor |
| `SessionListView` | Active sessions list with swipe-to-delete |
| `SettingsView` | Server config form with connection status indicator |

### Protocol (WebSocket JSON messages)

**Client → Daemon:**
```json
{"type": "session/create", "cwd": "/path/to/project"}
{"type": "session/list"}
{"type": "session/resume", "sessionId": "uuid"}
{"type": "session/message", "sessionId": "uuid", "content": "hello"}
{"type": "session/destroy", "sessionId": "uuid"}
```

**Daemon → Client:**
```json
{"type": "session/created", "sessionId": "uuid", "cwd": "/path"}
{"type": "session/list", "sessions": [{"sessionId": "...", "cwd": "..."}]}
{"type": "stream/text", "sessionId": "uuid", "content": "partial text"}
{"type": "stream/tool_use", "sessionId": "uuid", "tool": "Read", "input": {...}}
{"type": "stream/end", "sessionId": "uuid", "result": "done"}
{"type": "error", "message": "description"}
```

---

## Network Setup

The daemon binds to `0.0.0.0:7842` by default. For remote access:

**Option A: Tailscale (recommended)**
1. Install Tailscale on both your Mac and iPhone
2. Use the Tailscale IP/hostname as the host in the iOS app
3. Traffic is encrypted end-to-end, no port forwarding needed

**Option B: Local network**
- Use your Mac's local IP (e.g., `192.168.1.x`)
- Both devices must be on the same WiFi

> ⚠️ **Do not expose the daemon to the public internet** without additional security measures.

---

## CI

GitHub Actions runs on every push to `main` and PRs:
- **Daemon job:** Node 20 — type check, build, test
- **iOS job:** macOS — Xcode build and test on iOS Simulator

---

## v0.2 Roadmap (Backlog)

- Agent prompt layer (soul.md / agent.md / memory.md)
- File watcher & hot reload
- Skills loader (OpenClaw-compatible)
- Agent mode toggle in iOS app

## License

MIT
