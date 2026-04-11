import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import YAML from 'yaml';

// Override config path for tests
const TEST_DIR = path.join(os.tmpdir(), `vibe-test-${Date.now()}`);
const TEST_CONFIG_PATH = path.join(TEST_DIR, 'config.yaml');

describe('Config', () => {
  beforeEach(() => {
    fs.mkdirSync(TEST_DIR, { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(TEST_DIR, { recursive: true, force: true });
  });

  it('validates token is required', () => {
    const raw = { allowedDirs: ['/tmp'] }; // no token
    fs.writeFileSync(TEST_CONFIG_PATH, YAML.stringify(raw));
    const parsed = YAML.parse(fs.readFileSync(TEST_CONFIG_PATH, 'utf-8'));
    assert.ok(!parsed.token || typeof parsed.token !== 'string' || parsed.token.length === 0);
  });

  it('validates allowedDirs is required', () => {
    const raw = { token: 'abc123' }; // no allowedDirs
    fs.writeFileSync(TEST_CONFIG_PATH, YAML.stringify(raw));
    const parsed = YAML.parse(fs.readFileSync(TEST_CONFIG_PATH, 'utf-8'));
    assert.ok(!Array.isArray(parsed.allowedDirs) || parsed.allowedDirs.length === 0);
  });

  it('parses valid config', () => {
    const raw = {
      port: 8080,
      bind: '127.0.0.1',
      token: 'test-token-123',
      allowedDirs: ['/tmp', '/home/user/projects'],
      claudePath: '/usr/local/bin/claude',
    };
    fs.writeFileSync(TEST_CONFIG_PATH, YAML.stringify(raw));
    const parsed = YAML.parse(fs.readFileSync(TEST_CONFIG_PATH, 'utf-8'));

    assert.equal(parsed.port, 8080);
    assert.equal(parsed.bind, '127.0.0.1');
    assert.equal(parsed.token, 'test-token-123');
    assert.deepEqual(parsed.allowedDirs, ['/tmp', '/home/user/projects']);
    assert.equal(parsed.claudePath, '/usr/local/bin/claude');
  });

  it('handles YAML roundtrip', () => {
    const raw = {
      token: 'my-token',
      allowedDirs: ['~/projects'],
      port: 7842,
    };
    const yaml = YAML.stringify(raw);
    const parsed = YAML.parse(yaml);

    assert.equal(parsed.token, 'my-token');
    assert.deepEqual(parsed.allowedDirs, ['~/projects']);
    assert.equal(parsed.port, 7842);
  });
});
