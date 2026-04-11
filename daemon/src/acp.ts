import { spawn, type ChildProcess } from 'node:child_process';
import { createInterface } from 'node:readline';
import { EventEmitter } from 'node:events';

export interface AcpBridgeOptions {
  claudePath: string;
  cwd: string;
}

export type AcpEvent =
  | { type: 'init'; sessionId: string }
  | { type: 'text'; content: string }
  | { type: 'tool_use'; tool: string; toolUseId: string; input: Record<string, unknown> }
  | { type: 'tool_result'; tool: string; output: string }
  | { type: 'turn_end'; result: string }
  | { type: 'error'; message: string }
  | { type: 'exit'; code: number | null };

export class AcpBridge extends EventEmitter {
  private process: ChildProcess | null = null;
  private sessionId: string | null = null;
  private _alive = false;
  // Track tool_use blocks by index for tool_result correlation
  private toolUseBlocks = new Map<number, { id: string; name: string; inputJson: string }>();

  get alive(): boolean {
    return this._alive;
  }

  get acpSessionId(): string | null {
    return this.sessionId;
  }

  start(opts: AcpBridgeOptions): void {
    if (this._alive) {
      throw new Error('ACP bridge already running');
    }

    const args = [
      '--print',
      '--output-format', 'stream-json',
      '--input-format', 'stream-json',
      '--verbose',
      '--permission-mode', 'bypassPermissions',
      '--include-partial-messages',
      '--bare',
    ];

    this.process = spawn(opts.claudePath, args, {
      cwd: opts.cwd,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    this._alive = true;

    const rl = createInterface({ input: this.process.stdout! });
    rl.on('line', (line) => this.handleLine(line));

    this.process.stderr?.on('data', (data: Buffer) => {
      const msg = data.toString().trim();
      if (msg) {
        console.error(`[acp:stderr] ${msg}`);
      }
    });

    this.process.on('close', (code) => {
      this._alive = false;
      this.process = null;
      this.emit('event', { type: 'exit', code } satisfies AcpEvent);
    });

    this.process.on('error', (err) => {
      this._alive = false;
      this.process = null;
      this.emit('event', { type: 'error', message: err.message } satisfies AcpEvent);
    });
  }

  sendMessage(content: string): void {
    if (!this.process?.stdin?.writable) {
      throw new Error('ACP bridge not running');
    }
    const msg = JSON.stringify({
      type: 'user',
      message: { role: 'user', content },
    });
    this.process.stdin.write(msg + '\n');
  }

  destroy(): void {
    if (this.process) {
      this.process.kill('SIGTERM');
      // Force kill after 3s if still alive
      const forceKill = setTimeout(() => {
        if (this.process) {
          this.process.kill('SIGKILL');
        }
      }, 3000);
      this.process.on('close', () => clearTimeout(forceKill));
    }
  }

  private handleLine(line: string): void {
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(line) as Record<string, unknown>;
    } catch {
      return;
    }

    const msgType = data.type as string;

    switch (msgType) {
      case 'system': {
        if (data.subtype === 'init') {
          this.sessionId = data.session_id as string;
          this.toolUseBlocks.clear();
          this.emit('event', {
            type: 'init',
            sessionId: this.sessionId,
          } satisfies AcpEvent);
        }
        break;
      }

      case 'stream_event': {
        this.handleStreamEvent(data.event as Record<string, unknown>);
        break;
      }

      case 'result': {
        const result = (data.result as string) ?? '';
        this.emit('event', { type: 'turn_end', result } satisfies AcpEvent);
        break;
      }
    }
  }

  private handleStreamEvent(event: Record<string, unknown>): void {
    const eventType = event.type as string;

    switch (eventType) {
      case 'content_block_start': {
        const block = event.content_block as Record<string, unknown>;
        const index = event.index as number;
        if (block?.type === 'tool_use') {
          this.toolUseBlocks.set(index, {
            id: block.id as string,
            name: block.name as string,
            inputJson: '',
          });
        }
        break;
      }

      case 'content_block_delta': {
        const delta = event.delta as Record<string, unknown>;
        const index = event.index as number;
        if (delta?.type === 'text_delta') {
          this.emit('event', {
            type: 'text',
            content: delta.text as string,
          } satisfies AcpEvent);
        } else if (delta?.type === 'input_json_delta') {
          // Accumulate tool input JSON
          const toolBlock = this.toolUseBlocks.get(index);
          if (toolBlock) {
            toolBlock.inputJson += delta.partial_json as string;
          }
        }
        break;
      }

      case 'content_block_stop': {
        const index = event.index as number;
        const toolBlock = this.toolUseBlocks.get(index);
        if (toolBlock) {
          let input: Record<string, unknown> = {};
          try {
            input = JSON.parse(toolBlock.inputJson) as Record<string, unknown>;
          } catch { /* empty */ }
          this.emit('event', {
            type: 'tool_use',
            tool: toolBlock.name,
            toolUseId: toolBlock.id,
            input,
          } satisfies AcpEvent);
          this.toolUseBlocks.delete(index);
        }
        break;
      }
    }
  }
}
