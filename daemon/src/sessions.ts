import path from 'node:path';
import { WebSocket } from 'ws';
import type { AgentStreamEvent } from './providers/types.js';
import { type ProviderRegistry } from './providers/registry.js';
import { send, sendError } from './server.js';
import { type Config, expandTilde } from './config.js';
import type { ClientMessage } from './types.js';

export interface SessionInfo {
  sessionId: string;
  cwd: string;
  agent: string;
  title: string | null;
  createdAt: number;
  lastMessageAt: number;
}

interface Session {
  info: SessionInfo;
  client: WebSocket | null;
  /** Timer for reconnect window — destroys session if no client reconnects */
  reconnectTimer: ReturnType<typeof setTimeout> | null;
}

export class SessionManager {
  private sessions = new Map<string, Session>();
  private readonly config: Config;
  private readonly reconnectWindowMs: number;
  private readonly registry: ProviderRegistry;

  constructor(config: Config, registry: ProviderRegistry, reconnectWindowSeconds = 300) {
    this.config = config;
    this.reconnectWindowMs = reconnectWindowSeconds * 1000;
    this.registry = registry;

    // Wire event listeners for all currently registered providers
    for (const [, client] of registry.all()) {
      client.on('event', (event: AgentStreamEvent) => {
        this.relayEvent(event);
      });
    }

    // Auto-wire event listeners for providers registered later
    registry.onRegister((_name, client) => {
      client.on('event', (event: AgentStreamEvent) => {
        this.relayEvent(event);
      });
    });
  }

  handleMessage(ws: WebSocket, msg: ClientMessage): void {
    switch (msg.type) {
      case 'session/create':
        void this.createSession(ws, msg.cwd, msg.agent ?? this.config.defaultAgent);
        break;
      case 'session/list':
        this.listSessions(ws);
        break;
      case 'session/resume':
        void this.resumeSession(ws, msg.sessionId);
        break;
      case 'session/message': {
        const trimmed = msg.content.trim();
        if (!trimmed) {
          sendError(ws, 'Message content cannot be empty');
          break;
        }
        void this.sendMessage(ws, msg.sessionId, trimmed);
        break;
      }
      case 'session/destroy':
        this.destroySession(ws, msg.sessionId);
        break;
      case 'session/cancel':
        void this.cancelSession(ws, msg.sessionId);
        break;
      case 'session/set-mode':
        void this.setMode(ws, msg.sessionId, msg.mode);
        break;
      case 'session/set-model':
        void this.setModel(ws, msg.sessionId, msg.model);
        break;
      case 'permission/respond':
        this.respondPermission(ws, msg.requestId, msg.optionId);
        break;
      case 'host-session/list':
        void this.listHostSessions(ws, msg.agent ?? this.config.defaultAgent);
        break;
      case 'host-session/resume':
        void this.resumeHostSession(ws, msg.sessionId, msg.cwd, msg.agent ?? this.config.defaultAgent);
        break;
    }
  }

  /** Called when a WebSocket client disconnects */
  handleDisconnect(ws: WebSocket): void {
    for (const session of this.sessions.values()) {
      if (session.client === ws) {
        session.client = null;
        console.log(`[session] Client detached from ${session.info.sessionId}`);
        session.reconnectTimer = setTimeout(() => {
          console.log(`[session] Reconnect window expired for ${session.info.sessionId}`);
          this.destroySessionById(session.info.sessionId);
        }, this.reconnectWindowMs);
      }
    }
  }

  /** Destroy all sessions (for graceful shutdown) */
  destroyAll(): void {
    for (const sessionId of [...this.sessions.keys()]) {
      this.destroySessionById(sessionId);
    }
    void this.registry.shutdownAll();
  }

  // ── Session operations ──

