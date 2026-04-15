import { EventEmitter } from 'node:events';

// ── Stream events emitted by providers ──

export type AgentStreamEvent =
  | { type: 'text'; sessionId: string; content: string; replay?: boolean }
  | { type: 'user_text'; sessionId: string; content: string; replay?: boolean }
  | { type: 'tool_call'; sessionId: string; toolCallId: string; title: string; status: string; input?: Record<string, unknown>; replay?: boolean }
  | { type: 'tool_call_update'; sessionId: string; toolCallId: string; status: string; content?: string; replay?: boolean }
  | { type: 'permission_request'; sessionId: string; requestId: string; toolTitle: string; options: Array<{ optionId: string; name: string; kind: string }> }
  | { type: 'usage'; sessionId: string; inputTokens: number; outputTokens: number }
  | { type: 'turn_end'; sessionId: string; stopReason: string }
  | { type: 'replay_end'; sessionId: string }
  | { type: 'error'; sessionId: string | null; message: string }
  | { type: 'agent_exit'; agent: string; code: number | null };

// ── Host session info ──

export interface HostSessionInfo {
  sessionId: string;
  cwd: string;
  title?: string;
  updatedAt?: string;
}

// ── AgentClient interface ──
// TODO(#139): Remove `agent: string` parameter from methods once each provider
// handles a single agent type. Currently kept for backward compat with AcpProvider
// which manages multiple agent processes internally. The registry should be the
// sole routing layer — callers do `registry.getOrThrow(agent).createSession(cwd)`
// instead of passing `agent` through twice.

export interface AgentClient extends EventEmitter {
  readonly provider: string;

  // Lifecycle
  ensureAgent(agent: string): Promise<void>;
  shutdown(): Promise<void>;

  // Sessions
  createSession(agent: string, cwd: string): Promise<{ sessionId: string }>;
  loadSession(agent: string, sessionId: string, cwd: string): Promise<void>;
  closeSession(agent: string, sessionId: string): Promise<void>;
  listHostSessions(agent: string): Promise<{ sessions: HostSessionInfo[]; supported: boolean }>;
  resumeHostSession(agent: string, sessionId: string, cwd: string): Promise<{ sessionId: string }>;

  // Interaction
  prompt(agent: string, sessionId: string, content: string): Promise<void>;
  cancel(agent: string, sessionId: string): Promise<void>;

  // Controls
  setMode(agent: string, sessionId: string, mode: string): Promise<void>;
  setModel(agent: string, sessionId: string, model: string): Promise<void>;

  // Permissions
  respondPermission(requestId: string, optionId: string): boolean;

  // Introspection
  isAgentRunning(agent: string): boolean;
  getSessionAgent(sessionId: string): string | null;
}
