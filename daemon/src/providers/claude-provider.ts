import crypto from 'node:crypto';
import { EventEmitter } from 'node:events';
import {
  query as sdkQuery,
  listSessions,
  getSessionMessages,
  type Options,
  type Query,
  type SDKMessage,
  type SDKAssistantMessage,
  type SDKPartialAssistantMessage,
  type SDKResultMessage,
  type SDKSystemMessage,
  type SDKUserMessage,
  type SDKUserMessageReplay,
  type PermissionMode,
  type PermissionResult,
} from '@anthropic-ai/claude-agent-sdk';
import type { AgentClient, AgentStreamEvent, HostSessionInfo } from './types.js';

// ── Config ──

export interface ClaudeProviderConfig {
  permissionMode: PermissionMode;
  timeout: number;  // permission response timeout in seconds
}

// ── Async message input for multi-turn ──

interface AsyncInput<T> {
  push(value: T): void;
  end(): void;
  iterable: AsyncIterable<T>;
}

function createAsyncInput<T>(): AsyncInput<T> {
  const queue: T[] = [];
  let resolve: (() => void) | null = null;
  let done = false;

  return {
    push(value: T) {
      queue.push(value);
      resolve?.();
      resolve = null;
    },
    end() {
      done = true;
      resolve?.();
      resolve = null;
    },
    iterable: {
      [Symbol.asyncIterator]() {
        return {
          async next(): Promise<IteratorResult<T>> {
            while (queue.length === 0 && !done) {
              await new Promise<void>((r) => { resolve = r; });
            }
            if (queue.length > 0) {
              return { value: queue.shift()!, done: false };
            }
            return { value: undefined as unknown as T, done: true };
          },
        };
      },
    },
  };
}

// ── Internal session state ──

interface ClaudeSession {
  sessionId: string;
  cwd: string;
  query: Query;
  input: AsyncInput<SDKUserMessage>;
  abortController: AbortController;
  pumpPromise: Promise<void>;
}

// Pending permission requests awaiting iOS response
interface PendingPermission {
  resolve: (result: PermissionResult) => void;
  timer: ReturnType<typeof setTimeout> | null;
}

/**
 * ClaudeProvider — manages Claude sessions via @anthropic-ai/claude-agent-sdk.
 *
 * Each session runs a `query()` with an async message input for multi-turn.
 * Implements AgentClient interface for use with ProviderRegistry.
 */
export class ClaudeProvider extends EventEmitter implements AgentClient {
  readonly provider = 'claude-sdk';
  private sessions = new Map<string, ClaudeSession>();
  private pendingPermissions = new Map<string, PendingPermission>();
  private readonly config: ClaudeProviderConfig;

  constructor(config: ClaudeProviderConfig) {
    super();
    this.config = config;
  }

  // ── Lifecycle ──

  async ensureAgent(_agent: string): Promise<void> {
    // No persistent process to manage — query() spawns on demand
  }

  async shutdown(): Promise<void> {
    // Clear pending permissions
    for (const [id, pending] of this.pendingPermissions) {
      if (pending.timer) clearTimeout(pending.timer);
      this.pendingPermissions.delete(id);
    }

    // Abort all sessions
    const closeTasks = [...this.sessions.entries()].map(async ([sessionId, session]) => {
      console.log(`[claude-sdk] Closing session ${sessionId}`);
      session.abortController.abort();
      session.input.end();
      try {
        await session.pumpPromise;
      } catch { /* expected on abort */ }
    });

    await Promise.all(closeTasks);
    this.sessions.clear();
    console.log('[claude-sdk] All sessions shut down');
  }

  // ── Sessions ──

