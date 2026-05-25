const assert = require("node:assert/strict");
const test = require("node:test");
const { handler } = require("../netlify/functions/sonos-proxy.js");

const originalEnv = { ...process.env };
const originalFetch = global.fetch;

function resetEnvironment() {
  process.env = { ...originalEnv };
  process.env.SONOS_CLIENT_ID = "client-id";
  process.env.SONOS_ALLOWED_HOUSEHOLDS = "allowed-household";
}

function proxyEvent(payload) {
  return {
    httpMethod: "POST",
    body: JSON.stringify(payload),
  };
}

function jsonResponse(payload, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload,
    text: async () => JSON.stringify(payload),
  };
}

test.beforeEach(() => {
  resetEnvironment();
});

test.afterEach(() => {
  global.fetch = originalFetch;
  process.env = { ...originalEnv };
});

test("allowed household proxy rejects group targets outside the declared household", async () => {
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push({ url, options });
    return jsonResponse({
      groups: [{ id: "allowed-group" }],
      players: [{ id: "allowed-player" }],
    });
  };

  const response = await handler(
    proxyEvent({
      path: "groups/other-group/playback/play",
      method: "POST",
      token: "access-token",
      householdId: "allowed-household",
    })
  );

  assert.equal(response.statusCode, 403);
  assert.match(JSON.parse(response.body).error, /Target is not in the declared household/);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://api.ws.sonos.com/control/api/v1/households/allowed-household/groups");
});

test("allowed household proxy rejects player targets outside the declared household", async () => {
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push({ url, options });
    return jsonResponse({
      groups: [{ id: "allowed-group" }],
      players: [{ id: "allowed-player" }],
    });
  };

  const response = await handler(
    proxyEvent({
      path: "players/other-player/playerVolume",
      method: "POST",
      body: { volume: 20 },
      token: "access-token",
      householdId: "allowed-household",
    })
  );

  assert.equal(response.statusCode, 403);
  assert.match(JSON.parse(response.body).error, /Target is not in the declared household/);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://api.ws.sonos.com/control/api/v1/households/allowed-household/groups");
});

test("allowed household proxy forwards validated group targets", async () => {
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith("/households/allowed-household/groups")) {
      return jsonResponse({
        groups: [{ id: "allowed-group" }],
        players: [{ id: "allowed-player" }],
      });
    }
    return jsonResponse({ ok: true });
  };

  const response = await handler(
    proxyEvent({
      path: "groups/allowed-group/playback/play",
      method: "POST",
      token: "access-token",
      householdId: "allowed-household",
    })
  );

  assert.equal(response.statusCode, 200);
  assert.deepEqual(
    calls.map((call) => [call.url, call.options.method]),
    [
      ["https://api.ws.sonos.com/control/api/v1/households/allowed-household/groups", "GET"],
      ["https://api.ws.sonos.com/control/api/v1/groups/allowed-group/playback/play", "POST"],
    ]
  );
});

test("target validation preserves expired-token responses for refresh", async () => {
  global.fetch = async () => jsonResponse({ error: "expired" }, 401);

  const response = await handler(
    proxyEvent({
      path: "groups/allowed-group/playback/play",
      method: "POST",
      token: "expired-token",
      householdId: "allowed-household",
    })
  );

  assert.equal(response.statusCode, 401);
  assert.match(JSON.parse(response.body).error, /authentication expired/);
});
