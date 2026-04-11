import path from 'node:path';
import crypto from 'node:crypto';
import { WebSocket } from 'ws';
import { AcpBridge, type AcpEvent } from './acp.js';
import { send, sendError } from './server.js';
import type { Config } from './config.js';
import type { ClientMessage } from './types.js';

export interface SessionInfo {
  sessionId: string;
  cwd: string;
  createdAt: number;
  lastMessageAt: number;
}

interface Session {
  info: SessionInfo;
  bridge: AcpBridge;
  client: WebSocket | null;
  /** Timer for reconnect window — destroys session if no client reconnects */
  reconnectTimer: ReturnType<typeof setTimeout> | null;
}

export class SessionManager {
  private sessions = new Map<string, Session>();
  private readonly config: Config;
  private readonly reconnectWindowMs: number;

  constructor(config: Config, reconnectWindowSeconds = 300) {
    this.config = config;
    this.reconnectWindowMs = reconnectWindowSeconds * 1000;
  }

  handleMessage(ws: WebSocket, msg: ClientMessage): void {
    switch (msg.type) {
      case 'session/create':
        this.createSession(ws, msg.cwd);
        break;
      case 'session/list':
        this.listSessions(ws);
        break;
      case 'session/resume':
        this.resumeSession(ws, msg.sessionId);
        break;
      case 'session/message':
        this.sendMessage(ws, msg.sessionId, msg.content);
        break;
      case 'session/destroy':
        this.destroySession(ws, msg.sessionId);
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
  }

  private createSession(ws: WebSocket, cwd: string): void {
    const resolved = path.resolve(cwd);

    if (!this.isAllowedDir(resolved)) {
      sendError(ws, `Directory not allowed: ${cwd}`);
      return;
    }

    const sessionId = crypto.randomUUID();
    const bridge = new AcpBridge();

    const session: Session = {
      info: {
        sessionId,
        cwd: resolved,
        createdAt: Date.now(),
        lastMessageAt: Date.now(),
      },
      bridge,
      client: ws,
      reconnectTimer: null,
    };

    this.sessions.set(sessionId, session);

    // Relay ACP events to WebSocket client
    bridge.on('event', (event: AcpEvent) => {
      this.relayEvent(sessionId, event);
    });

    try {
      bridge.start({ claudePath: this.config.claudePath, cwd: resolved });
    } catch (err) {
      this.sessions.delete(sessionId);
      sendError(ws, `Failed to start claude: ${(err as Error).message}`);
      return;
    }

    console.log(`[session] Created ${sessionId} in ${resolved}`);
    send(ws, { type: 'session/created', sessionId, cwd: resolved });
  }

  private listSessions(ws: WebSocket): void {
    const sessions = [...this.sessions.values()].map((s) => ({
      sessionId: s.info.sessionId,
      cwd: s.info.cwd,
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

  private sendMessage(ws: WebSocket, sessionId: string, content: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }

    if (!session.bridge.alive) {
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

  private destroySession(ws: WebSocket, sessionId: string): void {
    if (!this.sessions.has(sessionId)) {
      sendError(ws, `Session not found: ${sessionId}`);
      return;
    }
    this.destroySessionById(sessionId);
    send(ws, { type: 'session/created', sessionId, cwd: '' }); // ack
  }

  private destroySessionById(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    if (session.reconnectTimer) {
      clearTimeout(session.reconnectTimer);
    }

    session.bridge.destroy();
    this.sessions.delete(sessionId);
    console.log(`[session] Destroyed ${sessionId}`);
  }

  private relayEvent(sessionId: string, event: AcpEvent): void {
    const session = this.sessions.get(sessionId);
    if (!session?.client || session.client.readyState !== WebSocket.OPEN) return;

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

  private isAllowedDir(resolved: string): boolean {
    return this.config.allowedDirs.some(
      (allowed) => resolved === allowed || resolved.startsWith(allowed + path.sep),
    );
  }
}
