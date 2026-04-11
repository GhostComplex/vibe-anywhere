# PRD: Vibe Anywhere — MVP

**Status:** Draft  
**Author:** Major  
**Date:** 2026-04-12

## Overview

Vibe Anywhere is a lightweight system for controlling Claude Code from a mobile device. It consists of a TypeScript daemon running on the development machine and an iOS app for remote interaction.

The daemon bridges WebSocket connections from the iOS client to Claude Code via the ACP (Agent Communication Protocol) over stdio, enabling real-time streaming of conversations, tool use, and approvals.

## Goals

1. **Remote Claude Code access** — Start, interact with, and monitor Claude Code sessions from an iPhone
2. **Directory selection** — Choose which project directory Claude Code operates in
3. **Streaming output** — Real-time token-by-token output and tool use visibility
4. **Session persistence** — Resume conversations across app launches
5. **Security** — Only the device owner can connect; no public exposure
6. **Minimal codebase** — Target ~1500 LOC total (daemon + app), zero unnecessary dependencies

## Non-Goals (MVP)

- Agent layer (soul/agent/memory prompt architecture) — reserved for v0.2
- Skill system — reserved for v0.2
- Multi-user support
- Web client
- Approval workflows for dangerous operations (Claude Code handles this internally)

## Architecture

```
┌─────────────┐         WebSocket          ┌─────────────────┐       ACP/stdio       ┌──────────────┐
│             │  ◄──────────────────────►   │                 │  ◄──────────────────►  │              │
│   iOS App   │    (over Tailscale)         │  TS Daemon      │                        │ claude --acp │
│  (SwiftUI)  │                             │  (Node.js)      │                        │              │
│             │                             │                 │                        │              │
└─────────────┘                             └─────────────────┘                        └──────────────┘
```

### Data Flow

1. User sends a message from iOS app via WebSocket
2. Daemon receives message, forwards to Claude Code via ACP (`session/message`)
3. Claude Code streams response events via stdout
4. Daemon forwards stream events to iOS app via WebSocket
5. iOS app renders tokens, tool use, and results in real-time

### Network Model

- Daemon listens on a configurable port, bound to the Tailscale interface (`100.x.x.x`) or `0.0.0.0` for local dev
- iOS app connects via Tailscale IP
- All traffic encrypted by WireGuard (Tailscale) at the network layer
- Application-layer auth via pre-shared bearer token stored in Keychain (both sides)

## Components

### 1. TypeScript Daemon (`daemon/`)

**Runtime:** Node.js (LTS)  
**Estimated LOC:** 800-1000

#### Responsibilities

- WebSocket server (using `ws` library)
- ACP bridge: spawn `claude --acp`, manage stdin/stdout JSON-RPC communication
- Session management: create, list, resume, and destroy sessions
- Authentication: validate bearer token on WebSocket upgrade
- Configuration: YAML config file for port, allowed directories, token

#### ACP Bridge

The daemon communicates with Claude Code using the ACP protocol:

- **Spawn:** `claude --acp` as a child process
- **Send:** JSON-RPC messages via stdin (e.g., `session/start`, `session/message`)
- **Receive:** JSON-RPC responses and notifications via stdout (streamed line by line)
- **Lifecycle:** One `claude --acp` process per active session

#### WebSocket Protocol

All messages are JSON with a `type` field:

```jsonc
// Client → Daemon
{"type": "session/create", "cwd": "/path/to/project"}
{"type": "session/list"}
{"type": "session/resume", "sessionId": "..."}
{"type": "session/message", "sessionId": "...", "content": "fix the login bug"}
{"type": "session/destroy", "sessionId": "..."}

// Daemon → Client
{"type": "session/created", "sessionId": "...", "cwd": "..."}
{"type": "session/list", "sessions": [...]}
{"type": "stream/text", "sessionId": "...", "content": "I'll look at..."}
{"type": "stream/tool_use", "sessionId": "...", "tool": "file_read", "input": {...}}
{"type": "stream/tool_result", "sessionId": "...", "tool": "file_read", "output": "..."}
{"type": "stream/end", "sessionId": "...", "result": "completed"}
{"type": "error", "message": "..."}
```

#### Configuration

```yaml
# ~/.vibe-anywhere/config.yaml
port: 7842
bind: "0.0.0.0"           # or specific Tailscale IP
token: "generated-on-first-run"
allowedDirs:
  - "~/projects"
  - "~/work"
claudePath: "claude"       # path to claude binary
```

#### File Structure

