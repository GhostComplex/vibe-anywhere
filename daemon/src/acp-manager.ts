import { spawn, type ChildProcess } from 'node:child_process';
import crypto from 'node:crypto';
import { Writable, Readable } from 'node:stream';
import { EventEmitter } from 'node:events';
import * as acp from '@agentclientprotocol/sdk';

// ── Events emitted by AcpManager ──

export type AcpManagerEvent =
  | { type: 'text'; sessionId: string; content: string }
  | { type: 'tool_call'; sessionId: string; toolCallId: string; title: string; status: string; input?: Record<string, unknown> }
  | { type: 'tool_call_update'; sessionId: string; toolCallId: string; status: string; content?: string }
  | { type: 'permission_request'; sessionId: string; requestId: string; toolTitle: string; options: Array<{ optionId: string; name: string; kind: string }> }
  | { type: 'usage'; sessionId: string; inputTokens: number; outputTokens: number }
  | { type: 'turn_end'; sessionId: string; stopReason: string }
  | { type: 'error'; sessionId: string | null; message: string }
  | { type: 'agent_exit'; agent: string; code: number | null };

// ── Config ──

export interface AcpManagerConfig {
  acpxPath: string;         // path to acpx binary or 'npx'
  permissionMode: 'prompt' | 'approve-all' | 'deny-all';
  timeout: number;          // seconds per turn
}

// ── Internal state per agent process ──

interface AgentProcess {
  agent: string;
  process: ChildProcess;
  connection: acp.ClientSideConnection;
  initialized: boolean;
  sessions: Set<string>;    // sessionIds managed by this process
}

// Pending permission requests awaiting iOS response
interface PendingPermission {
  resolve: (response: acp.RequestPermissionResponse) => void;
  options: Array<{ optionId: string; name: string; kind: string }>;
  timer: ReturnType<typeof setTimeout> | null;
}

/**
 * AcpManager — manages acpx child processes via ACP SDK.
 *
 * One acpx process per agent type. Each process can host multiple sessions.
 * Emits events for the WebSocket relay layer.
 */
export class AcpManager extends EventEmitter {
  private agents = new Map<string, AgentProcess>();
  private pendingPermissions = new Map<string, PendingPermission>();
  private readonly config: AcpManagerConfig;

  constructor(config: AcpManagerConfig) {
    super();
    this.config = config;
  }

  // ── Agent Process Lifecycle ──

  async ensureAgent(agent: string): Promise<void> {
    if (this.agents.has(agent)) return;
    await this.spawnAgent(agent);
  }

  // Map agent name → ACP adapter package (what acpx uses internally)
  private static readonly ACP_AGENTS: Record<string, string> = {
    claude: '@agentclientprotocol/claude-agent-acp',
    codex: '@zed-industries/codex-acp',
  };

