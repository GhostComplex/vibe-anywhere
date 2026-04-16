import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { ClaudeProvider, type ClaudeProviderConfig } from '../providers/claude-provider.js';

// ── Mock helpers ──

function makeConfig(overrides: Partial<ClaudeProviderConfig> = {}): ClaudeProviderConfig {
  return {
    permissionMode: 'default',
    timeout: 5,
    ...overrides,
  };
}

describe('ClaudeProvider', () => {
  let provider: ClaudeProvider;

  beforeEach(() => {
    provider = new ClaudeProvider(makeConfig());
  });

  afterEach(async () => {
    await provider.shutdown();
  });

  describe('construction', () => {
    it('creates with default config', () => {
      assert.ok(provider instanceof EventEmitter);
    });

    it('exposes provider name', () => {
      assert.equal(provider.provider, 'claude-sdk');
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
      assert.equal(provider.respondPermission('unknown-id', 'allow'), false);
    });
  });

  describe('ensureAgent', () => {
    it('resolves without error (no persistent process)', async () => {
      await provider.ensureAgent('claude');
    });
  });

  describe('prompt', () => {
    it('throws for unknown session', async () => {
      await assert.rejects(
        () => provider.prompt('claude', 'nonexistent', 'hello'),
        { message: /not found/ },
      );
    });
  });

  describe('cancel', () => {
    it('does not throw for unknown session', async () => {
      await provider.cancel('claude', 'nonexistent');
    });
  });

  describe('shutdown', () => {
    it('completes cleanly with no sessions', async () => {
      await provider.shutdown();
    });
  });
});
