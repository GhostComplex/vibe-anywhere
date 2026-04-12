// ── Client → Daemon messages ──

// v1 messages (kept for backward compat)

export interface SessionCreateMsg {
  type: 'session/create';
  cwd: string;
  agent?: string; // v2: optional agent, defaults to config.defaultAgent
}

export interface SessionListMsg {
  type: 'session/list';
}

export interface SessionResumeMsg {
  type: 'session/resume';
  sessionId: string;
}

export interface SessionMessageMsg {
  type: 'session/message';
  sessionId: string;
  content: string;
}

export interface SessionDestroyMsg {
  type: 'session/destroy';
  sessionId: string;
}

// v2 messages

export interface SessionCancelMsg {
  type: 'session/cancel';
  sessionId: string;
}

export interface SessionSetModeMsg {
  type: 'session/set-mode';
  sessionId: string;
  mode: string;
}

export interface SessionSetModelMsg {
  type: 'session/set-model';
  sessionId: string;
  model: string;
}

export interface PermissionRespondMsg {
  type: 'permission/respond';
  sessionId: string;
  requestId: string;
  optionId: string;
}

export type ClientMessage =
  | SessionCreateMsg
  | SessionListMsg
  | SessionResumeMsg
  | SessionMessageMsg
  | SessionDestroyMsg
  | SessionCancelMsg
  | SessionSetModeMsg
  | SessionSetModelMsg
  | PermissionRespondMsg;

// ── Daemon → Client messages ──

// v1 messages (kept for backward compat)

export interface SessionCreatedMsg {
  type: 'session/created';
  sessionId: string;
  cwd: string;
}

export interface SessionDestroyedMsg {
  type: 'session/destroyed';
  sessionId: string;
}

export interface SessionListResponseMsg {
  type: 'session/list';
  sessions: Array<{ sessionId: string; cwd: string; agent?: string }>;
}

export interface StreamTextMsg {
  type: 'stream/text';
  sessionId: string;
  content: string;
}

export interface StreamToolUseMsg {
  type: 'stream/tool_use';
  sessionId: string;
  tool: string;
  input: Record<string, unknown>;
}

export interface StreamToolResultMsg {
  type: 'stream/tool_result';
  sessionId: string;
  tool: string;
  output: string;
}

export interface StreamEndMsg {
  type: 'stream/end';
  sessionId: string;
  result: string;
}

export interface ErrorMsg {
  type: 'error';
  message: string;
  sessionId?: string;
}

// v2 event messages

export interface EventTextMsg {
  type: 'event/text';
  sessionId: string;
  content: string;
}

export interface EventToolCallMsg {
  type: 'event/tool_call';
  sessionId: string;
  toolCallId: string;
  tool: string;
  status: string;
  input?: Record<string, unknown>;
  content?: string;
}

export interface EventToolCallUpdateMsg {
  type: 'event/tool_call_update';
  sessionId: string;
  toolCallId: string;
  status?: string;
  content?: string;
}

export interface EventPermissionRequestMsg {
  type: 'event/permission_request';
  sessionId: string;
  requestId: string;
  tool: string;
  options: Array<{ optionId: string; name: string; kind: string }>;
}

export interface EventUsageMsg {
  type: 'event/usage';
  sessionId: string;
  inputTokens: number;
  outputTokens: number;
}

export interface EventTurnEndMsg {
  type: 'event/turn_end';
  sessionId: string;
  stopReason: string;
}

export interface EventErrorMsg {
  type: 'event/error';
  sessionId: string;
  message: string;
}

export interface EventSessionInfoMsg {
  type: 'event/session_info';
  sessionId: string;
  agent: string;
  models?: string[];
  modes?: string[];
}

export type DaemonMessage =
  | SessionCreatedMsg
  | SessionDestroyedMsg
  | SessionListResponseMsg
  | StreamTextMsg
  | StreamToolUseMsg
  | StreamToolResultMsg
  | StreamEndMsg
  | ErrorMsg
  | EventTextMsg
  | EventToolCallMsg
  | EventToolCallUpdateMsg
  | EventPermissionRequestMsg
  | EventUsageMsg
  | EventTurnEndMsg
  | EventErrorMsg
  | EventSessionInfoMsg;

// ── Type guards ──

const VALID_CLIENT_TYPES = [
  'session/create', 'session/list', 'session/resume',
  'session/message', 'session/destroy',
  // v2
  'session/cancel', 'session/set-mode', 'session/set-model',
  'permission/respond',
];

export function isClientMessage(msg: unknown): msg is ClientMessage {
  return typeof msg === 'object' && msg !== null && 'type' in msg &&
    typeof (msg as { type: unknown }).type === 'string' &&
    VALID_CLIENT_TYPES.includes((msg as { type: string }).type);
}

export function isSessionCreate(msg: ClientMessage): msg is SessionCreateMsg {
  return msg.type === 'session/create';
}

export function isSessionList(msg: ClientMessage): msg is SessionListMsg {
  return msg.type === 'session/list';
}

export function isSessionResume(msg: ClientMessage): msg is SessionResumeMsg {
  return msg.type === 'session/resume';
}

export function isSessionMessage(msg: ClientMessage): msg is SessionMessageMsg {
  return msg.type === 'session/message';
}

export function isSessionDestroy(msg: ClientMessage): msg is SessionDestroyMsg {
  return msg.type === 'session/destroy';
}
