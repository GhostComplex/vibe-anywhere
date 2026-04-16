import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { CopilotProvider, type CopilotProviderConfig } from '../providers/copilot-provider.js';

// ── Mock helpers ──

function makeConfig(overrides: Partial<CopilotProviderConfig> = {}): CopilotProviderConfig {
  return {
    copilotPath: 'copilot',
    permissionMode: 'prompt',
    timeout: 5,
    ...overrides,
  };
}

describe('CopilotProvider', () => {
  let provider: CopilotProvider;

  beforeEach(() => {
    provider = new CopilotProvider(makeConfig());
  });

  afterEach(async () => {
    await provider.shutdown();
  });

  describe('construction', () => {
    it('creates with default config', () => {
      assert.ok(provider instanceof EventEmitter);
    });

    it('exposes provider name', () => {
      assert.equal(provider.provider, 'copilot');
    });

    it('reports no agents running initially', () => {
      assert.ok(!provider.isAgentRunning('copilot'));
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

  describe('prompt without process', () => {
    it('throws when process not running', async () => {
      await assert.rejects(
        () => provider.prompt('copilot', 'nonexistent', 'hello'),
        { message: /not running/ },
      );
    });
  });

  describe('cancel without process', () => {
    it('does not throw when process not running', async () => {
      await provider.cancel('copilot', 'nonexistent');
    });
  });

  describe('shutdown', () => {
    it('completes cleanly with no process', async () => {
      await provider.shutdown();
    });

    it('can be called multiple times', async () => {
      await provider.shutdown();
      await provider.shutdown();
    });
  });
});
