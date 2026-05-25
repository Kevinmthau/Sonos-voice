import assert from 'node:assert/strict';
import test from 'node:test';
import { getStoredRefreshToken, storeTokens } from '../src/services/sonos/authStore.js';

const originalLocalStorage = global.localStorage;

function makeLocalStorage(seed = {}) {
  const values = new Map(Object.entries(seed));
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
  };
}

test.afterEach(() => {
  global.localStorage = originalLocalStorage;
});

test('storeTokens clears a stale refresh token when the callback omits one', () => {
  global.localStorage = makeLocalStorage({
    sonos_access_token: 'old-access-token',
    sonos_refresh_token: 'old-refresh-token',
  });

  storeTokens('new-access-token', null);

  assert.equal(global.localStorage.getItem('sonos_access_token'), 'new-access-token');
  assert.equal(getStoredRefreshToken(), null);
});

test('storeTokens preserves the refresh token when the argument is omitted', () => {
  global.localStorage = makeLocalStorage({
    sonos_access_token: 'old-access-token',
    sonos_refresh_token: 'old-refresh-token',
  });

  storeTokens('new-access-token');

  assert.equal(global.localStorage.getItem('sonos_access_token'), 'new-access-token');
  assert.equal(getStoredRefreshToken(), 'old-refresh-token');
});
