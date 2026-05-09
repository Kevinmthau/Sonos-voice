const crypto = require("crypto");

const OPENAI_TRANSCRIPTIONS_URL = "https://api.openai.com/v1/audio/transcriptions";
const DEFAULT_MODEL = "gpt-4o-mini-transcribe";
const MAX_AUDIO_BYTES = 12 * 1024 * 1024;

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

  if (!audio.length) {
    return jsonResponse(400, { error: "Missing audio body." });
  }

  if (audio.length > MAX_AUDIO_BYTES) {
    return jsonResponse(413, { error: "Audio body is too large." });
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
