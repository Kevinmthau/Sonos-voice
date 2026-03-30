const {
  env,
  errorRedirect,
  exchangeAuthorizationCode,
  redirectResponse,
  verifySignedState,
  webCallbackURL
} = require("./_sonos-oauth");

exports.handler = async function handler(event) {
  try {
    const query = event.queryStringParameters || {};
    if (query.error) {
      const callbackURL = new URL(webCallbackURL(), `https://${event.headers.host}`);
      callbackURL.searchParams.set("error", query.error);
      callbackURL.searchParams.set("error_description", query.error_description || query.error);
      return redirectResponse(callbackURL.toString());
    }

    verifySignedState(query.state, env("SONOS_STATE_SECRET"));

    if (!query.code) {
      const callbackURL = new URL(webCallbackURL(), `https://${event.headers.host}`);
      callbackURL.searchParams.set("error", "missing_code");
      callbackURL.searchParams.set("error_description", "The Sonos callback did not include an authorization code.");
      return redirectResponse(callbackURL.toString());
    }

    const tokenResponse = await exchangeAuthorizationCode(query.code);
    const callbackURL = new URL(webCallbackURL(), `https://${event.headers.host}`);
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
    const callbackURL = new URL(webCallbackURL(), `https://${event.headers.host}`);
    callbackURL.searchParams.set("error", "oauth_callback_failed");
    callbackURL.searchParams.set("error_description", error.message);
    return redirectResponse(callbackURL.toString());
  }
};
