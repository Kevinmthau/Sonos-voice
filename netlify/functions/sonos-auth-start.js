const { DEFAULT_REDIRECT_URI, createAuthorizeURL, errorRedirect, optionalEnv, redirectResponse } = require("./_sonos-oauth");

exports.handler = async function handler() {
  try {
    const redirectURI = optionalEnv("SONOS_REDIRECT_URI", DEFAULT_REDIRECT_URI);
    return redirectResponse(
      createAuthorizeURL({
        redirectURI,
        statePayload: { target: "ios", redirectURI }
      })
    );
  } catch (error) {
    return errorRedirect("configuration_error", error.message);
  }
};
