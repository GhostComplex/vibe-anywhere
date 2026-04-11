# Vibe Anywhere — Product Requirements Document

> Remote Claude Code client: control Claude from your phone, anywhere.

## Overview

Vibe Anywhere is a lightweight system that lets you interact with Claude Code from an iOS device over the network. A TypeScript daemon on your Mac bridges WebSocket connections to Claude Code's ACP (Agent Communication Protocol) over stdio, streaming tokens and tool-use events back to the mobile app in real time.

## Architecture

```
┌─────────────┐         WebSocket          ┌──────────────────┐        ACP/stdio        ┌──────────────┐
│  iOS App    │ ◄─────────────────────────► │  Daemon (TS)     │ ◄─────────────────────► │ claude --acp │
│  SwiftUI    │       (JSON messages)       │  Node.js         │     (JSON-RPC)          │              │
└─────────────┘                             └──────────────────┘                          └──────────────┘
                                                     │
                                              Tailscale / LAN
```

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Daemon language | TypeScript / Node.js | Cross-platform (macOS/Linux/VPS), JSON-native, mature WebSocket ecosystem (`ws`), Steins is a fullstack TS dev |
| iOS app | Swift / SwiftUI | Only option for native iOS; shares protocol models via Swift Package |
| Protocol to Claude | ACP (JSON-RPC over stdio) | Streaming, multi-turn sessions, tool-use visibility; `claude --acp` |
| Network transport | WebSocket over Tailscale | Encrypted tunnel, zero-config NAT traversal, mTLS-grade security |
| Auth | Bearer token | Simple, validated per-connection; token stored in config |

## Milestones

### v0.1 — MVP (Direct Mode)

Minimal viable path: type on phone → see Claude's streaming response.

#### Daemon (TypeScript)

1. **WebSocket server** — Accept connections on configurable port, authenticate via bearer token in the upgrade request.
2. **ACP bridge** — Spawn `claude --acp` as child process. Translate incoming WebSocket messages to ACP `session/start` and `session/message` JSON-RPC calls on stdin. Read stdout for streaming responses and notifications.
3. **Session management** — Track active sessions per client. Support `create`, `resume`, and `list` operations. Persist session IDs to disk for reconnection.
4. **Directory selection** — Client specifies working directory (`cwd`) when creating a session; daemon passes it to `claude --acp` via `session/start`.
5. **Error handling** — Claude process crashes → notify client, allow restart. WebSocket drops → keep Claude session alive for reconnect window (configurable, default 5 min).

#### iOS App (SwiftUI)

1. **Connection setup** — Enter daemon URL (auto-discovered on LAN via Bonjour, or manual Tailscale IP). Store token in Keychain.
2. **Chat UI** — Message list with streaming text, code blocks, and tool-use indicators (file read, command exec, etc). Markdown rendering.
3. **Directory picker** — Show available directories from daemon (daemon exposes a configurable allowlist). Select cwd for new sessions.
4. **Session list** — View active / recent sessions, resume or create new.
5. **Reconnection** — Auto-reconnect on network change; buffer pending messages.

#### Shared (Swift Package)

- WebSocket message models (request/response enums, Codable)
- Protocol version negotiation

#### Config

```yaml
# ~/.vibe-anywhere/config.yaml
port: 7777
token: "your-secret-token"
directories:
  - ~/Projects
  - ~/Documents/notes
reconnect_window_seconds: 300
```

#### Non-Goals for v0.1

- No agent layer / prompt injection
- No TLS termination (Tailscale handles encryption)
- No multi-user support
- No file browsing in iOS app (Claude handles file ops)

---

### v0.2 — Tiny Agent Layer

Add an optional prompt middleware that wraps user messages before forwarding to Claude. All "intelligence" lives in editable markdown files — code stays pure plumbing.

#### Prompt Architecture (3-layer)

