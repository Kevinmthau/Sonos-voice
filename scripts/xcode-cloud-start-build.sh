#!/bin/sh
set -eu

require_env() {
  eval "value=\${$1:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $1" >&2
    exit 1
  fi
}

b64url() {
  base64 | tr '+/' '-_' | tr -d '=\n'
}

require_env ASC_KEY_ID
require_env ASC_ISSUER_ID
require_env ASC_KEY_PATH
require_env ASC_WORKFLOW_ID

if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "ASC_KEY_PATH does not point to a file: $ASC_KEY_PATH" >&2
  exit 1
fi

now="$(date +%s)"
exp="$((now + 1200))"

header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | b64url)"
claims="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' "$ASC_ISSUER_ID" "$now" "$exp" | b64url)"
signature="$(printf '%s.%s' "$header" "$claims" | openssl dgst -binary -sha256 -sign "$ASC_KEY_PATH" | b64url)"
jwt="$header.$claims.$signature"

payload="$(printf '{"data":{"type":"ciBuildRuns","attributes":{},"relationships":{"workflow":{"data":{"type":"ciWorkflows","id":"%s"}}}}}' "$ASC_WORKFLOW_ID")"

curl -sS \
  -X POST "https://api.appstoreconnect.apple.com/v1/ciBuildRuns" \
  -H "Authorization: Bearer $jwt" \
  -H "Content-Type: application/json" \
  -d "$payload"