  async createSession(_agent: string, cwd: string): Promise<{ sessionId: string }> {
    const input = createAsyncInput<SDKUserMessage>();
    const abortController = new AbortController();

    const options: Options = {
      cwd,
      permissionMode: this.config.permissionMode,
      canUseTool: (toolName, toolInput, opts) => this.handlePermission(toolName, toolInput, opts),
      abortController,
      includePartialMessages: true,
    };

    const q = sdkQuery({ prompt: input.iterable, options });

    // We don't know the sessionId until we get the first system message.
    // Start the pump and capture it.
    const sessionId = await new Promise<string>((resolveId, rejectId) => {
      const session: ClaudeSession = {
        sessionId: '', // will be set once we know
        cwd,
        query: q,
        input,
        abortController,
        pumpPromise: null as unknown as Promise<void>,
      };

      // Store temporarily with a placeholder — will be updated when sessionId arrives
      const tempId = `pending-${crypto.randomUUID()}`;
      this.sessions.set(tempId, session);

      // Wrap resolveId to re-key the map when real sessionId arrives
      const origResolve = resolveId;
      const wrappedResolve = (id: string): void => {
        this.sessions.delete(tempId);
        session.sessionId = id;
        this.sessions.set(id, session);
        origResolve(id);
      };

      session.pumpPromise = this.runPump(q, session, wrappedResolve);
      session.pumpPromise.catch((err) => {
        if (!session.sessionId) {
          rejectId(err);
        }
      });
    });

    console.log(`[claude-sdk] Session created: ${sessionId} (cwd: ${cwd})`);
    return { sessionId };
  }

  async loadSession(_agent: string, sessionId: string, cwd: string): Promise<void> {
    // Resume an existing session by creating a query with `resume`
    await this.startResumedSession(sessionId, cwd);
    console.log(`[claude-sdk] Session loaded: ${sessionId}`);
  }

  async resumeHostSession(_agent: string, sessionId: string, cwd: string): Promise<{ sessionId: string }> {
    // Step 1: Read history and emit as replay events
    try {
      const messages = await getSessionMessages(sessionId, { dir: cwd });
      for (const msg of messages) {
        if (msg.type === 'user') {
          const content = (msg.message as { content?: unknown })?.content;
          const text = typeof content === 'string' ? content : '';
          if (text) {
            this.emit('event', {
              type: 'user_text',
              sessionId,
              content: text,
              replay: true,
            } satisfies AgentStreamEvent);
          }
        } else if (msg.type === 'assistant') {
          const betaMsg = msg.message as { content?: Array<{ type: string; text?: string; id?: string; name?: string }> };
          if (betaMsg.content) {
            for (const block of betaMsg.content) {
              if (block.type === 'text' && block.text) {
                this.emit('event', {
                  type: 'text',
                  sessionId,
                  content: block.text,
                  replay: true,
                } satisfies AgentStreamEvent);
              } else if (block.type === 'tool_use') {
                this.emit('event', {
                  type: 'tool_call',
                  sessionId,
                  toolCallId: block.id ?? '',
                  title: block.name ?? 'tool',
                  status: 'completed',
                  replay: true,
                } satisfies AgentStreamEvent);
              }
            }
          }
        }
      }
    } catch (err) {
      console.warn(`[claude-sdk] Failed to read session history: ${(err as Error).message}`);
    }

    // Step 2: Signal replay complete
    this.emit('event', { type: 'replay_end', sessionId } satisfies AgentStreamEvent);

    // Step 3: Set up the resumed session for future prompts
    await this.startResumedSession(sessionId, cwd);
    console.log(`[claude-sdk] Host session resumed: ${sessionId}`);
    return { sessionId };
  }

  private async startResumedSession(sessionId: string, cwd: string): Promise<void> {
    const input = createAsyncInput<SDKUserMessage>();
    const abortController = new AbortController();

    const options: Options = {
      cwd,
      resume: sessionId,
      permissionMode: this.config.permissionMode,
      canUseTool: (toolName, toolInput, opts) => this.handlePermission(toolName, toolInput, opts),
      abortController,
      includePartialMessages: true,
    };

    const q = sdkQuery({ prompt: input.iterable, options });

    const session: ClaudeSession = {
      sessionId,
      cwd,
      query: q,
      input,
      abortController,
      pumpPromise: null as unknown as Promise<void>,
    };

    session.pumpPromise = this.runPump(q, session);
    this.sessions.set(sessionId, session);
  }

