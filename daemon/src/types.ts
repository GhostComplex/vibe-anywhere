// ── Client → Daemon messages ──

export interface SessionCreateMsg {
  type: 'session/create';
  cwd: string;
  agent?: string; // defaults to config.defaultAgent
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

export interface ErrorMsg {
  type: 'error';
  message: string;
  sessionId?: string;
}

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

export interface HelloMsg {
  type: 'hello';
  version: number;
}

export type DaemonMessage =
  | HelloMsg
  | SessionCreatedMsg
  | SessionDestroyedMsg
  | SessionListResponseMsg
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
  'session/cancel', 'session/set-mode', 'session/set-model',
  'permission/respond',
];

export function isClientMessage(msg: unknown): msg is ClientMessage {
  return typeof msg === 'object' && msg !== null && 'type' in msg &&
    typeof (msg as { type: unknown }).type === 'string' &&
    VALID_CLIENT_TYPES.includes((msg as { type: string }).type);
}
