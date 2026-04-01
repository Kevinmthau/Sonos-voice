const { DEFAULT_REDIRECT_URI, createAuthorizeURL, optionalEnv, redirectResponse } = require("./_sonos-oauth");

exports.handler = async function handler(event) {
  try {
    const webRedirectURI = optionalEnv(
      "SONOS_WEB_REDIRECT_URI",
      optionalEnv("SONOS_REDIRECT_URI", DEFAULT_REDIRECT_URI)
    );
    return redirectResponse(
      createAuthorizeURL({
        redirectURI: webRedirectURI,
        statePayload: { target: "web", redirectURI: webRedirectURI }
      })
    );
  } catch (error) {
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ error: error.message }),
    };
  }
};