```
daemon/
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts           # Entry point, CLI args
│   ├── server.ts          # WebSocket server + auth
│   ├── acp.ts             # ACP bridge (spawn + stdio JSON-RPC)
│   ├── sessions.ts        # Session lifecycle management
│   ├── config.ts          # YAML config loader
│   └── types.ts           # Shared type definitions
└── README.md
```

### 2. iOS App (`app/`)

**Framework:** SwiftUI  
**Target:** iOS 17+  
**Estimated LOC:** 600-800

#### Responsibilities

- WebSocket client connecting to daemon
- Chat UI: message bubbles, streaming text, tool use display
- Session management: create new (with directory picker), resume existing, destroy
- Connection management: auto-reconnect, connection status indicator
- Settings: daemon address, token, directory favorites
- Keychain storage for token

#### Screens

1. **Connection Setup** — Enter daemon Tailscale IP + port, paste/scan token. One-time setup, stored in Keychain.
2. **Session List** — Active and recent sessions, each showing project directory and last message preview. "New Session" button.
3. **New Session** — Pick a directory from allowed list (fetched from daemon). Start.
4. **Chat** — Message input, streaming response display, tool use cards (collapsible), session info header.

#### File Structure

```
app/
├── VibeAnywhere.xcodeproj
├── VibeAnywhere/
│   ├── App.swift
│   ├── Models/
│   │   ├── Session.swift
│   │   └── Message.swift
│   ├── Services/
│   │   ├── WebSocketService.swift
│   │   └── KeychainService.swift
│   ├── Views/
│   │   ├── ConnectionSetupView.swift
│   │   ├── SessionListView.swift
│   │   ├── NewSessionView.swift
│   │   ├── ChatView.swift
│   │   └── Components/
│   │       ├── MessageBubble.swift
│   │       ├── ToolUseCard.swift
│   │       └── StreamingText.swift
│   └── Info.plist
```

### 3. Shared Protocol

The WebSocket message protocol is defined in both TypeScript (daemon types) and Swift (app models). No shared package needed — the protocol is simple enough to maintain separately with type definitions on each side.

## Security Model

### Threat Model

- **Network:** Tailscale provides WireGuard encryption and device-level authentication. Only devices in the user's Tailscale network can reach the daemon.
- **Application:** Bearer token validates that the connecting client is authorized. Token generated on first daemon run, displayed once for the user to copy to iOS app.
- **Directory sandbox:** Daemon only allows Claude Code to operate in configured `allowedDirs`. Requests for other directories are rejected.
- **No cloud relay:** All communication is direct device-to-device. No data passes through any third-party server.

### Token Lifecycle

1. First `vibe-anywhere` run generates a random 256-bit token
2. Token displayed in terminal for user to copy
3. User enters token in iOS app (one time)
4. Both sides store in their respective secure storage (file permission on daemon, Keychain on iOS)
5. Token sent as `Authorization: Bearer <token>` on WebSocket upgrade
6. Token can be rotated via `vibe-anywhere --rotate-token`

## v0.2 Roadmap (Agent Layer)

> Not in MVP scope. Documented here for architectural awareness.

v0.2 adds a thin agent layer between the user and Claude Code:

```
~/.vibe-anywhere/
├── config.yaml
├── soul.md          # Identity and red lines (user-only edit)
├── agent.md         # Behavior instructions (AI can edit when instructed)
├── memory.md        # Long-term memory (AI reads/writes freely)
└── skills/
    └── <skill-name>/
        └── SKILL.md
```

- **soul.md** — Read-only for AI. Defines identity, constraints, tone.
- **agent.md** — AI can edit when user instructs it to. Self-iterating prompt.
- **memory.md** — AI reads/writes across sessions. Persistent context.
- **Hot reload** — Daemon watches these files via `FSEvents` (macOS) / `fs.watch` (Node). Changes take effect on the next message without restart.
- **Skill loading** — Skills loaded on demand, same format as OpenClaw skills.
- **Prompt injection** — `buildSystemPrompt()` concatenates soul + agent + memory + active skills → prepended to ACP session start.

The daemon code in v0.1 should include a `buildSystemPrompt()` stub that returns empty string, making v0.2 a drop-in enhancement.

## Success Criteria

- [ ] Can start a Claude Code session from iPhone in a chosen directory
- [ ] Streaming output visible in real-time on iPhone
- [ ] Tool use (file reads, shell commands) visible as collapsible cards
- [ ] Session survives app backgrounding and reconnects automatically
- [ ] Unauthorized connections are rejected
- [ ] Total codebase under 2000 LOC
