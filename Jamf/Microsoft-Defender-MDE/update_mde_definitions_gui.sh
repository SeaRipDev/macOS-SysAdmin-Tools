#!/bin/zsh
###############################################################################
# Microsoft Defender (MDE) — Update Definitions (swiftDialog GUI)
#
# Purpose:  User-facing version of update_mde_definitions.sh. Shows a
#           swiftDialog progress window while Microsoft Defender updates its
#           security intelligence (virus definitions), live-updates the window
#           with the current version/status, then runs `jamf recon` to report
#           the result back to Jamf.
#
#           Pattern/structure modeled on cocopuff2u's Trellix GUI loop,
#           retargeted to the mdatp CLI. Instead of a fixed loop count, the
#           progress bar is driven by polling until Defender reports current.
#
# Deploy:   Jamf Pro Self Service policy (gives the user a "Update Antivirus
#           Definitions" button with visible progress).
#
# Runs as:  root (standard Jamf behavior). swiftDialog renders in the active
#           user session automatically.
#
# Jamf Script Parameters:
#   $4 = Log file path   (default: /var/log/mde_defupdate_gui.log)
#   $5 = Max wait seconds for definitions to report current (default: 300)
#
# Requires: Microsoft Defender for Endpoint (/usr/local/bin/mdatp).
#           swiftDialog is auto-installed if missing (Team ID verified).
#
# NOTE: Validate `mdatp` field names/values on your build. Run `mdatp health`
#       on a test Mac and confirm definitions_status returns "up_to_date" when
#       current; adjust the comparison below if your build differs.
###############################################################################

###############################################################################
# CONFIGURATION
###############################################################################

ScriptVersion="1.0"
mdatp="/usr/local/bin/mdatp"
scriptLog="${4:-/var/log/mde_defupdate_gui.log}"
maxWaitSeconds="${5:-300}"
pollInterval=15

dialogPath="/usr/local/bin/dialog"
dialogApp="/Library/Application Support/Dialog/Dialog.app"
swiftDialogMinimumRequiredVersion="2.3.0"
expectedDialogTeamID="PWA5E9TQ59"
dialogCommandFile=$(mktemp /var/tmp/mdeDefUpdate.XXXXX) && chmod 644 "$dialogCommandFile"

title="Antivirus Definitions Update"
message="Microsoft Defender is checking for the latest virus definitions. This window will update automatically and close when finished."
helpmessage="This updates Microsoft Defender's security intelligence (virus definitions), waits until the endpoint reports current, then reports the result back to Jamf.

Command run: mdatp definitions update"

###############################################################################
# LOGGING
###############################################################################

[[ -f "$scriptLog" ]] || touch "$scriptLog"
function log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$scriptLog"; }

log "MDE Definitions GUI: starting (v$ScriptVersion)"

###############################################################################
# PREFLIGHT: Defender present?
###############################################################################

if [[ ! -x "$mdatp" ]]; then
    log "ERROR: mdatp not found at $mdatp — Defender not installed. Exiting."
    /bin/rm -f "$dialogCommandFile"
    exit 1
fi

###############################################################################
# PREFLIGHT: Icon (Defender app icon, else SF Symbol fallback)
###############################################################################

icon="SF=shield.lefthalf.filled,colour=blue,weight=bold"
for app in "/Applications/Microsoft Defender.app" "/Applications/Microsoft Defender ATP.app"; do
    if [[ -d "$app" ]]; then
        icon="$app"
        break
    fi
done
log "Using icon: $icon"

###############################################################################
# PREFLIGHT: Validate / install swiftDialog (Team ID verified)
###############################################################################