  private async spawnAgent(agent: string): Promise<AgentProcess> {
    const acpPackage = AcpManager.ACP_AGENTS[agent];
    let cmd: string;
    let args: string[];

    if (acpPackage && this.config.acpxPath === 'npx') {
      // Use the actual ACP adapter package directly
      cmd = 'npx';
      args = ['-y', `${acpPackage}@latest`];
    } else if (this.config.acpxPath === 'npx') {
      // Unknown agent — fall back to acpx
      cmd = 'npx';
      args = ['--yes', 'acpx@latest', agent];
    } else {
      cmd = this.config.acpxPath;
      args = [agent];
    }

    console.log(`[acp-mgr] Spawning: ${cmd} ${args.join(' ')}`);

    const proc = spawn(cmd, args, {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    console.log(`[acp-mgr] Process spawned, pid: ${proc.pid}`);

    proc.stderr?.on('data', (data: Buffer) => {
      const msg = data.toString().trim();
      if (msg) console.error(`[acp-mgr:${agent}:stderr] ${msg}`);
    });

    const input = Writable.toWeb(proc.stdin!);
    const output = Readable.toWeb(proc.stdout!) as ReadableStream<Uint8Array>;
    const stream = acp.ndJsonStream(input, output);

    const agentProc: AgentProcess = {
      agent,
      process: proc,
      connection: null as unknown as acp.ClientSideConnection,
      initialized: false,
      sessions: new Set(),
    };

    // Build ACP client that handles callbacks
    const client = this.buildClient(agent, agentProc);
    const connection = new acp.ClientSideConnection((_agent) => client, stream);
    agentProc.connection = connection;

    // Handle process exit
    proc.on('close', (code) => {
      console.log(`[acp-mgr] Agent "${agent}" exited (code: ${code})`);
      this.agents.delete(agent);
      this.emit('event', { type: 'agent_exit', agent, code } satisfies AcpManagerEvent);
    });

    proc.on('error', (err) => {
      console.error(`[acp-mgr] Agent "${agent}" error: ${err.message}`);
      this.agents.delete(agent);
      this.emit('event', { type: 'error', sessionId: null, message: `Agent "${agent}" failed: ${err.message}` } satisfies AcpManagerEvent);
    });

    // Initialize ACP connection
    console.log(`[acp-mgr] Sending initialize request to agent "${agent}" (protocol v${acp.PROTOCOL_VERSION})...`);
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
      agentProc.initialized = true;
      console.log(`[acp-mgr] Agent "${agent}" initialized (protocol v${initResult.protocolVersion})`);
    } catch (err) {
      console.error(`[acp-mgr] Initialize failed for "${agent}":`, err);
      proc.kill('SIGTERM');
      throw new Error(`Failed to initialize agent "${agent}": ${(err as Error).message}`);
    }

    this.agents.set(agent, agentProc);
    return agentProc;
  }

  private buildClient(agent: string, agentProc: AgentProcess): acp.Client {
    return {
      requestPermission: async (params: acp.RequestPermissionRequest): Promise<acp.RequestPermissionResponse> => {
        return this.handlePermissionRequest(agent, agentProc, params);
      },

      sessionUpdate: async (params: acp.SessionNotification): Promise<void> => {
        this.handleSessionUpdate(params);
      },

      // File system callbacks — let the agent handle files directly
      readTextFile: async (_params: acp.ReadTextFileRequest): Promise<acp.ReadTextFileResponse> => {
        return { content: '' };
      },
      writeTextFile: async (_params: acp.WriteTextFileRequest): Promise<acp.WriteTextFileResponse> => {
        return {};
      },
    };
  }

  // ── Session Management ──

  async createSession(agent: string, cwd: string): Promise<{ sessionId: string }> {
    await this.ensureAgent(agent);
    const agentProc = this.agents.get(agent)!;

    const result = await agentProc.connection.newSession({
      cwd,
      mcpServers: [],
    });

    agentProc.sessions.add(result.sessionId);
    console.log(`[acp-mgr] Session created: ${result.sessionId} (agent: ${agent}, cwd: ${cwd})`);
    return { sessionId: result.sessionId };
  }

  async loadSession(agent: string, sessionId: string): Promise<void> {
    await this.ensureAgent(agent);
    const agentProc = this.agents.get(agent)!;

    await agentProc.connection.loadSession({ sessionId });
    agentProc.sessions.add(sessionId);
    console.log(`[acp-mgr] Session loaded: ${sessionId} (agent: ${agent})`);
  }

  async closeSession(agent: string, sessionId: string): Promise<void> {
    const agentProc = this.agents.get(agent);
    if (!agentProc) return;

    try {
      await agentProc.connection.unstable_closeSession({ sessionId });
    } catch (err) {
      console.error(`[acp-mgr] Error closing session ${sessionId}: ${(err as Error).message}`);
    }

    agentProc.sessions.delete(sessionId);
    console.log(`[acp-mgr] Session closed: ${sessionId}`);
  }

  // ── Interaction ──

  async prompt(agent: string, sessionId: string, content: string): Promise<void> {
    const agentProc = this.agents.get(agent);
    if (!agentProc) throw new Error(`Agent "${agent}" not running`);
    if (!agentProc.sessions.has(sessionId)) throw new Error(`Session "${sessionId}" not found on agent "${agent}"`);

    try {
      const result = await agentProc.connection.prompt({
        sessionId,
        prompt: [{ type: 'text', text: content }],
      });

      this.emit('event', {
        type: 'turn_end',
        sessionId,
        stopReason: result.stopReason ?? 'end_turn',
      } satisfies AcpManagerEvent);
    } catch (err) {
      this.emit('event', {
        type: 'error',
        sessionId,
        message: `Prompt failed: ${(err as Error).message}`,
      } satisfies AcpManagerEvent);
    }
  }

  async cancel(agent: string, sessionId: string): Promise<void> {
    const agentProc = this.agents.get(agent);
    if (!agentProc) return;

    try {
      await agentProc.connection.cancel({ sessionId });
      console.log(`[acp-mgr] Cancelled session ${sessionId}`);
    } catch (err) {
      console.error(`[acp-mgr] Cancel failed for ${sessionId}: ${(err as Error).message}`);
    }
  }

  // ── Controls ──

  async setMode(agent: string, sessionId: string, mode: string): Promise<void> {
    const agentProc = this.agents.get(agent);
    if (!agentProc) throw new Error(`Agent "${agent}" not running`);

    await agentProc.connection.setSessionMode({ sessionId, mode });
    console.log(`[acp-mgr] Mode set to "${mode}" for session ${sessionId}`);
  }

  async setModel(agent: string, sessionId: string, model: string): Promise<void> {
    const agentProc = this.agents.get(agent);
    if (!agentProc) throw new Error(`Agent "${agent}" not running`);

    await agentProc.connection.unstable_setSessionModel({ sessionId, model });
    console.log(`[acp-mgr] Model set to "${model}" for session ${sessionId}`);
  }

  // ── Permission Handling ──

  private async handlePermissionRequest(
    _agent: string,
    _agentProc: AgentProcess,
    params: acp.RequestPermissionRequest,
  ): Promise<acp.RequestPermissionResponse> {
    const { permissionMode } = this.config;

    // Auto-approve/deny if configured
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

    // Find which session this is for — use toolCall context if available
    const sessionId = params.sessionId;

    this.emit('event', {
      type: 'permission_request',
      sessionId,
      requestId,
      toolTitle: params.toolCall.title ?? 'Unknown tool',
      options,
    } satisfies AcpManagerEvent);

    // Wait for iOS response with timeout
    return new Promise<acp.RequestPermissionResponse>((resolve) => {
      const timer = setTimeout(() => {
        this.pendingPermissions.delete(requestId);
        const denyOption = params.options.find((o) => o.kind === 'reject_once' || o.kind === 'reject_always');
        if (denyOption) {
          resolve({ outcome: { outcome: 'selected', optionId: denyOption.optionId } });
        } else {
          resolve({ outcome: { outcome: 'selected', optionId: params.options[0].optionId } });
        }
        console.log(`[acp-mgr] Permission request ${requestId} timed out — auto-denied`);
      }, this.config.timeout * 1000);

      this.pendingPermissions.set(requestId, { resolve, options, timer });
    });
  }

  /**
   * Called by WebSocket layer when iOS responds to a permission request.
   */
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

    switch (update.sessionUpdate) {
      case 'agent_message_chunk': {
        if (update.content.type === 'text') {
          this.emit('event', {
            type: 'text',
            sessionId,
            content: update.content.text,
          } satisfies AcpManagerEvent);
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
        } satisfies AcpManagerEvent);
        break;
      }

      case 'tool_call_update': {
        this.emit('event', {
          type: 'tool_call_update',
          sessionId,
          toolCallId: update.toolCallId,
          status: update.status ?? 'running',
        } satisfies AcpManagerEvent);
        break;
      }

      default:
        // plan, agent_thought_chunk, user_message_chunk — skip for now
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

    // Kill all agent processes
    const kills = [...this.agents.entries()].map(async ([agent, agentProc]) => {
      console.log(`[acp-mgr] Shutting down agent "${agent}"`);

      // Try to close all sessions gracefully
      for (const sessionId of agentProc.sessions) {
        try {
          await agentProc.connection.unstable_closeSession({ sessionId });
        } catch { /* best effort */ }
      }

      // Kill the process
      agentProc.process.kill('SIGTERM');
      await new Promise<void>((resolve) => {
        const forceKill = setTimeout(() => {
          agentProc.process.kill('SIGKILL');
          resolve();
        }, 3000);
        agentProc.process.on('close', () => {
          clearTimeout(forceKill);
          resolve();
        });
      });
    });

    await Promise.all(kills);
    this.agents.clear();
    console.log('[acp-mgr] All agents shut down');
  }

  // ── Introspection ──
  isAgentRunning(agent: string): boolean {
    return this.agents.has(agent);
  }

  getSessionAgent(sessionId: string): string | null {
    for (const [agent, agentProc] of this.agents) {
      if (agentProc.sessions.has(sessionId)) return agent;
    }
    return null;
  }
}
