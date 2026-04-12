import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server as HttpServer } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import { startServer, send, sendError } from '../server.js';
import type { Config } from '../config.js';
import type { ClientMessage, DaemonMessage } from '../types.js';

const TEST_TOKEN = 'test-token-for-ci';
const TEST_PORT = 18742;

function makeConfig(overrides: Partial<Config> = {}): Config {
  return {
    port: TEST_PORT,
    bind: '127.0.0.1',
    token: TEST_TOKEN,
    allowedDirs: ['/tmp'],
    defaultAgent: 'claude',
    acpx: {
      path: 'npx',
      permissionMode: 'prompt',
      timeout: 120,
    },
    ...overrides,
  };
}

describe('WebSocket Server Auth', () => {
  let server: { close(): Promise<void> };

  afterEach(async () => {
    if (server) await server.close();
  });

  it('rejects connection without token', async () => {
    server = startServer({
      config: makeConfig(),
      onMessage: () => {},
    });

    await new Promise((r) => setTimeout(r, 200));

    const result = await new Promise<string>((resolve) => {
      const ws = new WebSocket(`ws://127.0.0.1:${TEST_PORT}`);
      ws.on('error', (err) => resolve('rejected'));
      ws.on('open', () => resolve('connected'));
      setTimeout(() => resolve('timeout'), 3000);
    });

    assert.equal(result, 'rejected');
  });

  it('rejects connection with wrong token', async () => {
    server = startServer({
      config: makeConfig(),
      onMessage: () => {},
    });

    await new Promise((r) => setTimeout(r, 200));

    const result = await new Promise<string>((resolve) => {
      const ws = new WebSocket(`ws://127.0.0.1:${TEST_PORT}`, {
        headers: { Authorization: 'Bearer wrong-token' },
      });
      ws.on('error', () => resolve('rejected'));
      ws.on('open', () => resolve('connected'));
      setTimeout(() => resolve('timeout'), 3000);
    });

    assert.equal(result, 'rejected');
  });

  it('accepts connection with valid token', async () => {
    server = startServer({
      config: makeConfig(),
      onMessage: () => {},
    });

    await new Promise((r) => setTimeout(r, 200));

    const result = await new Promise<string>((resolve) => {
      const ws = new WebSocket(`ws://127.0.0.1:${TEST_PORT}`, {
        headers: { Authorization: `Bearer ${TEST_TOKEN}` },
      });
      ws.on('error', () => resolve('rejected'));
      ws.on('open', () => {
        ws.close();
        resolve('connected');
      });
      setTimeout(() => resolve('timeout'), 3000);
    });

    assert.equal(result, 'connected');
  });

  it('dispatches valid messages to onMessage', async () => {
    const received: ClientMessage[] = [];

    server = startServer({
      config: makeConfig(),
      onMessage: (_ws, msg) => received.push(msg),
    });

    await new Promise((r) => setTimeout(r, 200));

    const ws = new WebSocket(`ws://127.0.0.1:${TEST_PORT}`, {
      headers: { Authorization: `Bearer ${TEST_TOKEN}` },
    });

    await new Promise<void>((resolve) => {
      ws.on('open', () => {
        ws.send(JSON.stringify({ type: 'session/list' }));
        setTimeout(() => {
          ws.close();
          resolve();
        }, 200);
      });
    });

    assert.equal(received.length, 1);
    assert.equal(received[0].type, 'session/list');
  });

  it('returns error for invalid JSON', async () => {
    server = startServer({
      config: makeConfig(),
      onMessage: () => {},
    });

    await new Promise((r) => setTimeout(r, 200));

    const response = await new Promise<string>((resolve) => {
      const ws = new WebSocket(`ws://127.0.0.1:${TEST_PORT}`, {
        headers: { Authorization: `Bearer ${TEST_TOKEN}` },
      });
      ws.on('open', () => {
        ws.send('not json');
      });
      ws.on('message', (data) => {
        ws.close();
        resolve(data.toString());
      });
      setTimeout(() => resolve('timeout'), 3000);
    });

    const parsed = JSON.parse(response);
    assert.equal(parsed.type, 'error');
    assert.ok(parsed.message.includes('Invalid JSON'));
  });
});
