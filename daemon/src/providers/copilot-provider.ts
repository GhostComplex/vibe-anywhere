import { spawn, type ChildProcess } from 'node:child_process';
import crypto from 'node:crypto';
import { Writable, Readable } from 'node:stream';
import { EventEmitter } from 'node:events';
import * as acp from '@agentclientprotocol/sdk';
import type { AgentClient, AgentStreamEvent, HostSessionInfo } from './types.js';

// ── Config ──

export interface CopilotProviderConfig {
  copilotPath: string;  // path to copilot binary, default "copilot"
  permissionMode: 'prompt' | 'approve-all' | 'deny-all';
  timeout: number;
}

// ── Internal state ──

interface CopilotProcess {
  process: ChildProcess;
  connection: acp.ClientSideConnection;
  initialized: boolean;
  sessions: Set<string>;
  capabilities: {
    listSessions: boolean;
    resumeSession: boolean;
    loadSession: boolean;
  };
}

// Pending permission requests awaiting iOS response
interface PendingPermission {
  resolve: (response: acp.RequestPermissionResponse) => void;
  options: Array<{ optionId: string; name: string; kind: string }>;
  timer: ReturnType<typeof setTimeout> | null;
}

/**
 * CopilotProvider — manages Copilot Coding Agent via ACP SDK.
 *
 * Spawns a single `copilot --acp` subprocess and communicates over
 * stdin/stdout using the ACP ndjson protocol. Implements AgentClient
 * interface for use with ProviderRegistry.
 */
export class CopilotProvider extends EventEmitter implements AgentClient {
  readonly provider = 'copilot';
  private copilotProc: CopilotProcess | null = null;
  private pendingPermissions = new Map<string, PendingPermission>();
  private replayingSessions = new Set<string>();
  private readonly config: CopilotProviderConfig;

  constructor(config: CopilotProviderConfig) {
    super();
    this.config = config;
  }

  // ── Process Lifecycle ──

  async ensureAgent(_agent: string): Promise<void> {
    if (this.copilotProc) return;
    await this.spawnCopilot();
  }

