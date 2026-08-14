#!/bin/bash
# Prints the raw /api/oauth/usage response, pretty-printed, so the shape and
# encoding of `utilization` and `resets_at` can be inspected directly.
# The OAuth token is never echoed.
set -euo pipefail

CREDS="$(security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null || true)"
if [ -z "$CREDS" ]; then
    echo "No 'Claude Code-credentials' item in the Keychain. Run \`claude\` and sign in first." >&2
    exit 1
fi

TOKEN="$(printf '%s' "$CREDS" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["claudeAiOauth"]["accessToken"])')"
if [ -z "$TOKEN" ]; then
    echo "Could not find claudeAiOauth.accessToken in the stored credentials." >&2
    exit 1
fi

# The token goes in via a stdin config file rather than argv, which any
# same-uid process could read from the process list.
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" \
    | curl -sS --max-time 5 --config - \
        -H "Content-Type: application/json" \
        https://api.anthropic.com/api/oauth/usage \
    | /usr/bin/python3 -m json.tool
