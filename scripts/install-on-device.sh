#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Honkumi.xcodeproj"
SCHEME="Honkumi"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DeviceDerivedData"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-1}"

DEVICE_ID="${DEVICE_ID:-}"
PROVISIONING_ARGS=()

if [[ "$ALLOW_PROVISIONING_UPDATES" != "0" ]]; then
  PROVISIONING_ARGS=(-allowProvisioningUpdates)
fi

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcrun devicectl list devices \
    | awk '/connected/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-Fa-f-]{36}$/) { print $i; exit } }')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No connected iOS device found. Connect a device or set DEVICE_ID." >&2
  exit 1
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${PROVISIONING_ARGS[@]}" \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Installed $SCHEME on device $DEVICE_ID"
