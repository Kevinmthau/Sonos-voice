const crypto = require("crypto");
const { getStore } = require("@netlify/blobs");
const { exchangeRefreshToken, optionalEnv } = require("./_sonos-oauth");

const DEFAULT_ALLOWED_ORIGIN = "https://sonos-voice.netlify.app";
const DEFAULT_PER_IP_DAILY_CAP = 60;

exports.handler = async function handler(event) {
  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 204,
      headers: corsHeaders(),
      body: "",
    };
  }

  if (event.httpMethod !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  let payload;
  try {
    payload = JSON.parse(event.body || "{}");
  } catch {
    return jsonResponse(400, { error: "Invalid JSON body" });
  }

  const refreshToken = payload.refresh_token;
  if (!refreshToken || typeof refreshToken !== "string") {
    return jsonResponse(400, { error: "Missing refresh_token" });
  }

  // Defensive rate limit: a stolen refresh token shouldn't be free to brute-force.
  try {
    const today = new Date().toISOString().slice(0, 10);
    const ip = clientIPFor(event);
    const key = `refresh:ip:${hashIdentifier(ip)}:${today}`;
    const cap = Number(process.env.SONOS_REFRESH_PER_IP_DAILY_CAP || DEFAULT_PER_IP_DAILY_CAP);
    const store = getStore("sonos-refresh-rate-limits");
    const current = Number((await store.get(key)) || 0);
    if (current >= cap) {
      return jsonResponse(429, { error: "Refresh limit reached. Please sign in again." });
    }
    await store.set(key, String(current + 1));
  } catch (error) {
    console.warn(`Refresh rate-limit store unavailable: ${error.message}`);
  }

  try {
    const tokenResponse = await exchangeRefreshToken(refreshToken);
    return jsonResponse(200, {
      access_token: tokenResponse.access_token,
      refresh_token: tokenResponse.refresh_token || refreshToken,
      expires_in: tokenResponse.expires_in,
      scope: tokenResponse.scope || "",
    });
  } catch (error) {
    const status = error.status === 400 || error.status === 401 ? 401 : 502;
    return jsonResponse(status, { error: error.message });
  }
};

function clientIPFor(event) {
  const headers = event.headers || {};
  return (
    headers["x-nf-client-connection-ip"] ||
    headers["X-Nf-Client-Connection-Ip"] ||
    headers["x-forwarded-for"]?.split(",")[0]?.trim() ||
    headers["client-ip"] ||
    "unknown"
  );
}

function hashIdentifier(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 32);
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": optionalEnv("SONOS_PROXY_ALLOWED_ORIGIN", DEFAULT_ALLOWED_ORIGIN),
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      ...corsHeaders(),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
    body: JSON.stringify(body),
  };
}