  async listHostSessions(_agent: string): Promise<{ sessions: HostSessionInfo[]; supported: boolean }> {
    try {
      const sdkSessions = await listSessions();
      const sessions: HostSessionInfo[] = sdkSessions.map((s) => ({
        sessionId: s.sessionId,
        cwd: s.cwd ?? '',
        title: s.summary,
        updatedAt: new Date(s.lastModified).toISOString(),
      }));
      return { sessions, supported: true };
    } catch (err) {
      console.error(`[claude-sdk] Failed to list sessions: ${(err as Error).message}`);
      return { sessions: [], supported: true };
    }
  }

  async closeSession(_agent: string, sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    session.abortController.abort();
    session.input.end();
    try {
      await session.pumpPromise;
    } catch { /* expected */ }
    this.sessions.delete(sessionId);
    console.log(`[claude-sdk] Session closed: ${sessionId}`);
  }

  // ── Interaction ──

  async prompt(_agent: string, sessionId: string, content: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Session "${sessionId}" not found`);

    const userMessage: SDKUserMessage = {
      type: 'user',
      message: { role: 'user', content },
      parent_tool_use_id: null,
    };

    session.input.push(userMessage);
    // The pump loop will pick up the message and emit events
  }

  async cancel(_agent: string, sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    try {
      await session.query.interrupt();
      console.log(`[claude-sdk] Interrupted session ${sessionId}`);
    } catch (err) {
      console.error(`[claude-sdk] Interrupt failed for ${sessionId}: ${(err as Error).message}`);
    }
  }

  // ── Controls ──

  async setMode(_agent: string, sessionId: string, mode: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Session "${sessionId}" not found`);