  private async createSession(ws: WebSocket, cwd: string, agent: string): Promise<void> {
    const resolved = this.resolveCwd(cwd);
    if (!resolved) {
      sendError(ws, `Directory not allowed: ${cwd}`);
      return;
    }

    try {
      const result = await this.registry.getOrThrow(agent).createSession(agent, resolved);

      const session: Session = {
        info: {
          sessionId: result.sessionId,
          cwd: resolved,
          agent,
          title: null,
          createdAt: Date.now(),
          lastMessageAt: Date.now(),
        },
        client: ws,
        reconnectTimer: null,
      };

      this.sessions.set(result.sessionId, session);
      console.log(`[session] Created ${result.sessionId} (agent: ${agent}) in ${resolved}`);
      send(ws, { type: 'session/created', sessionId: result.sessionId, cwd: resolved });
    } catch (err) {
      sendError(ws, `Failed to create session: ${(err as Error).message}`);
    }
  }

  private async sendMessage(ws: WebSocket, sessionId: string, content: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }

    session.info.lastMessageAt = Date.now();

    try {
      await this.registry.getOrThrow(session.info.agent).prompt(session.info.agent, sessionId, content);
    } catch (err) {
      sendError(ws, `Failed to send message: ${(err as Error).message}`);
    }
  }

  private async cancelSession(ws: WebSocket, sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }
    await this.registry.getOrThrow(session.info.agent).cancel(session.info.agent, sessionId);
  }

  private async setMode(ws: WebSocket, sessionId: string, mode: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }

    try {
      await this.registry.getOrThrow(session.info.agent).setMode(session.info.agent, sessionId, mode);
    } catch (err) {
      sendError(ws, `Failed to set mode: ${(err as Error).message}`);
    }
  }

  private async setModel(ws: WebSocket, sessionId: string, model: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }

    try {
      await this.registry.getOrThrow(session.info.agent).setModel(session.info.agent, sessionId, model);
    } catch (err) {
      sendError(ws, `Failed to set model: ${(err as Error).message}`);
    }
  }

  private respondPermission(_ws: WebSocket, requestId: string, optionId: string): void {
    // Try all providers — we don't know which one holds this permission request
    for (const [, client] of this.registry.all()) {
      if (client.respondPermission(requestId, optionId)) return;
    }
    sendError(_ws, `Permission request not found or expired: ${requestId}`);
  }

  private listSessions(ws: WebSocket): void {
    const sessions = [...this.sessions.values()].map((s) => ({
      sessionId: s.info.sessionId,
      cwd: s.info.cwd,
      agent: s.info.agent,
      title: s.info.title,
    }));
    send(ws, { type: 'session/list', sessions });
  }

  private async resumeSession(ws: WebSocket, sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }

    if (session.reconnectTimer) {
      clearTimeout(session.reconnectTimer);
      session.reconnectTimer = null;
    }

    // Only replay history when the session had no active client (app reconnecting)
    const needsReplay = session.client === null || session.client.readyState !== WebSocket.OPEN;
    session.client = ws;

    if (needsReplay) {
      try {
        await this.registry.getOrThrow(session.info.agent).resumeHostSession(session.info.agent, sessionId, session.info.cwd);
      } catch (err) {
        console.warn(`[session] Replay failed for ${sessionId}: ${(err as Error).message}`);
        send(ws, { type: 'event/replay_end', sessionId });
      }
    } else {
      // No replay needed — still send replay_end so the client clears loading state
      send(ws, { type: 'event/replay_end', sessionId });
    }

    console.log(`[session] Resumed ${sessionId} (replay: ${needsReplay})`);
    send(ws, { type: 'session/created', sessionId, cwd: session.info.cwd });
  }

  private destroySession(ws: WebSocket, sessionId: string): void {
    if (!this.sessions.has(sessionId)) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }
    this.destroySessionById(sessionId);
    send(ws, { type: 'session/destroyed', sessionId });
  }

  private destroySessionById(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    if (session.reconnectTimer) {
      clearTimeout(session.reconnectTimer);
    }

    void this.registry.getOrThrow(session.info.agent).closeSession(session.info.agent, sessionId);
    this.sessions.delete(sessionId);
    console.log(`[session] Destroyed ${sessionId}`);
  }

  private async listHostSessions(ws: WebSocket, agent: string): Promise<void> {
    try {
      const result = await this.registry.getOrThrow(agent).listHostSessions(agent);

      // Filter out sessions already tracked by the daemon
      const activeIds = new Set(this.sessions.keys());
      const filtered = result.sessions.filter((s) => !activeIds.has(s.sessionId));

      send(ws, { type: 'host-session/list', sessions: filtered, supported: result.supported });
    } catch (err) {
      sendError(ws, `Failed to list host sessions: ${(err as Error).message}`);
    }
  }

  private async resumeHostSession(ws: WebSocket, sessionId: string, cwd: string, agent: string): Promise<void> {
    // If already tracked, resume with replay
    if (this.sessions.has(sessionId)) {
      await this.resumeSession(ws, sessionId);
      return;
    }

    const resolved = this.resolveCwd(cwd);
    if (!resolved) {
      sendError(ws, `Directory not allowed: ${cwd}`);
      return;
    }

    // Register session BEFORE loadSession so replay events can be relayed
    const session: Session = {
      info: {
        sessionId,
        cwd: resolved,
        agent,
        title: null,
        createdAt: Date.now(),
        lastMessageAt: Date.now(),
      },
      client: ws,
      reconnectTimer: null,
    };
    this.sessions.set(sessionId, session);

    try {
      await this.registry.getOrThrow(agent).resumeHostSession(agent, sessionId, resolved);

      console.log(`[session] Resumed host session ${sessionId} (agent: ${agent}) in ${resolved}`);
      send(ws, { type: 'session/created', sessionId, cwd: resolved });
    } catch (err) {
      // Roll back on failure
      this.sessions.delete(sessionId);
      sendError(ws, `Failed to resume host session: ${(err as Error).message}`);
    }
  }

  // ── Event relay ──

  private relayEvent(event: AgentStreamEvent): void {
    if (event.type === 'agent_exit') {
      console.log(`[session] Agent "${event.agent}" exited (code: ${event.code})`);
      return;
    }

    if (!event.sessionId) return;

    const session = this.sessions.get(event.sessionId);
    if (!session?.client || session.client.readyState !== WebSocket.OPEN) {
      return;
    }

    const ws = session.client;
    const sessionId = event.sessionId;

    switch (event.type) {
      case 'text':
        send(ws, { type: 'event/text', sessionId, content: event.content, ...(event.replay && { replay: true }) });
        break;
      case 'user_text':
        // Capture first user message as session title (including during replay)
        if (!session.info.title) {
          session.info.title = event.content.slice(0, 100);
        }
        send(ws, { type: 'event/user_text', sessionId, content: event.content, ...(event.replay && { replay: true }) });
        break;
      case 'tool_call':
        send(ws, {
          type: 'event/tool_call',
          sessionId,
          toolCallId: event.toolCallId,
          tool: event.title,
          status: event.status,
          ...(event.replay && { replay: true }),
        });
        break;
      case 'tool_call_update':
        send(ws, {
          type: 'event/tool_call_update',
          sessionId,
          toolCallId: event.toolCallId,
          status: event.status,
          ...(event.replay && { replay: true }),
        });
        break;
      case 'replay_end':
        send(ws, { type: 'event/replay_end', sessionId });
        break;
      case 'permission_request':
        send(ws, {
          type: 'event/permission_request',
          sessionId,
          requestId: event.requestId,
          tool: event.toolTitle,
          options: event.options,
        });
        break;
      case 'usage':
        send(ws, {
          type: 'event/usage',
          sessionId,
          inputTokens: event.inputTokens,
          outputTokens: event.outputTokens,
        });
        break;
      case 'turn_end':
        send(ws, {
          type: 'event/turn_end',
          sessionId,
          stopReason: event.stopReason,
        });
        break;
      case 'error':
        send(ws, {
          type: 'event/error',
          sessionId,
          message: event.message,
        });
        break;
    }
  }

  // ── Helpers ──

  private resolveCwd(cwd: string): string | null {
    const resolved = path.resolve(expandTilde(cwd));
    if (!this.isAllowedDir(resolved)) return null;
    return resolved;
  }

  private isAllowedDir(resolved: string): boolean {
    return this.config.allowedDirs.some(
      (allowed) => resolved === allowed || resolved.startsWith(allowed + path.sep),
    );
  }
}
