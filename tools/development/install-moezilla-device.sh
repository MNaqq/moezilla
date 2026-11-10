#!/bin/zsh
# Build and install signed Moezilla on a paired iPhone.
set -euo pipefail

: "${TEAM_ID:?Set Apple development team ID}"
: "${DEVICE_UDID:?Set paired iPhone UDID}"

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_ROOT="${BUILD_ROOT:-${HOME}/.moezilla-build}"
DERIVED_DATA="${BUILD_ROOT}/DerivedData"
LOG_DIR="${BUILD_ROOT}/logs"

mkdir -p "${DERIVED_DATA}" "${LOG_DIR}"
export DEVELOPER_DIR
EXPECTED_BUNDLE_ID="com.bonewizardry.Moezilla"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphoneos/Reynard.app"
PROJECT="${ROOT_DIR}/browser/Reynard.xcodeproj"

echo "Building Moezilla for paired iOS device..."
/usr/bin/xcodebuild \
    -project "${PROJECT}" \
    -scheme Reynard \
    -configuration Debug \
    -sdk iphoneos \
    -destination "id=${DEVICE_UDID}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_STYLE=Automatic \
    build 2>&1 | tee "${LOG_DIR}/moezilla-device-build.log"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "Compiled app is missing: ${APP_PATH}" >&2
    exit 1
fi

ACTUAL_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "${APP_PATH}/Info.plist")
if [[ "${ACTUAL_BUNDLE_ID}" != "${EXPECTED_BUNDLE_ID}" ]]; then
    echo "Unexpected browser bundle ID: ${ACTUAL_BUNDLE_ID}" >&2
    exit 1
fi

# Xcode's `Copy Gecko Stuff` phase can refresh the signed Gecko frameworks
# during an incremental build *after* the enclosing app's resource seal was
# written. Re-seal only the outer app with the identity Xcode selected.
if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"; then
    SIGNER=$(/usr/bin/codesign --display --verbose=3 "${APP_PATH}" 2>&1 \
        | /usr/bin/sed -n 's/^Authority=\(Apple Development:.*\)$/\1/p' \
        | /usr/bin/head -n 1)
    if [[ -z "${SIGNER}" ]]; then
        echo "Could not determine the Xcode development signing identity" >&2
        exit 1
    fi
    echo "Refreshing outer app resource seal after Gecko framework copying..."
    /usr/bin/codesign --force --sign "${SIGNER}" \
        --preserve-metadata=entitlements,requirements,flags "${APP_PATH}"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
fi

echo "Installing ${EXPECTED_BUNDLE_ID} on paired iPhone..."
/usr/bin/xcrun devicectl device install app \
    --device "${DEVICE_UDID}" "${APP_PATH}"

echo "Confirming installation..."
/usr/bin/xcrun devicectl device info apps \
    --device "${DEVICE_UDID}" | grep -F "${EXPECTED_BUNDLE_ID}"

echo "Launching installed Moezilla..."
/usr/bin/xcrun devicectl device process launch \
    --device "${DEVICE_UDID}" "${EXPECTED_BUNDLE_ID}"

echo "Moezilla installed and launched on the paired device."
