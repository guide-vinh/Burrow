#!/usr/bin/env bash
#
# Verifies a Sparkle EdDSA signature against a raw public key, e.g. the
# app's SUPublicEDKey, so a release signed with the wrong private key fails
# here instead of being rejected by every installed copy of the app.
#
# Usage: scripts/ci/verify_ed25519.sh <file> <base64 signature> <base64 public key>
# Needs OpenSSL 3 (LibreSSL lacks Ed25519); set OPENSSL to its path.

set -euo pipefail

FILE="${1:?usage: verify_ed25519.sh <file> <signature> <public key>}"
SIGNATURE="${2:?missing signature}"
PUBLIC_KEY="${3:?missing public key}"
OPENSSL="${OPENSSL:-openssl}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# DER SubjectPublicKeyInfo header for a raw 32-byte Ed25519 key.
printf '302a300506032b6570032100' | xxd -r -p > "$TMP/pub.der"
printf '%s' "$PUBLIC_KEY" | base64 --decode >> "$TMP/pub.der"
printf '%s' "$SIGNATURE" | base64 --decode > "$TMP/sig.bin"

"$OPENSSL" pkey -pubin -inform DER -in "$TMP/pub.der" -out "$TMP/pub.pem"
"$OPENSSL" pkeyutl -verify -pubin -inkey "$TMP/pub.pem" -rawin -in "$FILE" -sigfile "$TMP/sig.bin"
