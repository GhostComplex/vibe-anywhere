// Client → Daemon messages

export interface SessionCreateMsg {
  type: 'session/create';
  cwd: string;
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

export type ClientMessage =
  | SessionCreateMsg
  | SessionListMsg
  | SessionResumeMsg
  | SessionMessageMsg
  | SessionDestroyMsg;

// Daemon → Client messages

export interface SessionCreatedMsg {
  type: 'session/created';
  sessionId: string;
  cwd: string;
}

export interface SessionListResponseMsg {
  type: 'session/list';
  sessions: Array<{ sessionId: string; cwd: string }>;
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
}

export type DaemonMessage =
  | SessionCreatedMsg
  | SessionListResponseMsg
  | StreamTextMsg
  | StreamToolUseMsg
  | StreamToolResultMsg
  | StreamEndMsg
  | ErrorMsg;

// Type guards

export function isClientMessage(msg: unknown): msg is ClientMessage {
  return typeof msg === 'object' && msg !== null && 'type' in msg &&
    typeof (msg as { type: unknown }).type === 'string' &&
    [
      'session/create', 'session/list', 'session/resume',
      'session/message', 'session/destroy',
    ].includes((msg as { type: string }).type);
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
