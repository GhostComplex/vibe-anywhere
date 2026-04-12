import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { AcpManager, type AcpManagerConfig, type AcpManagerEvent } from '../acp-manager.js';

// ── Mock helpers ──

function makeConfig(overrides: Partial<AcpManagerConfig> = {}): AcpManagerConfig {
  return {
    acpxPath: 'npx',
    permissionMode: 'prompt',
    timeout: 5,
    ...overrides,
  };
}

describe('AcpManager', () => {
  let manager: AcpManager;

  beforeEach(() => {
    manager = new AcpManager(makeConfig());
  });

  afterEach(async () => {
    await manager.shutdown();
  });

  describe('construction', () => {
    it('creates with default config', () => {
      assert.ok(manager instanceof EventEmitter);
    });

    it('reports no agents running initially', () => {
      assert.ok(!manager.isAgentRunning('claude'));
    });

    it('returns null for unknown session agent', () => {
      assert.equal(manager.getSessionAgent('nonexistent'), null);
    });
  });

  describe('respondPermission', () => {
    it('returns false for unknown requestId', () => {
      assert.equal(manager.respondPermission('unknown-id', 'option-1'), false);
    });
  });

  describe('prompt without agent', () => {
    it('throws when agent not running', async () => {
      await assert.rejects(
        () => manager.prompt('claude', 'session-1', 'hello'),
        { message: /Agent "claude" not running/ },
      );
    });
  });

  describe('cancel without agent', () => {
    it('does not throw when agent not running', async () => {
      // cancel is fire-and-forget, should not throw
      await manager.cancel('claude', 'session-1');
    });
  });

  describe('setMode without agent', () => {
    it('throws when agent not running', async () => {
      await assert.rejects(
        () => manager.setMode('claude', 'session-1', 'plan'),
        { message: /Agent "claude" not running/ },
      );
    });
  });

  describe('setModel without agent', () => {
    it('throws when agent not running', async () => {
      await assert.rejects(
        () => manager.setModel('claude', 'session-1', 'opus'),
        { message: /Agent "claude" not running/ },
      );
    });
  });

  describe('shutdown', () => {
    it('completes cleanly with no agents', async () => {
      await manager.shutdown();
      // Should not throw
      assert.ok(true);
    });

    it('can be called multiple times', async () => {
      await manager.shutdown();
      await manager.shutdown();
      assert.ok(true);
    });
  });

  describe('event emission', () => {
    it('is an EventEmitter', () => {
      const events: AcpManagerEvent[] = [];
      manager.on('event', (e: AcpManagerEvent) => events.push(e));
      // Manually emit to verify wiring
      manager.emit('event', { type: 'error', sessionId: null, message: 'test' } satisfies AcpManagerEvent);
      assert.equal(events.length, 1);
      assert.equal(events[0].type, 'error');
    });
  });
});

describe('AcpManager auto-permission modes', () => {
  it('approve-all config is stored', () => {
    const config = makeConfig({ permissionMode: 'approve-all' });
    assert.equal(config.permissionMode, 'approve-all');
  });

  it('deny-all config is stored', () => {
    const config = makeConfig({ permissionMode: 'deny-all' });
    assert.equal(config.permissionMode, 'deny-all');
  });
});
