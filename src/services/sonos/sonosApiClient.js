import {
  clearTokens,
  getSelectedHouseholdID,
  getStoredRefreshToken,
  getStoredToken,
  storeTokens,
} from './authStore.js';

let inflightRefresh = null;

async function callProxy(token, path, method, body, householdId) {
  return fetch('/api/sonos', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path, method, body, token, householdId }),
  });
}

export async function refreshAccessToken() {
  if (inflightRefresh) return inflightRefresh;
  const refreshToken = getStoredRefreshToken();
  if (!refreshToken) return null;

  inflightRefresh = (async () => {
    try {
      const res = await fetch('/api/sonos/refresh', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });
      if (!res.ok) return null;
      const data = await res.json();
      if (!data.access_token) return null;
      storeTokens(data.access_token, data.refresh_token);
      return data.access_token;
    } catch {
      return null;
    } finally {
      inflightRefresh = null;
    }
  })();

  return inflightRefresh;
}

export async function sonosAPI(path, method = 'GET', body = null) {
  let token = getStoredToken();
  if (!token) throw new Error('Not authenticated. Please sign in to Sonos.');

  const householdId = getSelectedHouseholdID();

  let res = await callProxy(token, path, method, body, householdId);

  if (res.status === 401) {
    const refreshed = await refreshAccessToken();
    if (refreshed) {
      res = await callProxy(refreshed, path, method, body, householdId);
    }
    if (res.status === 401) {
      clearTokens();
      throw new Error('Sonos session expired. Please sign in again.');
    }
  }

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || `Sonos API error: ${res.status}`);
  }

  const text = await res.text();
  return text ? JSON.parse(text) : {};
}
