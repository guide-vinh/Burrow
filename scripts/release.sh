#!/usr/bin/env bash
#
# Full release: archive → Developer-ID-sign → notarize → staple → Sparkle-sign
# → GitHub Release → append to appcast gist.
#
# Usage:
#   scripts/release.sh <version>            e.g. scripts/release.sh 0.1.0
#
# Prereqs (one-time):
#   - Developer ID Application cert in keychain (T4XT6XZ2WT)
#   - notarytool keychain profile `burrow-notarize`
#   - Sparkle EdDSA private key in keychain
#   - `gh` authenticated for guide-vinh/Burrow
#   - sign_update binary findable (default: Sparkle CocoaPods cache)

set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>}"
SCHEME="Burrow"
TEAM_ID="T4XT6XZ2WT"
NOTARY_PROFILE="burrow-notarize"
GIST_ID="8b71ecd743dadfba09878aca26795040"
GH_REPO="guide-vinh/Burrow"

BUILD_DIR="build/release-${VERSION}"
ARCHIVE="${BUILD_DIR}/Burrow.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
APP_PATH="${EXPORT_DIR}/Burrow.app"
ZIP_PATH="${BUILD_DIR}/Burrow-${VERSION}.zip"
DMG_PATH="${BUILD_DIR}/Burrow-${VERSION}.dmg"
SIGNING_IDENTITY="Developer ID Application: Nha Nguyen Trong (${TEAM_ID})"
APPCAST_LOCAL="scripts/appcast.xml"
INFO_PLIST="Burrow/Info.plist"

# Sparkle's bin tools — adjust if you keep them elsewhere.
SPARKLE_TOOLS="${SPARKLE_TOOLS:-${HOME}/Library/Caches/CocoaPods/Pods/Release/Sparkle/2.9.1-a4115/bin}"

step() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }

# 0. Bump Info.plist ---------------------------------------------------------
# CFBundleShortVersionString = the human VERSION (e.g. 0.1.2).
# CFBundleVersion = monotonic integer; what Sparkle's version comparator
# uses against <sparkle:version>. Increment by 1 every release so older
# installs see the new build as strictly newer.
step "bump Info.plist"
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INFO_PLIST}")
NEW_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD}" "${INFO_PLIST}"
echo "  CFBundleShortVersionString -> ${VERSION}"
echo "  CFBundleVersion            -> ${NEW_BUILD} (was ${CURRENT_BUILD})"

# 1. Archive ------------------------------------------------------------------
step "archive (Release, Developer ID)"
rm -rf "${BUILD_DIR}"
xcodebuild -scheme "${SCHEME}" -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE}" \
    archive | xcbeautify --quiet 2>/dev/null || \
xcodebuild -scheme "${SCHEME}" -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE}" \
    archive

# 2. Export -------------------------------------------------------------------
step "export (developer-id)"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE}" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "${EXPORT_DIR}"

# 3. Zip for notarization ----------------------------------------------------
step "zip for notarization"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

# 4. Notarize ----------------------------------------------------------------
step "notarize (waits for Apple — typically 1-5 min)"
xcrun notarytool submit "${ZIP_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

# 5. Staple ------------------------------------------------------------------
step "staple notarization ticket"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

# 6. Re-zip stapled app ------------------------------------------------------
step "re-zip stapled app"
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

# 6b. Build DMG (signed, notarized, stapled) ---------------------------------
step "build dmg"
if ! command -v create-dmg >/dev/null 2>&1; then
    echo "error: create-dmg not found. Install with \`brew install create-dmg\`." >&2
    exit 1
fi
# create-dmg picks up every file in the source dir, so isolate just Burrow.app.
DMG_STAGE="${BUILD_DIR}/dmg-stage"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
ditto "${APP_PATH}" "${DMG_STAGE}/Burrow.app"
rm -f "${DMG_PATH}"
create-dmg \
    --volname "Burrow ${VERSION}" \
    --window-pos 200 120 \
    --window-size 600 320 \
    --icon-size 100 \
    --icon "Burrow.app" 175 140 \
    --hide-extension "Burrow.app" \
    --app-drop-link 425 140 \
    "${DMG_PATH}" \
    "${DMG_STAGE}"

step "sign dmg"
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "${DMG_PATH}"

step "notarize dmg"
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

step "staple dmg"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

# 7. Sparkle sign ------------------------------------------------------------
step "sparkle sign_update"
if [[ ! -x "${SPARKLE_TOOLS}/sign_update" ]]; then
    echo "error: sign_update not found at ${SPARKLE_TOOLS}" >&2
    echo "  set SPARKLE_TOOLS=/path/to/sparkle/bin and re-run" >&2
    exit 1
fi
SIGN_OUTPUT=$("${SPARKLE_TOOLS}/sign_update" "${ZIP_PATH}")
ED_SIGNATURE=$(printf '%s' "${SIGN_OUTPUT}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(stat -f %z "${ZIP_PATH}")
echo "  sparkle:edSignature=${ED_SIGNATURE}"
echo "  length=${LENGTH}"

# 8. Append to local appcast.xml --------------------------------------------
step "append <item> to ${APPCAST_LOCAL}"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/v${VERSION}/Burrow-${VERSION}.zip"

ITEM_FILE=$(mktemp)
cat > "${ITEM_FILE}" <<EOF
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${NEW_BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${LENGTH}"
                type="application/octet-stream" />
        </item>
EOF

# Insert the contents of the item file immediately before </channel>.
# Reading from a file via getline avoids awk's "no newlines in -v" limitation.
TMP=$(mktemp)
awk -v itemfile="${ITEM_FILE}" '
    /<\/channel>/ {
        while ((getline line < itemfile) > 0) print line
        close(itemfile)
        print
        next
    }
    { print }
' "${APPCAST_LOCAL}" > "${TMP}"
mv "${TMP}" "${APPCAST_LOCAL}"
rm -f "${ITEM_FILE}"

# 9. Commit version bump + appcast entry, tag, push --------------------------
# Done before `gh release create` so the GitHub release tag points at this
# new commit (otherwise it would tag whatever HEAD is on the remote branch).
step "git commit + tag v${VERSION}"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git add "${INFO_PLIST}" "${APPCAST_LOCAL}"
git commit -m "chore(release): v${VERSION} (build ${NEW_BUILD})"
git tag -a "v${VERSION}" -m "Burrow v${VERSION}"
git push origin "${BRANCH}"
git push origin "v${VERSION}"

# 10. GitHub Release ---------------------------------------------------------
step "gh release create v${VERSION}"
gh release create "v${VERSION}" "${DMG_PATH}" "${ZIP_PATH}" \
    --repo "${GH_REPO}" \
    --title "v${VERSION}" \
    --generate-notes

# 11. Push appcast to gist ---------------------------------------------------
step "push appcast to gist ${GIST_ID}"
gh gist edit "${GIST_ID}" "${APPCAST_LOCAL}"

step "done — v${VERSION} live"
echo "  release: https://github.com/${GH_REPO}/releases/tag/v${VERSION}"
echo "  dmg:     https://github.com/${GH_REPO}/releases/download/v${VERSION}/Burrow-${VERSION}.dmg"
echo "  zip:     https://github.com/${GH_REPO}/releases/download/v${VERSION}/Burrow-${VERSION}.zip"
echo "  appcast: https://gist.githubusercontent.com/guide-vinh/${GIST_ID}/raw/appcast.xml"
