import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { WebSocket } from 'ws';
import { AcpBridge, type AcpEvent } from './acp.js';
import { AcpManager, type AcpManagerEvent } from './acp-manager.js';
import { send, sendError } from './server.js';
import type { Config } from './config.js';
import type { ClientMessage } from './types.js';

export interface SessionInfo {
  sessionId: string;
  cwd: string;
  agent: string;
  createdAt: number;
  lastMessageAt: number;
  protocolVersion: number;
}

interface Session {
  info: SessionInfo;
  /** v1 only — old AcpBridge per session */
  bridge: AcpBridge | null;
  client: WebSocket | null;
  /** Timer for reconnect window — destroys session if no client reconnects */
  reconnectTimer: ReturnType<typeof setTimeout> | null;
}

export class SessionManager {
  private sessions = new Map<string, Session>();
  private readonly config: Config;
  private readonly reconnectWindowMs: number;
  private readonly acpManager: AcpManager;

  constructor(config: Config, reconnectWindowSeconds = 300) {
    this.config = config;
    this.reconnectWindowMs = reconnectWindowSeconds * 1000;

    // Create AcpManager for v2 sessions
    this.acpManager = new AcpManager({
      acpxPath: config.acpx.path,
      permissionMode: config.acpx.permissionMode,
      timeout: config.acpx.timeout,
    });

    // Relay AcpManager events to the correct WebSocket client
    this.acpManager.on('event', (event: AcpManagerEvent) => {
      this.relayAcpManagerEvent(event);
    });
  }

  handleMessage(ws: WebSocket, msg: ClientMessage, protocolVersion = 1): void {
    switch (msg.type) {
      case 'session/create':
        if (protocolVersion >= 2) {
          void this.createSessionV2(ws, msg.cwd, msg.agent ?? this.config.defaultAgent, protocolVersion);
        } else {
          this.createSessionV1(ws, msg.cwd);
        }
        break;
      case 'session/list':
        this.listSessions(ws);
        break;
      case 'session/resume':
        this.resumeSession(ws, msg.sessionId);
        break;
      case 'session/message':
        if (this.isV2Session(msg.sessionId)) {
          void this.sendMessageV2(ws, msg.sessionId, msg.content);
        } else {
          this.sendMessageV1(ws, msg.sessionId, msg.content);
        }
        break;
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
    }
  }

