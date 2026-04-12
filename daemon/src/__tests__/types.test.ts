import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { isClientMessage } from '../types.js';

describe('isClientMessage', () => {
  it('accepts session/create', () => {
    assert.ok(isClientMessage({ type: 'session/create', cwd: '/tmp' }));
  });

  it('accepts session/list', () => {
    assert.ok(isClientMessage({ type: 'session/list' }));
  });

  it('accepts session/resume', () => {
    assert.ok(isClientMessage({ type: 'session/resume', sessionId: 'abc' }));
  });

  it('accepts session/message', () => {
    assert.ok(isClientMessage({ type: 'session/message', sessionId: 'abc', content: 'hi' }));
  });

  it('accepts session/destroy', () => {
    assert.ok(isClientMessage({ type: 'session/destroy', sessionId: 'abc' }));
  });

  it('accepts session/cancel', () => {
    assert.ok(isClientMessage({ type: 'session/cancel', sessionId: 'abc' }));
  });

  it('accepts session/set-mode', () => {
    assert.ok(isClientMessage({ type: 'session/set-mode', sessionId: 'abc', mode: 'plan' }));
  });

  it('accepts session/set-model', () => {
    assert.ok(isClientMessage({ type: 'session/set-model', sessionId: 'abc', model: 'opus' }));
  });

  it('accepts permission/respond', () => {
    assert.ok(isClientMessage({ type: 'permission/respond', sessionId: 'abc', requestId: 'r1', optionId: 'o1' }));
  });

  it('rejects unknown type', () => {
    assert.ok(!isClientMessage({ type: 'unknown' }));
  });

  it('rejects null', () => {
    assert.ok(!isClientMessage(null));
  });

  it('rejects non-object', () => {
    assert.ok(!isClientMessage('string'));
  });

  it('rejects missing type', () => {
    assert.ok(!isClientMessage({ cwd: '/tmp' }));
  });
});