    await session.query.setPermissionMode(mode as PermissionMode);
    console.log(`[claude-sdk] Mode set to "${mode}" for session ${sessionId}`);
  }

  async setModel(_agent: string, sessionId: string, model: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Session "${sessionId}" not found`);

    await session.query.setModel(model);
    console.log(`[claude-sdk] Model set to "${model}" for session ${sessionId}`);
  }

  // ── Permission Handling ──

  private handlePermission(
    toolName: string,
    _toolInput: Record<string, unknown>,
    _opts: { signal: AbortSignal },
  ): Promise<PermissionResult> {
    // Find the sessionId — use the first active session (in practice, permission
    // callbacks are per-query and we'll have the session context from the pump)
    const sessionId = this.activePermissionSessionId ?? '';

    const requestId = crypto.randomUUID();

    this.emit('event', {
      type: 'permission_request',
      sessionId,
      requestId,
      toolTitle: toolName,
      options: [
        { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
        { optionId: 'allow_always', name: 'Always allow', kind: 'allow_always' },
        { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
      ],
    } satisfies AgentStreamEvent);

    return new Promise<PermissionResult>((resolve) => {
      const timer = setTimeout(() => {
        this.pendingPermissions.delete(requestId);
        resolve({ behavior: 'deny', message: 'Permission request timed out' });
        console.log(`[claude-sdk] Permission request ${requestId} timed out — auto-denied`);
      }, this.config.timeout * 1000);

      this.pendingPermissions.set(requestId, { resolve, timer });
    });
  }

  // Track which session is currently processing a permission request
  private activePermissionSessionId: string | null = null;

  respondPermission(requestId: string, optionId: string): boolean {
    const pending = this.pendingPermissions.get(requestId);
    if (!pending) return false;

    if (pending.timer) clearTimeout(pending.timer);
    this.pendingPermissions.delete(requestId);

    if (optionId === 'deny') {
      pending.resolve({ behavior: 'deny', message: 'User denied permission' });
    } else {
      pending.resolve({ behavior: 'allow' });
    }

    return true;
  }

  // ── Message Pump ──

  private async runPump(
    q: Query,
    session: ClaudeSession,
    resolveSessionId?: (id: string) => void,
  ): Promise<void> {
    try {
      for await (const message of q) {
        this.routeMessage(message, session, resolveSessionId);
        // Once we've resolved sessionId, clear the callback
        if (resolveSessionId && session.sessionId) {
          resolveSessionId = undefined;
        }
      }
    } catch (err) {
      if ((err as Error).name !== 'AbortError') {
        console.error(`[claude-sdk] Pump error for ${session.sessionId}: ${(err as Error).message}`);
        this.emit('event', {
          type: 'error',
          sessionId: session.sessionId || null,
          message: `Session error: ${(err as Error).message}`,
        } satisfies AgentStreamEvent);
      }
    }
  }

  private routeMessage(
    message: SDKMessage,
    session: ClaudeSession,
    resolveSessionId?: (id: string) => void,
  ): void {
    switch (message.type) {
      case 'system': {
        const sys = message as SDKSystemMessage;
        if (sys.subtype === 'init' && sys.session_id) {
          session.sessionId = sys.session_id;
          resolveSessionId?.(sys.session_id);
        }
        break;
      }

      case 'stream_event': {
        const partial = message as SDKPartialAssistantMessage;
        this.activePermissionSessionId = session.sessionId;
        this.handleStreamEvent(partial, session.sessionId);
        break;
      }

      case 'assistant': {
        // Full assistant message — can appear during resume pump
        const assistantMsg = message as SDKAssistantMessage;
        if (assistantMsg.message?.content) {
          for (const block of assistantMsg.message.content) {
            if (block.type === 'text') {
              this.emit('event', {
                type: 'text',
                sessionId: session.sessionId,
                content: block.text,
              } satisfies AgentStreamEvent);
            } else if (block.type === 'tool_use') {
              this.emit('event', {
                type: 'tool_call',
                sessionId: session.sessionId,
                toolCallId: block.id,
                title: block.name,
                status: 'completed',
              } satisfies AgentStreamEvent);
            }
          }
        }
        break;
      }

      case 'user': {
        const userMsg = message as SDKUserMessage | SDKUserMessageReplay;
        if ('isReplay' in userMsg && userMsg.isReplay) {
          const text = typeof userMsg.message.content === 'string'
            ? userMsg.message.content
            : '';
          if (text) {
            this.emit('event', {
              type: 'user_text',
              sessionId: session.sessionId,
              content: text,
              replay: true,
            } satisfies AgentStreamEvent);
          }
        }
        break;
      }

      case 'result': {
        const result = message as SDKResultMessage;
        this.emit('event', {
          type: 'usage',
          sessionId: session.sessionId,
          inputTokens: result.usage.input_tokens,
          outputTokens: result.usage.output_tokens,
        } satisfies AgentStreamEvent);

        this.emit('event', {
          type: 'turn_end',
          sessionId: session.sessionId,
          stopReason: result.stop_reason ?? (result.is_error ? 'error' : 'end_turn'),
        } satisfies AgentStreamEvent);
        break;
      }

      default:
        break;
    }
  }

  private handleStreamEvent(
    partial: SDKPartialAssistantMessage,
    sessionId: string,
  ): void {
    const event = partial.event;

    switch (event.type) {
      case 'content_block_delta': {
        const delta = event.delta;
        if (delta.type === 'text_delta') {
          this.emit('event', {
            type: 'text',
            sessionId,
            content: delta.text,
          } satisfies AgentStreamEvent);
        } else if (delta.type === 'input_json_delta') {
          // Tool input streaming — emit as tool_call_update
          // The tool_call_id comes from the content block start
        }
        break;
      }

      case 'content_block_start': {
        const block = event.content_block;
        if (block.type === 'tool_use') {
          this.emit('event', {
            type: 'tool_call',
            sessionId,
            toolCallId: block.id,
            title: block.name,
            status: 'running',
          } satisfies AgentStreamEvent);
        }
        break;
      }

      case 'content_block_stop': {
        // Tool execution completed — emit update
        // We don't have the tool_call_id here directly, but the index maps to the block
        break;
      }

      case 'message_start':
      case 'message_delta':
      case 'message_stop':
        // Message-level events — usage is handled in result
        break;

      default:
        break;
    }
  }

  // ── Introspection ──

  isAgentRunning(_agent: string): boolean {
    return this.sessions.size > 0;
  }

  getSessionAgent(sessionId: string): string | null {
    return this.sessions.has(sessionId) ? 'claude' : null;
  }
}
