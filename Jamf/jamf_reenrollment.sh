#!/bin/bash
###############################################################################
# Jamf Pro Re-enrollment Script
# Purpose:  Removes the existing MDM profile and redirects the user to
#           enroll in the new Jamf Pro server (URL change, same hardware).
#
# Deploy:   Jamf Pro Self Service policy
# Runs as:  root (standard Jamf behavior)
#
# Jamf Script Parameters:
#   $4 = New Jamf Pro enrollment URL
#        Example: https://[NEW-JAMF-URL]/enroll
#        If left blank, script will prompt the user to contact IT.
#
# Tested on: macOS 13 (Ventura), macOS 14 (Sonoma), macOS 15 (Sequoia)
###############################################################################

###############################################################################
# CONFIGURATION
###############################################################################

NEW_ENROLLMENT_URL="${4}"   # Passed in as Jamf script parameter $4
DIALOG_TITLE="IT Management Update"
IT_CONTACT="[IT_CONTACT_INFO]"   # FILL IN: name, email, Teams channel, phone, etc.
LOG_FILE="/var/log/jamf_reenrollment.log"

###############################################################################
# LOGGING
###############################################################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" | tee -a "$LOG_FILE"
}

log "=============================="
log "Jamf Re-enrollment script started"
log "macOS version: $(sw_vers -productVersion)"
log "Script parameter (new URL): ${NEW_ENROLLMENT_URL:-NOT PROVIDED}"

###############################################################################
# PREFLIGHT CHECKS
###############################################################################

# Get the logged-in user (needed to open browser as them, not root)
LOGGED_IN_USER=$(stat -f "%Su" /dev/console 2>/dev/null)

if [ -z "$LOGGED_IN_USER" ] || [ "$LOGGED_IN_USER" = "root" ]; then
    log "ERROR: Could not determine logged-in user. Aborting."
    /usr/bin/osascript -e "display dialog \"This script must be run while a user is logged in.\n\nPlease contact $IT_CONTACT.\" buttons {\"OK\"} default button \"OK\" with title \"$DIALOG_TITLE\" with icon stop"
    exit 1
fi

log "Logged-in user: $LOGGED_IN_USER"

# Validate enrollment URL was provided
if [ -z "$NEW_ENROLLMENT_URL" ]; then
    log "ERROR: New enrollment URL not provided in script parameter 4."
    /usr/bin/osascript -e "display dialog \"Configuration error: enrollment URL not set.\n\nPlease contact $IT_CONTACT for assistance.\" buttons {\"OK\"} default button \"OK\" with title \"$DIALOG_TITLE\" with icon stop"
    exit 1
fi

# Check if an MDM profile is actually enrolled
MDM_PRESENT=$(profiles list -type enrollment 2>/dev/null | grep -c "MDM\|com.apple.mdm\|ManagementProfile" || true)
if [ "$MDM_PRESENT" -eq 0 ]; then
    log "WARNING: No MDM enrollment profile detected. Machine may already be unenrolled."
    /usr/bin/osascript -e "display dialog \"No management profile was found on this Mac.\n\nIf you have not already enrolled, click OK to open enrollment.\n\nIf this is unexpected, contact $IT_CONTACT.\" buttons {\"Cancel\", \"Open Enrollment\"} default button \"Open Enrollment\" with title \"$DIALOG_TITLE\" with icon caution"
    DIALOG_RESULT=$?
    if [ "$DIALOG_RESULT" -eq 0 ]; then
        log "User chose to open enrollment despite no MDM profile found."
        sudo -u "$LOGGED_IN_USER" /usr/bin/open "$NEW_ENROLLMENT_URL"
    fi
    exit 0
fi

###############################################################################
# STEP 1 — WARN USER
###############################################################################

log "Presenting Step 1 dialog to user..."

USER_CHOICE=$(/usr/bin/osascript <<EOF
button returned of (display dialog "Your Mac needs to be updated to connect to the new IT management server.

This process has 2 steps:

  Step 1 of 2 — Remove old management profile
  Step 2 of 2 — Enroll in new server (browser will open)

This will take about 2 minutes. Please do not shut down or close your Mac.

Click Continue when ready." buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with title "$DIALOG_TITLE" with icon caution)
EOF
)

if [ "$USER_CHOICE" != "Continue" ]; then
    log "User cancelled at Step 1 dialog."
    exit 0
fi

###############################################################################
# STEP 2 — REMOVE OLD MDM PROFILE
###############################################################################

log "Step 1: Removing old MDM enrollment profile..."

# Primary method: remove by type (works macOS 12+)
profiles remove -type enrollment 2>/dev/null
REMOVE_RESULT=$?

# Allow time for the removal to complete
sleep 3

# Verify removal
MDM_STILL_PRESENT=$(profiles list -type enrollment 2>/dev/null | grep -c "MDM\|com.apple.mdm\|ManagementProfile" || true)

if [ "$MDM_STILL_PRESENT" -gt 0 ]; then
    log "Primary removal failed or profile persists. Trying identifier-based removal..."

    # Fallback: get identifier and remove specifically
    MDM_IDENTIFIER=$(profiles list -type enrollment 2>/dev/null | awk -F'[()]' '/MDM|mdm/{print $2}' | head -1)

    if [ -n "$MDM_IDENTIFIER" ]; then
        log "Attempting removal by identifier: $MDM_IDENTIFIER"
        profiles remove -identifier "$MDM_IDENTIFIER" 2>/dev/null
        sleep 3
    fi

    # Last resort: direct system removal
    MDM_STILL_PRESENT=$(profiles list -type enrollment 2>/dev/null | grep -c "MDM\|com.apple.mdm\|ManagementProfile" || true)
    if [ "$MDM_STILL_PRESENT" -gt 0 ]; then
        log "ERROR: Could not remove MDM profile automatically."
        /usr/bin/osascript -e "display dialog \"Could not automatically remove the management profile.\n\nPlease go to:\nSystem Settings → Privacy & Security → Profiles\n\nRemove the MDM profile manually, then contact $IT_CONTACT to complete enrollment.\" buttons {\"OK\"} default button \"OK\" with title \"$DIALOG_TITLE\" with icon stop"
        exit 1
    fi
fi

log "Step 1 complete: MDM profile removed successfully."

###############################################################################
# STEP 3 — REDIRECT TO NEW ENROLLMENT
###############################################################################

log "Step 2: Presenting enrollment dialog..."

/usr/bin/osascript <<EOF
display dialog "Step 1 complete — management profile removed.

Step 2 of 2: A browser window will now open to the new enrollment page.

Please:
  1. Log in with your network credentials
  2. Follow the on-screen prompts
  3. Approve the new management profile when prompted in System Settings

Click Open Enrollment to continue." buttons {"Open Enrollment"} default button "Open Enrollment" with title "$DIALOG_TITLE"
EOF

log "Opening enrollment URL: $NEW_ENROLLMENT_URL"
sudo -u "$LOGGED_IN_USER" /usr/bin/open "$NEW_ENROLLMENT_URL"

###############################################################################
# STEP 4 — CLOSING INSTRUCTIONS
###############################################################################

sleep 2

/usr/bin/osascript <<EOF
display dialog "Browser is open to the enrollment page.

After enrolling:
  • Approve the new profile in System Settings → Privacy & Security → Profiles
  • Reply to the IT notification email to confirm completion

If you have trouble, contact $IT_CONTACT." buttons {"Done"} default button "Done" with title "$DIALOG_TITLE"
EOF

log "Re-enrollment script completed successfully for user: $LOGGED_IN_USER"
log "=============================="

exit 0
