# PRD: v0.2 — ACP Runtime Migration

**Status:** Draft
**Author:** Major
**Date:** 2026-04-12
**Depends on:** v0.1.0 (MVP)

## Overview

Replace the current `claude --print --output-format stream-json` bridge with [acpx](https://github.com/anthropics/acpx) — a headless ACP (Agent Client Protocol) client. This unlocks session resume, mid-turn cancel, permission approval from the phone, multi-agent support, and structured tool call streaming.

## Goals

1. **ACP protocol** — Full bidirectional JSON-RPC via `@agentclientprotocol/sdk` instead of one-way stream-json parsing
2. **Session resume** — Reconnect to an existing session without losing context (`loadSession`)
3. **Cancel** — Stop a running turn from the phone (`cancel`)
4. **Permission approval** — Surface `requestPermission` callbacks to iOS; user approves/denies file writes and shell commands
5. **Multi-agent** — Support any acpx-compatible agent: Claude, Codex, Gemini, Copilot, Cursor, etc.
6. **Structured events** — Replace hand-parsed `content_block_delta` with ACP `sessionUpdate` notifications (text, tool_call, tool_call_update, usage)
7. **Runtime controls** — Set mode (plan/code), switch model, configure options mid-session

## Non-Goals (v0.2)

- ~~Agent/buddy orchestrator layer~~ — **removed from roadmap entirely**. vibe-anywhere is a lightweight mobile client for Claude Code, not a standalone agent framework.
- ~~Soul/agent/memory prompt assembly~~ — **removed** (old #12, closed)
- ~~Skills system~~ — **removed** (old #15, closed)
- Network relay / Tailscale integration
- Multi-user / auth per user
- Web client

## Architecture

### Current (v0.1)

```
[iOS] → WebSocket → [Daemon] → spawn claude --print --stream-json → stdout parsing
```

### Target (v0.2)

```
[iOS] → WebSocket → [Daemon] → spawn acpx <agent> → ACP JSON-RPC over stdio
                                    ↕
                              @agentclientprotocol/sdk
                              (initialize, newSession, prompt, cancel,
                               loadSession, setSessionMode, setSessionModel,
                               sessionUpdate notifications, requestPermission callbacks)
```

### Data Flow

1. iOS sends `session/create { cwd, agent }` via WebSocket
2. Daemon spawns `acpx <agent>` if not already running for this agent
3. Daemon calls `initialize()` → `newSession({ cwd })` via ACP
4. iOS sends `session/message { sessionId, content }` via WebSocket
5. Daemon calls `prompt(sessionId, content)` via ACP
6. ACP streams `sessionUpdate` notifications → daemon relays to iOS as WebSocket events
7. If ACP sends `requestPermission` → daemon relays to iOS → user approves/denies → daemon responds
8. iOS sends `session/cancel { sessionId }` → daemon calls `cancel(sessionId)`

### Key Differences from v0.1

| Area | v0.1 (stream-json) | v0.2 (ACP) |
|------|---------------------|------------|
| Process per session | 1 claude process | 1 acpx process (manages sessions internally) |
| Protocol | Custom stream-json lines | Standard ACP JSON-RPC |
| Session lifecycle | Process = session | `newSession` / `loadSession` / `closeSession` |
| Tool events | Parse `content_block_start/delta/stop` | `tool_call` + `tool_call_update` notifications |
| Permissions | `bypassPermissions` | `requestPermission` callback |
| Cancel | Kill process | `cancel(sessionId)` (cooperative) |
| Multi-agent | Claude only | Any acpx agent |

## Daemon Changes

### New: `AcpManager` (replaces `AcpBridge`)

Single acpx process manager per agent type. Manages multiple sessions on one process.

```typescript
interface AcpManager {
  // Lifecycle
  ensureAgent(agent: string): Promise<void>        // spawn acpx <agent> if needed
  createSession(agent: string, cwd: string): Promise<{ sessionId: string }>
  loadSession(agent: string, sessionId: string): Promise<void>
  closeSession(agent: string, sessionId: string): Promise<void>

  // Interaction
  prompt(agent: string, sessionId: string, content: string): Promise<void>
  cancel(agent: string, sessionId: string): Promise<void>

  // Controls
  setMode(agent: string, sessionId: string, mode: string): Promise<void>
  setModel(agent: string, sessionId: string, model: string): Promise<void>

  // Events (emitted to WebSocket relay)
  on('text', (sessionId, text) => void)
  on('tool_call', (sessionId, toolCall) => void)
  on('tool_call_update', (sessionId, update) => void)
  on('permission_request', (sessionId, request) => void)
  on('usage', (sessionId, usage) => void)
  on('turn_end', (sessionId, result) => void)
  on('error', (sessionId, error) => void)
}
```

### New WebSocket Messages

Client → Daemon:
- `session/create { cwd, agent? }` — agent defaults to "claude"
- `session/resume { sessionId }` — reload existing session
- `session/message { sessionId, content }`
- `session/cancel { sessionId }`
- `session/set-mode { sessionId, mode }` — "plan", "code", etc.
- `session/set-model { sessionId, model }`
- `permission/respond { sessionId, requestId, outcome }` — "approved" / "denied"

Daemon → Client:
- `event/text { sessionId, content }`
- `event/tool_call { sessionId, toolCallId, tool, status, input?, content? }`
- `event/tool_call_update { sessionId, toolCallId, status?, content? }`
- `event/permission_request { sessionId, requestId, tool, description, permissions }`
- `event/usage { sessionId, inputTokens, outputTokens }`
- `event/turn_end { sessionId, stopReason }`
- `event/error { sessionId, message }`
- `event/session_info { sessionId, models?, modes? }`

### Config Changes

```yaml
# ~/.vibe-anywhere/config.yaml
port: 7842
bind: 0.0.0.0
token: <token>
allowedDirs:
  - ~/projects
defaultAgent: claude       # NEW: default acpx agent
acpx:
  path: acpx               # NEW: path to acpx binary (or auto-detect)
  permissionMode: prompt    # NEW: "prompt" (ask iOS) | "approve-all" | "deny-all"
  timeout: 120              # NEW: max seconds per turn
```

### Dependencies

- `@agentclientprotocol/sdk` — ACP types and client connection
- `acpx` — runtime binary (auto-detected from PATH or configured)

## iOS Changes

### Session Creation

- Add agent picker to "New Session" sheet (Claude, Codex, Gemini, etc.)
- Default to configured `defaultAgent`
- Show available agents from daemon (future: daemon reports installed agents)

### Cancel Button

- Add stop/cancel button in chat toolbar during active turn
- Sends `session/cancel` to daemon
- Visual feedback: spinner → cancelled state

### Permission Approval

- When daemon sends `event/permission_request`:
  - Show modal/banner with tool name, description, affected files
  - User taps Approve or Deny
  - App sends `permission/respond` back
  - Timeout: auto-deny after 60s with warning

### Session Resume

- Session list shows previous sessions (persisted by daemon)
- Tap to resume → sends `session/resume` → daemon calls `loadSession`
- Chat history replayed from ACP session state

### Token Usage

- Show input/output token count per turn (from `event/usage`)
- Optional: running session total

### Mode & Model Controls

- Settings gear in chat view → pick mode (plan/code) and model
- Sends `session/set-mode` / `session/set-model`

## WebSocket Protocol (v2)

Add protocol version negotiation. Client sends version on connect:

```
GET /ws HTTP/1.1
Authorization: Bearer <token>
X-Protocol-Version: 2
```

Daemon accepts v1 (stream-json) and v2 (ACP) connections. v1 gets the old behavior for backward compat during transition.

## Migration Strategy

1. Implement `AcpManager` alongside existing `AcpBridge`
2. New WebSocket message types for v2 protocol
3. iOS app detects protocol version from daemon
4. Once stable, remove v1 code path

## Milestones

### M1: Daemon ACP Core
- [ ] `AcpManager` with `acpx` process management
- [ ] `createSession` / `prompt` / `cancel` via ACP
- [ ] `sessionUpdate` → WebSocket event relay
- [ ] Config: `defaultAgent`, `acpx.path`
- [ ] Tests: unit + E2E smoke

### M2: iOS ACP Basics
- [ ] New WebSocket message types (v2)
- [ ] Agent picker in session creation
- [ ] Cancel button during active turn
- [ ] Session info display (model, mode, usage)

### M3: Permission Workflow
- [ ] Daemon: `requestPermission` callback relay
- [ ] iOS: permission approval modal
- [ ] Config: `acpx.permissionMode`
- [ ] Timeout + auto-deny logic

### M4: Session Resume + Controls
- [ ] Daemon: `loadSession` support
- [ ] iOS: session resume from list
- [ ] iOS: mode/model picker in chat settings
- [ ] Daemon: `setSessionMode` / `setSessionModel` relay

### M5: Cleanup + Polish
- [ ] Remove v1 stream-json code path
- [ ] Update README and docs
- [ ] Close old v0.2 issues (#12, #13, #15, #17) as deferred/wontfix
- [ ] Tag v0.2.0

## Estimated Effort

| Component | LOC (estimate) |
|-----------|----------------|
| Daemon AcpManager | ~400 |
| Daemon WebSocket v2 protocol | ~150 |
| Daemon config + tests | ~200 |
| iOS WebSocket v2 messages | ~100 |
| iOS cancel + agent picker | ~150 |
| iOS permission modal | ~200 |
| iOS session resume | ~150 |
| iOS mode/model controls | ~100 |
| Tests (daemon + iOS) | ~300 |
| **Total** | **~1750** |

## Open Questions

1. **Single acpx process vs per-session?** — acpx manages sessions internally, so one process per agent type should work. Need to verify session isolation.
2. **acpx binary distribution** — Ship with daemon? Auto-detect from PATH? Require manual install?
3. **Backward compat** — Keep v1 protocol forever or sunset after v0.2 stabilizes?
4. **Permission timeout** — 60s enough? Configurable?
