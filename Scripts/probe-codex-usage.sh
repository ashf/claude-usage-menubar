#!/bin/bash
# Prints the raw Codex usage response, pretty-printed, so its shape can be
# checked against CodexUsage.swift. The token is never echoed.
set -euo pipefail

AUTH="$HOME/.codex/auth.json"
if [ ! -f "$AUTH" ]; then
    echo "No $AUTH. Run \`codex login\` with a ChatGPT account first." >&2
    exit 1
fi

# The token goes in via a stdin config file rather than argv, which any
# same-uid process could read from the process list.
/usr/bin/python3 -c '
import json, sys
t = json.load(open(sys.argv[1]))["tokens"]
print("header = \"Authorization: Bearer %s\"" % t["access_token"])
print("header = \"ChatGPT-Account-Id: %s\"" % t["account_id"])
' "$AUTH" \
    | curl -sS --max-time 5 --config - \
        -H "Accept: application/json" \
        https://chatgpt.com/backend-api/wham/usage \
    | /usr/bin/python3 -m json.tool
