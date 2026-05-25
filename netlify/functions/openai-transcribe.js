const crypto = require("crypto");
const { getStore } = require("@netlify/blobs");

const OPENAI_TRANSCRIPTIONS_URL = "https://api.openai.com/v1/audio/transcriptions";
const DEFAULT_MODEL = "gpt-4o-mini-transcribe";
const MAX_AUDIO_BYTES = 4 * 1024 * 1024;
const MIN_AUDIO_BYTES = 2 * 1024;
const DEFAULT_PER_IP_DAILY_CAP = 200;
const DEFAULT_GLOBAL_DAILY_CAP = 2000;

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

  const proxyToken = process.env.SONOS_OPENAI_TRANSCRIPTION_TOKEN;
  if (!proxyToken) {
    return jsonResponse(503, { error: "OpenAI transcription proxy is not configured." });
  }

  if (!isAuthorized(event, proxyToken)) {
    return jsonResponse(401, { error: "Unauthorized." });
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return jsonResponse(500, { error: "Missing OPENAI_API_KEY." });
  }

  const audio = event.isBase64Encoded
    ? Buffer.from(event.body || "", "base64")
    : Buffer.from(event.body || "", "binary");

  if (audio.length < MIN_AUDIO_BYTES) {
    return jsonResponse(400, { error: "Audio body too short to transcribe." });
  }

  if (audio.length > MAX_AUDIO_BYTES) {
    return jsonResponse(413, { error: "Audio body is too large." });
  }

  const today = new Date().toISOString().slice(0, 10);
  const clientIp = clientIPFor(event);
  const ipKey = `transcribe:ip:${hashIdentifier(clientIp)}:${today}`;
  const globalKey = `transcribe:global:${today}`;
  const perIpCap = Number(process.env.TRANSCRIBE_PER_IP_DAILY_CAP || DEFAULT_PER_IP_DAILY_CAP);
  const globalCap = Number(process.env.TRANSCRIBE_GLOBAL_DAILY_CAP || DEFAULT_GLOBAL_DAILY_CAP);

  try {
    const store = getStore("transcription-rate-limits");
    const globalCount = Number((await store.get(globalKey)) || 0);
    if (globalCount >= globalCap) {
      return jsonResponse(429, {
        error: "Daily transcription cap for this deployment has been reached. Try again tomorrow.",
      });
    }

    const ipCount = Number((await store.get(ipKey)) || 0);
    if (ipCount >= perIpCap) {
      return jsonResponse(429, {
        error: "You have reached today's transcription limit. Try again tomorrow.",
      });
    }

    await store.set(globalKey, String(globalCount + 1));
    await store.set(ipKey, String(ipCount + 1));
  } catch (error) {
    // If the rate-limit store is unavailable, fall through rather than block
    // the user. Surface in logs so it can be diagnosed.
    console.warn(`Rate-limit store unavailable: ${error.message}`);
  }

  const contentType = event.headers["content-type"] || event.headers["Content-Type"] || "audio/mp4";
  const filename = sanitizeFilename(
    event.headers["x-audio-filename"] || event.headers["X-Audio-Filename"] || "command.m4a"
  );
  const model = process.env.OPENAI_TRANSCRIPTION_MODEL || DEFAULT_MODEL;

  const form = new FormData();
  form.append("model", model);
  form.append("response_format", "json");
  form.append("file", new Blob([audio], { type: contentType }), filename);

  try {
    const response = await fetch(OPENAI_TRANSCRIPTIONS_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
      body: form,
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const detail = payload.error?.message || payload.error || "OpenAI transcription failed.";
      return jsonResponse(response.status, { error: detail });
    }

    return jsonResponse(200, { text: payload.text || "" });
  } catch (error) {
    return jsonResponse(502, { error: `OpenAI transcription request failed: ${error.message}` });
  }
};

function sanitizeFilename(value) {
  return String(value).replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 80) || "command.m4a";
}

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

function isAuthorized(event, expectedToken) {
  const headers = event.headers || {};
  const authorization = headers.authorization || headers.Authorization || "";
  const suppliedToken = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";

  if (!suppliedToken) {
    return false;
  }

  const supplied = Buffer.from(suppliedToken, "utf8");
  const expected = Buffer.from(expectedToken, "utf8");
  return supplied.length === expected.length && crypto.timingSafeEqual(supplied, expected);
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": process.env.SONOS_TRANSCRIPTION_ALLOWED_ORIGIN || "https://sonos-voice.netlify.app",
    "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Audio-Filename",
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
