const {
  appCallbackURL,
  env,
  exchangeAuthorizationCode,
  redirectResponse,
  verifySignedState,
  webCallbackURL
} = require("./_sonos-oauth");

function callbackURLForState(statePayload, event) {
  return statePayload?.target === "web"
    ? new URL(webCallbackURL(), `https://${event.headers.host}`)
    : new URL(appCallbackURL());
}

function redirectWithError(statePayload, event, error, description) {
  const callbackURL = callbackURLForState(statePayload, event);
  callbackURL.searchParams.set("error", error);
  callbackURL.searchParams.set("error_description", description);
  return redirectResponse(callbackURL.toString());
}

exports.handler = async function handler(event) {
  let statePayload = null;

  try {
    const query = event.queryStringParameters || {};
    if (query.error) {
      statePayload = query.state ? verifySignedState(query.state, env("SONOS_STATE_SECRET")) : null;
      return redirectWithError(statePayload, event, query.error, query.error_description || query.error);
    }

    statePayload = verifySignedState(query.state, env("SONOS_STATE_SECRET"));

    if (!query.code) {
      return redirectWithError(
        statePayload,
        event,
        "missing_code",
        "The Sonos callback did not include an authorization code."
      );
    }

    const tokenResponse = await exchangeAuthorizationCode(query.code, statePayload.redirectURI);
    const callbackURL = callbackURLForState(statePayload, event);
    callbackURL.searchParams.set("access_token", tokenResponse.access_token);
    if (tokenResponse.refresh_token) {
      callbackURL.searchParams.set("refresh_token", tokenResponse.refresh_token);
    }
    if (tokenResponse.expires_in) {
      callbackURL.searchParams.set("expires_in", String(tokenResponse.expires_in));
    }
    callbackURL.searchParams.set("scope", tokenResponse.scope || "");

    return redirectResponse(callbackURL.toString());
  } catch (error) {
    return redirectWithError(statePayload, event, "oauth_callback_failed", error.message);
  }
};
