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
