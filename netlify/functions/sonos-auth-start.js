const { createAuthorizeURL, errorRedirect, redirectResponse } = require("./_sonos-oauth");

exports.handler = async function handler() {
  try {
    return redirectResponse(createAuthorizeURL());
  } catch (error) {
    return errorRedirect("configuration_error", error.message);
  }
};
