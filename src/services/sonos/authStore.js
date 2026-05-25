const TOKEN_KEY = 'sonos_access_token';
const REFRESH_TOKEN_KEY = 'sonos_refresh_token';
const HOUSEHOLD_KEY = 'sonos_selected_household';

export function getStoredToken() {
  return localStorage.getItem(TOKEN_KEY);
}

export function getStoredRefreshToken() {
  return localStorage.getItem(REFRESH_TOKEN_KEY);
}

export function storeTokens(accessToken, refreshToken) {
  if (accessToken) localStorage.setItem(TOKEN_KEY, accessToken);
  if (refreshToken === undefined) return;
  if (refreshToken) {
    localStorage.setItem(REFRESH_TOKEN_KEY, refreshToken);
  } else {
    localStorage.removeItem(REFRESH_TOKEN_KEY);
  }
}

export function clearTokens() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
  localStorage.removeItem(HOUSEHOLD_KEY);
}

export function getSelectedHouseholdID() {
  return localStorage.getItem(HOUSEHOLD_KEY);
}

export function setSelectedHouseholdID(id) {
  localStorage.setItem(HOUSEHOLD_KEY, id);
}
