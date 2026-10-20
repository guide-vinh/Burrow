#!/usr/bin/env bash
#
# Submits a zip or DMG for notarization and waits for Apple's verdict;
# prints the notarization log when it isn't accepted. Used by
# .github/workflows/notarized-build.yml.
#
# Needs NOTARY_APPLE_ID, NOTARY_APP_PASSWORD and TEAM_ID in the environment.

set -euo pipefail

FILE="${1:?usage: scripts/ci/notarize.sh <file.zip|file.dmg>}"
AUTH=(--apple-id "${NOTARY_APPLE_ID:?}" --password "${NOTARY_APP_PASSWORD:?}" --team-id "${TEAM_ID:?}")

RESULT=$(xcrun notarytool submit "$FILE" "${AUTH[@]}" --wait --timeout 30m --output-format json)
echo "$RESULT"
if [ "$(jq -r .status <<<"$RESULT")" != "Accepted" ]; then
    xcrun notarytool log "$(jq -r .id <<<"$RESULT")" "${AUTH[@]}" || true
    exit 1
fi
