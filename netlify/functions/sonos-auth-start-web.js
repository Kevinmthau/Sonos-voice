const crypto = require("crypto");
const { env, optionalEnv, redirectResponse } = require("./_sonos-oauth");

const DEFAULT_CLIENT_ID = "ae97b2cd-64bf-472c-9d0f-0ecac953b1dd";
const SONOS_AUTHORIZE_URL = "https://api.sonos.com/login/v3/oauth";
const SONOS_SCOPE = "playback-control-all";

function base64url(value) {
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(String(value), "utf8");
  return buffer
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function createSignedState(secret) {
  const payload = {
    nonce: crypto.randomBytes(16).toString("hex"),
    issuedAt: Date.now()
  };
  const encodedPayload = base64url(JSON.stringify(payload));
  const signature = base64url(crypto.createHmac("sha256", secret).update(encodedPayload).digest());
  return `${encodedPayload}.${signature}`;
}

exports.handler = async function handler(event) {
  try {
    const clientID = optionalEnv("SONOS_CLIENT_ID", DEFAULT_CLIENT_ID);
    const stateSecret = env("SONOS_STATE_SECRET");

    const host = event.headers.host || "localhost";
    const webRedirectURI = optionalEnv(
      "SONOS_WEB_REDIRECT_URI",
      `https://${host}/sonos/oauth/callback/web`
    );

    const state = createSignedState(stateSecret);

    const url = new URL(SONOS_AUTHORIZE_URL);
    url.searchParams.set("client_id", clientID);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("scope", SONOS_SCOPE);
    url.searchParams.set("redirect_uri", webRedirectURI);
    url.searchParams.set("state", state);

    return redirectResponse(url.toString());
  } catch (error) {
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ error: error.message }),
    };
  }
};
