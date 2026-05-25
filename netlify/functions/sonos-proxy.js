const SONOS_CONTROL_BASE = "https://api.ws.sonos.com/control/api/v1";
const { env, optionalEnv } = require("./_sonos-oauth");

const ALLOWED_METHODS = new Set(["GET", "POST", "DELETE"]);
const ALLOWED_PATH_PREFIXES = ["households", "groups", "players", "playbackSessions"];
const MAX_PATH_LENGTH = 256;
const MAX_BODY_BYTES = 16 * 1024;
const DEFAULT_ALLOWED_ORIGIN = "https://sonos-voice.netlify.app";

function allowedOrigin() {
  return optionalEnv("SONOS_PROXY_ALLOWED_ORIGIN", DEFAULT_ALLOWED_ORIGIN);
}

function parseAllowedHouseholds() {
  const raw = optionalEnv("SONOS_ALLOWED_HOUSEHOLDS", "");
  return new Set(
    raw
      .split(",")
      .map((id) => id.trim())
      .filter(Boolean)
  );
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": allowedOrigin(),
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

function extractHouseholdFromPath(trimmedPath) {
  const match = trimmedPath.match(/^households\/([^/]+)(?:\/|$)/);
  return match ? match[1] : null;
}

function extractHouseholdScopedTarget(trimmedPath) {
  const [scope, id] = trimmedPath.split("/");
  if (scope !== "groups" && scope !== "players") {
    return null;
  }
  return { scope, id };
}

async function validateTargetInHousehold(trimmedPath, householdId, token, clientID) {
  const target = extractHouseholdScopedTarget(trimmedPath);
  if (!target) {
    return null;
  }

  if (!target.id) {
    return { statusCode: 400, error: "Missing target id for this request" };
  }

  let response;
  try {
    response = await fetch(`${SONOS_CONTROL_BASE}/households/${encodeURIComponent(householdId)}/groups`, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
        "X-Sonos-Api-Key": clientID,
      },
    });
  } catch (error) {
    return { statusCode: 502, error: `Sonos target validation failed: ${error.message}` };
  }

  if (response.status === 401) {
    return { statusCode: 401, error: "Sonos authentication expired" };
  }
  if (!response.ok) {
    return { statusCode: 403, error: "Target household could not be validated." };
  }

  let topology;
  try {
    topology = await response.json();
  } catch {
    return { statusCode: 502, error: "Sonos target validation returned invalid JSON." };
  }

  const items = target.scope === "groups" ? topology.groups : topology.players;
  const found = Array.isArray(items) && items.some((item) => item && item.id === target.id);
  if (!found) {
    return { statusCode: 403, error: "Target is not in the declared household." };
  }

  return null;
}

function validatePath(path) {
  if (typeof path !== "string" || !path.length) {
    return "path must be a non-empty string";
  }
  if (path.length > MAX_PATH_LENGTH) {
    return "path is too long";
  }
  if (path.includes("..") || path.includes("//")) {
    return "path contains disallowed segments";
  }
  const trimmed = path.replace(/^\/+/, "");
  const prefix = trimmed.split("/")[0];
  if (!ALLOWED_PATH_PREFIXES.includes(prefix)) {
    return `path prefix '${prefix}' is not allowed`;
  }
  return null;
}

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

  const rawBody = event.body || "{}";
  if (Buffer.byteLength(rawBody, "utf8") > MAX_BODY_BYTES) {
    return jsonResponse(413, { error: "Request body too large" });
  }

  let payload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return jsonResponse(400, { error: "Invalid JSON body" });
  }

  const { path, method, body, token, householdId } = payload;

  if (!path || !method) {
    return jsonResponse(400, { error: "Missing path or method" });
  }

  if (!token) {
    return jsonResponse(401, { error: "Missing access token" });
  }

  if (!ALLOWED_METHODS.has(method)) {
    return jsonResponse(400, { error: `Method '${method}' is not permitted` });
  }

  const pathError = validatePath(path);
  if (pathError) {
    return jsonResponse(400, { error: pathError });
  }

  const trimmedPath = path.replace(/^\/+/, "");
  const pathHouseholdId = extractHouseholdFromPath(trimmedPath);
  const allowedHouseholds = parseAllowedHouseholds();
  let effectiveHouseholdId = null;

  // Bare "households" listing is allowed (user needs it to pick a household);
  // every other path either has a household in the URL or must declare one.
  if (trimmedPath !== "households") {
    effectiveHouseholdId = pathHouseholdId || householdId;
    if (!effectiveHouseholdId) {
      return jsonResponse(400, { error: "Missing householdId for this request" });
    }
    if (allowedHouseholds.size > 0 && !allowedHouseholds.has(effectiveHouseholdId)) {
      return jsonResponse(403, { error: "This household is not allowed to use this deployment." });
    }
    if (pathHouseholdId && householdId && pathHouseholdId !== householdId) {
      return jsonResponse(400, { error: "Path household does not match declared household" });
    }
  }

  let clientID;
  try {
    clientID = env("SONOS_CLIENT_ID");
  } catch (error) {
    return jsonResponse(500, { error: error.message });
  }

  if (allowedHouseholds.size > 0 && effectiveHouseholdId) {
    const targetError = await validateTargetInHousehold(trimmedPath, effectiveHouseholdId, token, clientID);
    if (targetError) {
      return jsonResponse(targetError.statusCode, { error: targetError.error });
    }
  }

  const url = `${SONOS_CONTROL_BASE}/${trimmedPath}`;
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
    "X-Sonos-Api-Key": clientID,
  };

  if (body) {
    headers["Content-Type"] = "application/json";
  }

  try {
    const response = await fetch(url, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });

    const responseText = await response.text();

    if (response.status === 401) {
      return jsonResponse(401, { error: "Sonos authentication expired" });
    }

    return {
      statusCode: response.status,
      headers: {
        ...corsHeaders(),
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
      body: responseText || "{}",
    };
  } catch (error) {
    return jsonResponse(502, { error: `Sonos API request failed: ${error.message}` });
  }
};