function dialogInstall() {
    dialogURL=$(curl -L --silent --fail "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
    log "Installing swiftDialog from $dialogURL"
    tempDirectory=$(/usr/bin/mktemp -d "/private/tmp/dialog.XXXXXX")
    /usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"
    teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
    if [[ "$expectedDialogTeamID" == "$teamID" ]]; then
        /usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
        sleep 2
        log "swiftDialog $("$dialogPath" --version) installed"
    else
        log "ERROR: swiftDialog Team ID verification failed (got '$teamID'). Aborting."
        /bin/rm -Rf "$tempDirectory"; /bin/rm -f "$dialogCommandFile"
        exit 1
    fi
    /bin/rm -Rf "$tempDirectory"
}

function dialogCheck() {
    if [[ ! -e "$dialogApp" ]]; then
        log "swiftDialog not found — installing"
        dialogInstall
    elif [[ "$("$dialogPath" --version)" < "$swiftDialogMinimumRequiredVersion" ]]; then
        log "swiftDialog older than $swiftDialogMinimumRequiredVersion — updating"
        dialogInstall
    else
        log "swiftDialog $("$dialogPath" --version) present"
    fi
}

dialogCheck

# Keep the Mac awake for the duration
caffeinate -dimsu &
caffeinatePID=$!
log "caffeinate started (PID $caffeinatePID)"

###############################################################################
# HELPERS
###############################################################################

function dialog_command() { echo "$@" >> "$dialogCommandFile"; sleep 0.1; }

# mdatp health field reader
function mde() { "$mdatp" health --field "$1" 2>/dev/null | tr -d '"'; }

# Build the message body from current MDE state
function stateMessage() {
    local ver="$1" status="$2" updated="$3"
    echo "$message <br><br>**Current State**<br>Definitions Version: \`${ver:-unknown}\`<br>Status: \`${status:-unknown}\`<br>Last Updated: \`${updated:-unknown}\`"
}

function cleanup_exit() {
    dialog_command "quit:"
    /bin/rm -f "$dialogCommandFile"
    kill "$caffeinatePID" 2>/dev/null
    log "MDE Definitions GUI: cleaned up"
    exit "${1:-0}"
}

function check_dialog_process() {
    if ! ps -p "$dialogPID" > /dev/null; then
        log "User closed the window — exiting early"
        /bin/rm -f "$dialogCommandFile"
        kill "$caffeinatePID" 2>/dev/null
        exit 0
    fi
}

###############################################################################
# INITIAL STATE + LAUNCH PROGRESS WINDOW
###############################################################################

beforeVer=$(mde definitions_version)
status=$(mde definitions_status)
updated=$(mde definitions_updated)
log "Before: version=${beforeVer:-unknown} status=${status:-unknown} updated=${updated:-unknown}"

# Progress steps = number of polls we could make within the timeout
steps=$(( maxWaitSeconds / pollInterval ))
(( steps < 1 )) && steps=1

"$dialogPath" \
    --title "$title" \
    --message "$(stateMessage "$beforeVer" "$status" "$updated")" \
    --icon "$icon" \
    --small \
    --ontop \
    --moveable \
    --messagefont "size=13" \
    --progress "$steps" \
    --progresstext "Starting..." \
    --button1text "Run in Background" \
    --helpmessage "$helpmessage" \
    --infotext "v$ScriptVersion" \
    --commandfile "$dialogCommandFile" &
dialogPID=$!
log "swiftDialog started (PID $dialogPID)"
sleep 1

###############################################################################
# TRIGGER UPDATE + POLL UNTIL CURRENT (advancing the progress bar)
###############################################################################

dialog_command "progresstext: Requesting definitions update..."
log "Requesting definitions update"
"$mdatp" definitions update &>/dev/null

elapsed=0
while (( elapsed < maxWaitSeconds )); do
    check_dialog_process
    status=$(mde definitions_status)
    ver=$(mde definitions_version)
    updated=$(mde definitions_updated)
    dialog_command "message: $(stateMessage "$ver" "$status" "$updated")"

    if [[ "$status" == "up_to_date" ]]; then
        log "Definitions up_to_date after ${elapsed}s (version $ver)"
        dialog_command "progress: complete"
        dialog_command "progresstext: Definitions are up to date"
        break
    fi

    dialog_command "progress: increment"
    dialog_command "progresstext: Updating... (status: ${status:-checking}, ${elapsed}s elapsed)"
    log "status='${status:-unknown}' after ${elapsed}s"
    sleep "$pollInterval"
    (( elapsed += pollInterval ))
done

afterStatus=$(mde definitions_status)
afterVer=$(mde definitions_version)
log "After: version=${afterVer:-unknown} status=${afterStatus:-unknown}"

###############################################################################
# PHONE HOME + FINISH
###############################################################################

check_dialog_process
dialog_command "progresstext: Reporting status to Jamf..."
log "Forcing inventory update (jamf recon)"
/usr/local/bin/jamf recon &>/dev/null

if [[ "$afterStatus" == "up_to_date" ]]; then
    dialog_command "message: ✅ **Your antivirus definitions are up to date.**<br><br>Version: \`${afterVer:-unknown}\`<br>You can close this window."
    dialog_command "progresstext: Done"
    finalCode=0
else
    dialog_command "message: ⚠️ **Definitions did not report current within the time limit.**<br><br>Current status: \`${afterStatus:-unknown}\`<br>Check your network connection and try again, or contact IT."
    dialog_command "progresstext: Finished with warnings"
    finalCode=1
fi

sleep 4
cleanup_exit "$finalCode"
