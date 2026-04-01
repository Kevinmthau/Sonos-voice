const crypto = require("crypto");

const DEFAULT_CLIENT_ID = "ae97b2cd-64bf-472c-9d0f-0ecac953b1dd";
const DEFAULT_REDIRECT_URI = "https://sonos-voice.netlify.app/sonos/oauth/callback";
const DEFAULT_IOS_CALLBACK_URL = "sonosvoiceremote://oauth/callback";
const DEFAULT_WEB_CALLBACK_URL = "/";
const SONOS_AUTHORIZE_URL = "https://api.sonos.com/login/v3/oauth";
const SONOS_TOKEN_URL = "https://api.sonos.com/login/v3/oauth/access";
const SONOS_SCOPE = "playback-control-all";

function env(name, fallback = undefined) {
  const value = process.env[name] ?? fallback;
  if (value === undefined || value === null || value === "") {
    throw new Error(`Missing required environment variable ${name}.`);
  }
  return value;
}

function optionalEnv(name, fallback = undefined) {
  const value = process.env[name];
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  return value;
}

function base64url(value) {
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(String(value), "utf8");
  return buffer
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function createSignedState(secret, extraPayload = {}) {
  const payload = {
    nonce: crypto.randomBytes(16).toString("hex"),
    issuedAt: Date.now(),
    ...extraPayload
  };
  const encodedPayload = base64url(JSON.stringify(payload));
  const signature = base64url(crypto.createHmac("sha256", secret).update(encodedPayload).digest());
  return `${encodedPayload}.${signature}`;
}

function verifySignedState(state, secret) {
  if (!state || !state.includes(".")) {
    throw new Error("Missing or invalid OAuth state.");
  }

  const [encodedPayload, receivedSignature] = state.split(".");
  const expectedSignature = base64url(
    crypto.createHmac("sha256", secret).update(encodedPayload).digest()
  );

  const received = Buffer.from(receivedSignature, "utf8");
  const expected = Buffer.from(expectedSignature, "utf8");
  if (received.length !== expected.length || !crypto.timingSafeEqual(received, expected)) {
    throw new Error("OAuth state verification failed.");
  }

  const payload = JSON.parse(Buffer.from(encodedPayload, "base64url").toString("utf8"));
  const maxAgeMs = 10 * 60 * 1000;
  if (typeof payload.issuedAt !== "number" || Date.now() - payload.issuedAt > maxAgeMs) {
    throw new Error("OAuth state expired.");
  }

  return payload;
}

function createAuthorizeURL(options = {}) {
  const clientID = optionalEnv("SONOS_CLIENT_ID", DEFAULT_CLIENT_ID);
  const redirectURI = options.redirectURI || optionalEnv("SONOS_REDIRECT_URI", DEFAULT_REDIRECT_URI);
  const stateSecret = env("SONOS_STATE_SECRET");
  const state = createSignedState(stateSecret, options.statePayload);

  const url = new URL(SONOS_AUTHORIZE_URL);
  url.searchParams.set("client_id", clientID);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", SONOS_SCOPE);
  url.searchParams.set("redirect_uri", redirectURI);
  url.searchParams.set("state", state);
  return url.toString();
}

async function exchangeAuthorizationCode(code, redirectURIOverride) {
  const clientID = optionalEnv("SONOS_CLIENT_ID", DEFAULT_CLIENT_ID);
  const clientSecret = env("SONOS_CLIENT_SECRET");
  const redirectURI = redirectURIOverride || optionalEnv("SONOS_REDIRECT_URI", DEFAULT_REDIRECT_URI);

  const credentials = Buffer.from(`${clientID}:${clientSecret}`, "utf8").toString("base64");
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectURI
  });

  const response = await fetch(SONOS_TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${credentials}`,
      "Content-Type": "application/x-www-form-urlencoded;charset=utf-8"
    },
    body: body.toString()
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail = payload.error_description || payload.error || "Sonos token exchange failed.";
    throw new Error(detail);
  }

  return payload;
}

function appCallbackURL() {
  return optionalEnv("SONOS_IOS_CALLBACK_URL", DEFAULT_IOS_CALLBACK_URL);
}

function webCallbackURL() {
  return optionalEnv("SONOS_WEB_CALLBACK_URL", DEFAULT_WEB_CALLBACK_URL);
}

function redirectResponse(location) {
  return {
    statusCode: 302,
    headers: {
      Location: location,
      "Cache-Control": "no-store"
    },
    body: ""
  };
}

function errorRedirect(error, description = error) {
  const url = new URL(appCallbackURL());
  url.searchParams.set("error", error);
  url.searchParams.set("error_description", description);
  return redirectResponse(url.toString());
}

module.exports = {
  DEFAULT_CLIENT_ID,
  DEFAULT_REDIRECT_URI,
  appCallbackURL,
  createAuthorizeURL,
  createSignedState,
  env,
  errorRedirect,
  exchangeAuthorizationCode,
  optionalEnv,
  redirectResponse,
  verifySignedState,
  webCallbackURL
};
