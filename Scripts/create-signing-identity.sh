#!/bin/bash
# Creates a self-signed code signing identity in the login keychain, so the app
# can be signed with a stable identity instead of ad-hoc.
#
# An ad-hoc signature's designated requirement is a bare cdhash, which changes
# with every code change. The Keychain ACL entry written by "Always Allow" is
# matched against that requirement, so an ad-hoc build has to be re-authorized
# (with the login password) after every rebuild. A certificate-backed identity
# gives a requirement pinned to the leaf certificate instead, which survives
# rebuilds, so a single "Always Allow" holds.
#
# Run once. Marking the certificate trusted for code signing needs the login
# password, via the standard macOS authorization prompt.
set -euo pipefail

IDENTITY_NAME="ClaudeUsageMenuBar Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY_NAME"; then
    echo "Identity '$IDENTITY_NAME' already exists — nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# `security import` rejects an empty PKCS#12 password with a MAC verification
# error, so the bundle gets a throwaway one. It only protects the file in $WORK,
# which is deleted on exit.
TRANSFER_PASSWORD="transfer"

# -x marks the imported private key non-extractable; -T lets codesign use it.
/usr/bin/openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -passout "pass:$TRANSFER_PASSWORD"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$TRANSFER_PASSWORD" \
    -T /usr/bin/codesign -x

# User trust domain only, so this never becomes a system-wide trusted root.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY_NAME"; then
    echo "Created '$IDENTITY_NAME'. ./Scripts/build-app.sh will now use it."
    echo "The next build prompts once for codesign to use the key — choose Always Allow."
else
    echo "Certificate imported but not valid for code signing. Check its trust" >&2
    echo "settings in Keychain Access, under the login keychain." >&2
    exit 1
fi
