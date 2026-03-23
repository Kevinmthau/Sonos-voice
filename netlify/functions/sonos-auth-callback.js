const {
  appCallbackURL,
  env,
  errorRedirect,
  exchangeAuthorizationCode,
  redirectResponse,
  verifySignedState
} = require("./_sonos-oauth");

exports.handler = async function handler(event) {
  try {
    const query = event.queryStringParameters || {};
    if (query.error) {
      return errorRedirect(query.error, query.error_description || query.error);
    }

    verifySignedState(query.state, env("SONOS_STATE_SECRET"));

    if (!query.code) {
      return errorRedirect("missing_code", "The Sonos callback did not include an authorization code.");
    }

    const tokenResponse = await exchangeAuthorizationCode(query.code);
    const callbackURL = new URL(appCallbackURL());
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
    return errorRedirect("oauth_callback_failed", error.message);
  }
};