  /** Called when a WebSocket client disconnects */
  handleDisconnect(ws: WebSocket): void {
    for (const session of this.sessions.values()) {
      if (session.client === ws) {
        session.client = null;
        console.log(`[session] Client detached from ${session.info.sessionId}`);
        // Start reconnect timer
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
    void this.acpManager.shutdown();
  }

  // ── v1 Session (old AcpBridge path) ──

  private createSessionV1(ws: WebSocket, cwd: string): void {
    const resolved = this.resolveCwd(cwd);
    if (!resolved) {
      sendError(ws, `Directory not allowed: ${cwd}`);
      return;
    }

    const sessionId = crypto.randomUUID();
    const bridge = new AcpBridge();

    const session: Session = {
      info: {
        sessionId,
        cwd: resolved,
        agent: 'claude',
        createdAt: Date.now(),
        lastMessageAt: Date.now(),
        protocolVersion: 1,
      },
      bridge,
      client: ws,
      reconnectTimer: null,
    };

    this.sessions.set(sessionId, session);

    bridge.on('event', (event: AcpEvent) => {
      this.relayV1Event(sessionId, event);
    });

    try {
      bridge.start({ claudePath: this.config.claudePath, cwd: resolved });
    } catch (err) {
      this.sessions.delete(sessionId);
      sendError(ws, `Failed to start claude: ${(err as Error).message}`);
      return;
    }

    console.log(`[session] Created v1 ${sessionId} in ${resolved}`);
    send(ws, { type: 'session/created', sessionId, cwd: resolved });
  }

  private sendMessageV1(ws: WebSocket, sessionId: string, content: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }

    if (!session.bridge?.alive) {
      sendError(ws, `Session claude process is not running: ${sessionId}`);
      return;
    }

    session.info.lastMessageAt = Date.now();
    try {
      session.bridge.sendMessage(content);
    } catch (err) {
      sendError(ws, `Failed to send message: ${(err as Error).message}`);
    }
  }

  // ── v2 Session (AcpManager path) ──

  private async createSessionV2(ws: WebSocket, cwd: string, agent: string, protocolVersion: number): Promise<void> {
    const resolved = this.resolveCwd(cwd);
    if (!resolved) {
      sendError(ws, `Directory not allowed: ${cwd}`);
      return;
    }

    try {
      const result = await this.acpManager.createSession(agent, resolved);

      const session: Session = {
        info: {
          sessionId: result.sessionId,
          cwd: resolved,
          agent,
          createdAt: Date.now(),
          lastMessageAt: Date.now(),
          protocolVersion,
        },
        bridge: null, // v2 sessions use AcpManager
        client: ws,
        reconnectTimer: null,
      };

      this.sessions.set(result.sessionId, session);
      console.log(`[session] Created v2 ${result.sessionId} (agent: ${agent}) in ${resolved}`);
      send(ws, { type: 'session/created', sessionId: result.sessionId, cwd: resolved });
    } catch (err) {
      sendError(ws, `Failed to create session: ${(err as Error).message}`);
    }
  }

  private async sendMessageV2(ws: WebSocket, sessionId: string, content: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }

    session.info.lastMessageAt = Date.now();

    try {
      // prompt() blocks until turn_end; events arrive via AcpManager event emitter
      await this.acpManager.prompt(session.info.agent, sessionId, content);
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

    if (this.isV2Session(sessionId)) {
      await this.acpManager.cancel(session.info.agent, sessionId);
    }
    // v1 doesn't support cancel — would need to kill the process
  }

  private async setMode(ws: WebSocket, sessionId: string, mode: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }

    if (!this.isV2Session(sessionId)) {
      sendError(ws, 'set-mode requires protocol v2');
      return;
    }

    try {
      await this.acpManager.setMode(session.info.agent, sessionId, mode);
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

    if (!this.isV2Session(sessionId)) {
      sendError(ws, 'set-model requires protocol v2');
      return;
    }

    try {
      await this.acpManager.setModel(session.info.agent, sessionId, model);
    } catch (err) {
      sendError(ws, `Failed to set model: ${(err as Error).message}`);
    }
  }

  private respondPermission(ws: WebSocket, requestId: string, optionId: string): void {
    const success = this.acpManager.respondPermission(requestId, optionId);
    if (!success) {
      sendError(ws, `Permission request not found or expired: ${requestId}`);
    }
  }

  // ── Shared session operations ──

  private listSessions(ws: WebSocket): void {
    const sessions = [...this.sessions.values()].map((s) => ({
      sessionId: s.info.sessionId,
      cwd: s.info.cwd,
      agent: s.info.agent,
    }));
    send(ws, { type: 'session/list', sessions });
  }

  private resumeSession(ws: WebSocket, sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }

    // Cancel reconnect timer
    if (session.reconnectTimer) {
      clearTimeout(session.reconnectTimer);
      session.reconnectTimer = null;
    }

    session.client = ws;
    console.log(`[session] Resumed ${sessionId}`);
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

    if (session.bridge) {
      // v1 — kill the bridge process
      session.bridge.destroy();
    } else {
      // v2 — close via AcpManager
      void this.acpManager.closeSession(session.info.agent, sessionId);
    }

    this.sessions.delete(sessionId);
    console.log(`[session] Destroyed ${sessionId}`);
  }

  // ── Event relay ──

  /** Relay v1 AcpBridge events to WebSocket (v1 protocol) */
  private relayV1Event(sessionId: string, event: AcpEvent): void {
    const session = this.sessions.get(sessionId);
    if (!session?.client || session.client.readyState !== WebSocket.OPEN) {
      return;
    }

    const ws = session.client;

    switch (event.type) {
      case 'text':
        send(ws, { type: 'stream/text', sessionId, content: event.content });
        break;
      case 'tool_use':
        send(ws, { type: 'stream/tool_use', sessionId, tool: event.tool, input: event.input });
        break;
      case 'turn_end':
        send(ws, { type: 'stream/end', sessionId, result: event.result });
        break;
      case 'error':
        send(ws, { type: 'error', message: event.message });
        break;
      case 'exit':
        send(ws, { type: 'error', message: `Claude process exited (code: ${event.code})` });
        this.destroySessionById(sessionId);
        break;
    }
  }

  /** Relay v2 AcpManager events to WebSocket (v2 protocol) */
  private relayAcpManagerEvent(event: AcpManagerEvent): void {
    // agent_exit has no sessionId — handle separately
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
        send(ws, { type: 'event/text', sessionId, content: event.content });
        break;
      case 'tool_call':
        send(ws, {
          type: 'event/tool_call',
          sessionId,
          toolCallId: event.toolCallId,
          tool: event.title,
          status: event.status,
        });
        break;
      case 'tool_call_update':
        send(ws, {
          type: 'event/tool_call_update',
          sessionId,
          toolCallId: event.toolCallId,
          status: event.status,
        });
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
    const expanded = cwd.startsWith('~/') || cwd === '~'
      ? path.join(os.homedir(), cwd.slice(1))
      : cwd;
    const resolved = path.resolve(expanded);

    if (!this.isAllowedDir(resolved)) return null;
    return resolved;
  }

  private isAllowedDir(resolved: string): boolean {
    return this.config.allowedDirs.some(
      (allowed) => resolved === allowed || resolved.startsWith(allowed + path.sep),
    );
  }

  private isV2Session(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    return session ? session.info.protocolVersion >= 2 : false;
  }
}
