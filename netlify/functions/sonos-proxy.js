const SONOS_CONTROL_BASE = "https://api.ws.sonos.com/control/api/v1";
const { optionalEnv } = require("./_sonos-oauth");

const DEFAULT_CLIENT_ID = "ae97b2cd-64bf-472c-9d0f-0ecac953b1dd";

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

  const { path, method, body, token } = payload;

  if (!path || !method) {
    return jsonResponse(400, { error: "Missing path or method" });
  }

  if (!token) {
    return jsonResponse(401, { error: "Missing access token" });
  }

  const trimmedPath = path.replace(/^\/+/, "");
  const url = `${SONOS_CONTROL_BASE}/${trimmedPath}`;
  const clientID = optionalEnv("SONOS_CLIENT_ID", DEFAULT_CLIENT_ID);

  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
  };

  if (clientID) {
    headers["X-Sonos-Api-Key"] = clientID;
  }

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
      },
      body: responseText || "{}",
    };
  } catch (error) {
    return jsonResponse(502, { error: `Sonos API request failed: ${error.message}` });
  }
};

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
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
    },
    body: JSON.stringify(body),
  };
}
