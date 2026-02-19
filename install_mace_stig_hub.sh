#!/bin/bash
# ============================================================
# Install MACE STIG Hub from GitHub
# Jamf Self Service compatible
# ============================================================

APP_NAME="MACE STIG Hub"
APP_BUNDLE="MACE STIG Hub.app"
DMG_URL="https://github.com/MACE-App/MACE-STIG-Hub/releases/download/v1.0/M.A.C.E.STIG.Hub.V1.0.dmg"

INSTALL_PATH="/Applications"
TMP_DIR=$(mktemp -d)
DMG_PATH="$TMP_DIR/mace_stig_hub.dmg"
MOUNT_POINT="$TMP_DIR/dmg_mount"

echo "Starting installation of $APP_NAME..."

# ---- Download ----
echo "Downloading from GitHub..."
curl -L --silent --show-error --fail \
    -o "$DMG_PATH" \
    "$DMG_URL"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Download failed. Check the URL or network connection."
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "Download complete."

# ---- Mount DMG ----
echo "Mounting disk image..."
mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" \
    -mountpoint "$MOUNT_POINT" \
    -nobrowse \
    -quiet

if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to mount DMG."
    rm -rf "$TMP_DIR"
    exit 1
fi

# ---- Copy App ----
if [[ ! -d "$MOUNT_POINT/$APP_BUNDLE" ]]; then
    echo "ERROR: Could not find '$APP_BUNDLE' inside the DMG."
    hdiutil detach "$MOUNT_POINT" -quiet
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "Installing $APP_NAME to $INSTALL_PATH..."

# Remove existing version if present
if [[ -d "$INSTALL_PATH/$APP_BUNDLE" ]]; then
    rm -rf "$INSTALL_PATH/$APP_BUNDLE"
fi

cp -R "$MOUNT_POINT/$APP_BUNDLE" "$INSTALL_PATH/"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to copy app to $INSTALL_PATH."
    hdiutil detach "$MOUNT_POINT" -quiet
    rm -rf "$TMP_DIR"
    exit 1
fi

# ---- Cleanup ----
echo "Cleaning up..."
hdiutil detach "$MOUNT_POINT" -quiet
rm -rf "$TMP_DIR"

echo "$APP_NAME installed successfully."
exit 0
