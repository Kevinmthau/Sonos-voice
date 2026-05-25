const assert = require("node:assert/strict");
const test = require("node:test");
const { createSignedState } = require("../netlify/functions/_sonos-oauth.js");
const { handler } = require("../netlify/functions/sonos-auth-callback.js");

const originalEnv = { ...process.env };
const originalFetch = global.fetch;

function resetEnvironment() {
  process.env = { ...originalEnv };
  process.env.SONOS_CLIENT_ID = "client-id";
  process.env.SONOS_CLIENT_SECRET = "client-secret";
  process.env.SONOS_STATE_SECRET = "state-secret";
  delete process.env.SONOS_WEB_CALLBACK_URL;
  delete process.env.SONOS_IOS_CALLBACK_URL;
}

function signedState(payload) {
  return createSignedState(process.env.SONOS_STATE_SECRET, payload);
}

function callbackEvent(path, queryStringParameters) {
  return {
    path,
    headers: { host: "example.netlify.app" },
    queryStringParameters,
  };
}

function locationURL(response) {
  assert.equal(response.statusCode, 302);
  return new URL(response.headers.Location);
}

test.beforeEach(() => {
  resetEnvironment();
  global.fetch = async () => ({
    ok: true,
    status: 200,
    json: async () => ({
      access_token: "access-token",
      refresh_token: "refresh-token",
      expires_in: 3600,
      scope: "playback-control-all",
    }),
  });
});

test.afterEach(() => {
  global.fetch = originalFetch;
  process.env = { ...originalEnv };
});

test("web OAuth success redirects to the web callback URL", async () => {
  const state = signedState({
    target: "web",
    redirectURI: "https://example.netlify.app/sonos/oauth/callback/web",
  });

  const response = await handler(callbackEvent("/sonos/oauth/callback/web", { code: "code", state }));
  const location = locationURL(response);

  assert.equal(location.origin, "https://example.netlify.app");
  assert.equal(location.pathname, "/");
  assert.equal(location.searchParams.get("access_token"), "access-token");
  assert.equal(location.searchParams.get("refresh_token"), "refresh-token");
  assert.equal(location.searchParams.get("expires_in"), "3600");
  assert.equal(location.searchParams.get("scope"), "playback-control-all");
});

test("iOS OAuth success redirects to the custom app callback URL", async () => {
  const state = signedState({
    target: "ios",
    redirectURI: "https://example.netlify.app/sonos/oauth/callback",
  });

  const response = await handler(callbackEvent("/sonos/oauth/callback", { code: "code", state }));

  assert.match(response.headers.Location, /^sonosvoiceremote:\/\/oauth\/callback\?/);
  const location = new URL(response.headers.Location);
  assert.equal(location.searchParams.get("access_token"), "access-token");
  assert.equal(location.searchParams.get("refresh_token"), "refresh-token");
});

test("missing authorization code redirects with an error", async () => {
  const state = signedState({
    target: "web",
    redirectURI: "https://example.netlify.app/sonos/oauth/callback/web",
  });

  const response = await handler(callbackEvent("/sonos/oauth/callback/web", { state }));
  const location = locationURL(response);

  assert.equal(location.searchParams.get("error"), "missing_code");
  assert.equal(
    location.searchParams.get("error_description"),
    "The Sonos callback did not include an authorization code."
  );
});

test("Sonos error callback redirects with the provider error", async () => {
  const state = signedState({
    target: "web",
    redirectURI: "https://example.netlify.app/sonos/oauth/callback/web",
  });

  const response = await handler(
    callbackEvent("/sonos/oauth/callback/web", {
      error: "access_denied",
      error_description: "User denied access",
      state,
    })
  );
  const location = locationURL(response);

  assert.equal(location.searchParams.get("error"), "access_denied");
  assert.equal(location.searchParams.get("error_description"), "User denied access");
});

test("invalid web state redirects back to the web app", async () => {
  const response = await handler(
    callbackEvent("/sonos/oauth/callback/web", {
      code: "code",
      state: "invalid-state",
    })
  );
  const location = locationURL(response);

  assert.equal(location.origin, "https://example.netlify.app");
  assert.equal(location.pathname, "/");
  assert.equal(location.searchParams.get("error"), "oauth_callback_failed");
  assert.equal(location.searchParams.get("error_description"), "Missing or invalid OAuth state.");
});
