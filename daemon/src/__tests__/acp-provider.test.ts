import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { AcpProvider, type AcpProviderConfig } from '../providers/acp-provider.js';
import type { AgentStreamEvent } from '../providers/types.js';

// ── Mock helpers ──

function makeConfig(overrides: Partial<AcpProviderConfig> = {}): AcpProviderConfig {
  return {
    acpxPath: 'npx',
    permissionMode: 'prompt',
    timeout: 5,
    ...overrides,
  };
}

describe('AcpProvider', () => {
  let provider: AcpProvider;

  beforeEach(() => {
    provider = new AcpProvider(makeConfig());
  });

  afterEach(async () => {
    await provider.shutdown();
  });

  describe('construction', () => {
    it('creates with default config', () => {
      assert.ok(provider instanceof EventEmitter);
    });

    it('exposes provider name', () => {
      assert.equal(provider.provider, 'acp');
    });

    it('reports no agents running initially', () => {
      assert.ok(!provider.isAgentRunning('claude'));
    });

    it('returns null for unknown session agent', () => {
      assert.equal(provider.getSessionAgent('nonexistent'), null);
    });
  });

  describe('respondPermission', () => {
    it('returns false for unknown requestId', () => {
      assert.equal(provider.respondPermission('unknown-id', 'option-1'), false);
    });
  });

  describe('prompt without agent', () => {
    it('throws when agent not running', async () => {
      await assert.rejects(
        () => provider.prompt('claude', 'session-1', 'hello'),
        { message: /Agent "claude" not running/ },
      );
    });
  });

  describe('cancel without agent', () => {
    it('does not throw when agent not running', async () => {
      // cancel is fire-and-forget, should not throw
      await provider.cancel('claude', 'session-1');
    });
  });

  describe('setMode without agent', () => {
    it('throws when agent not running', async () => {
      await assert.rejects(
        () => provider.setMode('claude', 'session-1', 'plan'),
        { message: /Agent "claude" not running/ },
      );
    });
  });

  describe('setModel without agent', () => {
    it('throws when agent not running', async () => {
      await assert.rejects(
        () => provider.setModel('claude', 'session-1', 'opus'),
        { message: /Agent "claude" not running/ },
      );
    });
  });

  describe('shutdown', () => {
    it('completes cleanly with no agents', async () => {
      await provider.shutdown();
      // Should not throw
      assert.ok(true);
    });

    it('can be called multiple times', async () => {
      await provider.shutdown();
      await provider.shutdown();
      assert.ok(true);
    });
  });

  describe('event emission', () => {
    it('is an EventEmitter', () => {
      const events: AgentStreamEvent[] = [];
      provider.on('event', (e: AgentStreamEvent) => events.push(e));
      // Manually emit to verify wiring
      provider.emit('event', { type: 'error', sessionId: null, message: 'test' } satisfies AgentStreamEvent);
      assert.equal(events.length, 1);
      assert.equal(events[0].type, 'error');
    });
  });
});

describe('AcpProvider auto-permission modes', () => {
  it('approve-all config is stored', () => {
    const config = makeConfig({ permissionMode: 'approve-all' });
    assert.equal(config.permissionMode, 'approve-all');
  });

  it('deny-all config is stored', () => {
    const config = makeConfig({ permissionMode: 'deny-all' });
    assert.equal(config.permissionMode, 'deny-all');
  });
});