```
~/.vibe-anywhere/
├── config.yaml
├── soul.md              # Identity & red lines — user-editable only, AI read-only
├── agent.md             # Behavior instructions — user tells AI to edit this
├── memory.md            # Persistent memory — AI reads/writes across sessions
├── skills/
│   ├── code-review/
│   │   └── SKILL.md
│   └── ...
└── sessions/
```

| File | Who reads | Who writes | Purpose |
|------|-----------|------------|---------|
| `soul.md` | AI + user | User only | Core identity, personality, boundaries |
| `agent.md` | AI + user | User instructs AI to edit | Behavioral prompt, self-iterable |
| `memory.md` | AI + user | AI (on user's instruction) | Long-term context across sessions |
| `skills/*.md` | AI | User | Task-specific instructions, loaded on demand |

#### How It Works

1. **System prompt assembly** — On each `session/message`, daemon reads `soul.md` + `agent.md` + `memory.md` + relevant skill files, concatenates them as system context, prepends to user message.
2. **File write exposure** — Claude's allowed tools include file write, scoped to `agent.md` and `memory.md` only. User says "remember X" → AI writes to `memory.md`. User says "change your prompt to Y" → AI edits `agent.md`.
3. **Hot reload** — Daemon watches `~/.vibe-anywhere/` with `fs.watch()` (or `FSEvents` on macOS). File changes take effect on the next message — no restart needed.
4. **Mode toggle** — Client can switch between direct mode (no prompt injection) and agent mode per session.

#### Non-Goals for v0.2

- AI does NOT self-initiate prompt changes — only edits when user instructs
- No scheduled/cron tasks
- No multi-agent orchestration

---

### Future (v0.3+)

- **watchOS companion** — Quick reply, session status on wrist
- **macOS native client** — Desktop UI alongside iOS
- **Multi-backend** — Support other ACP-compatible agents beyond Claude
- **VPS deployment** — Run daemon on remote server, not just local Mac
- **Skill marketplace** — Share/install skill packs

## Code Estimates

| Component | v0.1 | v0.2 delta | Total |
|-----------|------|------------|-------|
| Daemon (TS) | ~800 | ~200 | ~1000 |
| iOS App (Swift) | ~700 | ~100 | ~800 |
| Shared Package | ~100 | — | ~100 |
| **Total** | **~1600** | **~300** | **~1900** |

## Protocol

### WebSocket Messages (Client → Daemon)

```typescript
// Create a new session
{ type: "session.create", cwd: "/path/to/project" }

// Send a message in a session
{ type: "session.message", sessionId: "abc123", content: "Fix the login bug" }

// Resume an existing session
{ type: "session.resume", sessionId: "abc123" }

// List sessions
{ type: "session.list" }

// List available directories
{ type: "directory.list" }
```

### WebSocket Messages (Daemon → Client)

```typescript
// Session created
{ type: "session.created", sessionId: "abc123" }

// Streaming text chunk
{ type: "stream.text", sessionId: "abc123", content: "Let me look at..." }

// Tool use event
{ type: "stream.tool_use", sessionId: "abc123", tool: "file_read", input: { path: "src/auth.ts" } }

// Tool result
{ type: "stream.tool_result", sessionId: "abc123", tool: "file_read", output: "..." }

// Message complete
{ type: "stream.done", sessionId: "abc123" }

// Error
{ type: "error", message: "Session not found", code: "SESSION_NOT_FOUND" }
```

## Security Model

1. **Network** — Tailscale provides encrypted tunnel with device-level auth. No public internet exposure.
2. **Auth** — Bearer token validated on WebSocket upgrade. Single token in config (MVP). Future: per-device tokens.
3. **Directory sandbox** — Daemon only allows `cwd` within configured directory allowlist.
4. **Agent file scope** — In v0.2, AI can only write to `agent.md` and `memory.md`. `soul.md` and `config.yaml` are read-only to AI.

## Open Questions

1. **Bonjour discovery** — Worth implementing for LAN? Or just manual IP entry + Tailscale?
2. **Session persistence format** — JSON files? SQLite? Keep it simple — JSON files.
3. **Multiple Claude instances** — One per session? Shared? Start with one shared instance, queue messages.