  private async spawnCopilot(): Promise<CopilotProcess> {
    const cmd = this.config.copilotPath;
    const args = ['--acp'];

    console.log(`[copilot] Spawning: ${cmd} ${args.join(' ')}`);

    const proc = spawn(cmd, args, {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    console.log(`[copilot] Process spawned, pid: ${proc.pid}`);

    proc.stderr?.on('data', (data: Buffer) => {
      const msg = data.toString().trim();
      if (msg) console.error(`[copilot:stderr] ${msg}`);
    });

    const input = Writable.toWeb(proc.stdin!);
    const output = Readable.toWeb(proc.stdout!) as ReadableStream<Uint8Array>;
    const stream = acp.ndJsonStream(input, output);

    const copilotProc: CopilotProcess = {
      process: proc,
      connection: null as unknown as acp.ClientSideConnection,
      initialized: false,
      sessions: new Set(),
      capabilities: {
        listSessions: false,
        resumeSession: false,
        loadSession: false,
      },
    };

    const client = this.buildClient();
    const connection = new acp.ClientSideConnection((_agent) => client, stream);
    copilotProc.connection = connection;

    // Handle process exit
    proc.on('close', (code) => {
      console.log(`[copilot] Process exited (code: ${code})`);
      this.copilotProc = null;
      this.emit('event', { type: 'agent_exit', agent: 'copilot', code } satisfies AgentStreamEvent);
    });

    proc.on('error', (err) => {
      console.error(`[copilot] Process error: ${err.message}`);
      this.copilotProc = null;
      this.emit('event', { type: 'error', sessionId: null, message: `Copilot failed: ${err.message}` } satisfies AgentStreamEvent);
    });

    // Initialize ACP connection
    console.log(`[copilot] Sending initialize request (protocol v${acp.PROTOCOL_VERSION})...`);
    try {
      const initResult = await connection.initialize({
        protocolVersion: acp.PROTOCOL_VERSION,
        clientCapabilities: {
          fs: {
            readTextFile: true,
            writeTextFile: true,
          },
        },
      });
      copilotProc.initialized = true;
      console.log(`[copilot] Initialized (protocol v${initResult.protocolVersion})`);

      // Extract capabilities
      const caps = initResult.agentCapabilities;
      if (caps) {
        copilotProc.capabilities.loadSession = !!(caps as Record<string, unknown>).loadSession;
        const sessionCaps = (caps as Record<string, unknown>).sessionCapabilities as Record<string, unknown> | undefined;
        if (sessionCaps) {
          copilotProc.capabilities.listSessions = !!sessionCaps.list;
          copilotProc.capabilities.resumeSession = !!sessionCaps.resume;
        }
      }
      console.log(`[copilot] Capabilities: ${JSON.stringify(copilotProc.capabilities)}`);
    } catch (err) {
      console.error(`[copilot] Initialize failed:`, err);
      proc.kill('SIGTERM');
      throw new Error(`Failed to initialize Copilot: ${(err as Error).message}`);
    }

    this.copilotProc = copilotProc;
    return copilotProc;
  }

  private buildClient(): acp.Client {
    return {
      requestPermission: async (params: acp.RequestPermissionRequest): Promise<acp.RequestPermissionResponse> => {
        return this.handlePermissionRequest(params);
      },

      sessionUpdate: async (params: acp.SessionNotification): Promise<void> => {
        this.handleSessionUpdate(params);
      },

      readTextFile: async (_params: acp.ReadTextFileRequest): Promise<acp.ReadTextFileResponse> => {
        return { content: '' };
      },
      writeTextFile: async (_params: acp.WriteTextFileRequest): Promise<acp.WriteTextFileResponse> => {
        return {};
      },
    };
  }

  // ── Helper ──

  private getProc(): CopilotProcess {
    if (!this.copilotProc) throw new Error('Copilot process not running');
    return this.copilotProc;
  }

  // ── Session Management ──

  async createSession(_agent: string, cwd: string): Promise<{ sessionId: string }> {
    await this.ensureAgent('copilot');
    const proc = this.getProc();

    const result = await proc.connection.newSession({
      cwd,
      mcpServers: [],
    });

    proc.sessions.add(result.sessionId);
    console.log(`[copilot] Session created: ${result.sessionId} (cwd: ${cwd})`);
    return { sessionId: result.sessionId };
  }

  async loadSession(_agent: string, sessionId: string, cwd: string): Promise<void> {
    await this.ensureAgent('copilot');
    const proc = this.getProc();

    await proc.connection.loadSession({ sessionId, cwd, mcpServers: [] });
    proc.sessions.add(sessionId);
    console.log(`[copilot] Session loaded: ${sessionId}`);
  }

  async listHostSessions(_agent: string): Promise<{ sessions: HostSessionInfo[]; supported: boolean }> {
    await this.ensureAgent('copilot');
    const proc = this.getProc();

    if (!proc.capabilities.listSessions) {
      return { sessions: [], supported: false };
    }

    const allSessions: HostSessionInfo[] = [];
    let cursor: string | undefined;

    do {
      const result = await proc.connection.listSessions({ cursor });
      for (const s of result.sessions) {
        allSessions.push({
          sessionId: s.sessionId,
          cwd: s.cwd,
          title: s.title ?? undefined,
          updatedAt: s.updatedAt ?? undefined,
        });
      }
      cursor = result.nextCursor ?? undefined;
    } while (cursor);

    console.log(`[copilot] Listed ${allSessions.length} host sessions`);
    return { sessions: allSessions, supported: true };
  }

  async resumeHostSession(_agent: string, sessionId: string, cwd: string): Promise<{ sessionId: string }> {
    await this.ensureAgent('copilot');
    const proc = this.getProc();

    if (!proc.capabilities.loadSession) {
      throw new Error('Copilot does not support session load');
    }

    this.replayingSessions.add(sessionId);

    try {
      await proc.connection.loadSession({ sessionId, cwd, mcpServers: [] });
      console.log(`[copilot] Host session loaded: ${sessionId}`);
    } finally {
      this.replayingSessions.delete(sessionId);
    }

    this.emit('event', { type: 'replay_end', sessionId } satisfies AgentStreamEvent);

    proc.sessions.add(sessionId);
    return { sessionId };
  }

  async closeSession(_agent: string, sessionId: string): Promise<void> {
    const proc = this.copilotProc;
    if (!proc) return;

    try {
      await proc.connection.unstable_closeSession({ sessionId });
    } catch (err) {
      console.error(`[copilot] Error closing session ${sessionId}: ${(err as Error).message}`);
    }

    proc.sessions.delete(sessionId);
    console.log(`[copilot] Session closed: ${sessionId}`);
  }

  // ── Interaction ──

  async prompt(_agent: string, sessionId: string, content: string): Promise<void> {
    const proc = this.getProc();
    if (!proc.sessions.has(sessionId)) throw new Error(`Session "${sessionId}" not found`);

    try {
      const result = await proc.connection.prompt({
        sessionId,
        prompt: [{ type: 'text', text: content }],
      });

      this.emit('event', {
        type: 'turn_end',
        sessionId,
        stopReason: result.stopReason ?? 'end_turn',
      } satisfies AgentStreamEvent);
    } catch (err) {
      this.emit('event', {
        type: 'error',
        sessionId,
        message: `Prompt failed: ${(err as Error).message}`,
      } satisfies AgentStreamEvent);
    }
  }

  async cancel(_agent: string, sessionId: string): Promise<void> {
    const proc = this.copilotProc;
    if (!proc) return;

    try {
      await proc.connection.cancel({ sessionId });
      console.log(`[copilot] Cancelled session ${sessionId}`);
    } catch (err) {
      console.error(`[copilot] Cancel failed for ${sessionId}: ${(err as Error).message}`);
    }
  }

  // ── Controls ──

  async setMode(_agent: string, sessionId: string, mode: string): Promise<void> {
    const proc = this.getProc();
    await proc.connection.setSessionMode({ sessionId, mode });
    console.log(`[copilot] Mode set to "${mode}" for session ${sessionId}`);
  }

  async setModel(_agent: string, sessionId: string, model: string): Promise<void> {
    const proc = this.getProc();
    await proc.connection.unstable_setSessionModel({ sessionId, model });
    console.log(`[copilot] Model set to "${model}" for session ${sessionId}`);
  }

  // ── Permission Handling ──

  private async handlePermissionRequest(
    params: acp.RequestPermissionRequest,
  ): Promise<acp.RequestPermissionResponse> {
    const { permissionMode } = this.config;

    if (permissionMode === 'approve-all') {
      const approveOption = params.options.find((o) => o.kind === 'allow_once' || o.kind === 'allow_always');
      if (approveOption) {
        return { outcome: { outcome: 'selected', optionId: approveOption.optionId } };
      }
    }
    if (permissionMode === 'deny-all') {
      const denyOption = params.options.find((o) => o.kind === 'reject_once' || o.kind === 'reject_always');
      if (denyOption) {
        return { outcome: { outcome: 'selected', optionId: denyOption.optionId } };
      }
    }

    // Prompt mode — relay to iOS client
    const requestId = crypto.randomUUID();
    const options = params.options.map((o) => ({
      optionId: o.optionId,
      name: o.name,
      kind: o.kind,
    }));

    const sessionId = params.sessionId;

    this.emit('event', {
      type: 'permission_request',
      sessionId,
      requestId,
      toolTitle: params.toolCall.title ?? 'Unknown tool',
      options,
    } satisfies AgentStreamEvent);

    return new Promise<acp.RequestPermissionResponse>((resolve) => {
      const timer = setTimeout(() => {
        this.pendingPermissions.delete(requestId);
        const denyOption = params.options.find((o) => o.kind === 'reject_once' || o.kind === 'reject_always');
        if (denyOption) {
          resolve({ outcome: { outcome: 'selected', optionId: denyOption.optionId } });
        } else {
          resolve({ outcome: { outcome: 'selected', optionId: params.options[0].optionId } });
        }
        console.log(`[copilot] Permission request ${requestId} timed out — auto-denied`);
      }, this.config.timeout * 1000);

      this.pendingPermissions.set(requestId, { resolve, options, timer });
    });
  }

  respondPermission(requestId: string, optionId: string): boolean {
    const pending = this.pendingPermissions.get(requestId);
    if (!pending) return false;

    if (pending.timer) clearTimeout(pending.timer);
    this.pendingPermissions.delete(requestId);

    pending.resolve({
      outcome: { outcome: 'selected', optionId },
    });

    return true;
  }

  // ── Session Update Handler ──

  private handleSessionUpdate(params: acp.SessionNotification): void {
    const sessionId = params.sessionId;
    const update = params.update;
    const replay = this.replayingSessions.has(sessionId) || undefined;

    switch (update.sessionUpdate) {
      case 'user_message_chunk': {
        if (update.content.type === 'text') {
          this.emit('event', {
            type: 'user_text',
            sessionId,
            content: update.content.text,
            replay,
          } satisfies AgentStreamEvent);
        }
        break;
      }

      case 'agent_message_chunk': {
        if (update.content.type === 'text') {
          this.emit('event', {
            type: 'text',
            sessionId,
            content: update.content.text,
            replay,
          } satisfies AgentStreamEvent);
        }
        break;
      }

      case 'tool_call': {
        this.emit('event', {
          type: 'tool_call',
          sessionId,
          toolCallId: update.toolCallId,
          title: update.title,
          status: update.status ?? 'running',
          replay,
        } satisfies AgentStreamEvent);
        break;
      }

      case 'tool_call_update': {
        this.emit('event', {
          type: 'tool_call_update',
          sessionId,
          toolCallId: update.toolCallId,
          status: update.status ?? 'running',
          replay,
        } satisfies AgentStreamEvent);
        break;
      }

      default:
        break;
    }
  }

  // ── Shutdown ──

  async shutdown(): Promise<void> {
    // Clear pending permissions
    for (const [id, pending] of this.pendingPermissions) {
      if (pending.timer) clearTimeout(pending.timer);
      this.pendingPermissions.delete(id);
    }

    if (!this.copilotProc) {
      console.log('[copilot] No process to shut down');
      return;
    }

    const proc = this.copilotProc;
    console.log('[copilot] Shutting down...');

    // Close all sessions gracefully
    for (const sessionId of proc.sessions) {
      try {
        await proc.connection.unstable_closeSession({ sessionId });
      } catch { /* best effort */ }
    }

    // Kill the process
    proc.process.kill('SIGTERM');
    await new Promise<void>((resolve) => {
      const forceKill = setTimeout(() => {
        proc.process.kill('SIGKILL');
        resolve();
      }, 3000);
      proc.process.on('close', () => {
        clearTimeout(forceKill);
        resolve();
      });
    });

    this.copilotProc = null;
    console.log('[copilot] Shut down');
  }

  // ── Introspection ──

  isAgentRunning(_agent: string): boolean {
    return this.copilotProc !== null;
  }

  getSessionAgent(sessionId: string): string | null {
    if (this.copilotProc?.sessions.has(sessionId)) return 'copilot';
    return null;
  }
}
