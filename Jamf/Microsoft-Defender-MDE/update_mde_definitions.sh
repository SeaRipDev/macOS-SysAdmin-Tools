#!/bin/zsh
###############################################################################
# Microsoft Defender (MDE) — Update Definitions + Phone Home
#
# Purpose:  Force Microsoft Defender for Endpoint to update its security
#           intelligence (virus definitions), wait until it reports current,
#           then run `jamf recon` so Jamf inventory reflects the new state.
#
#           Pattern: trigger update -> poll until healthy -> report back.
#           (Modeled on cocopuff2u's Trellix cmdagent loop, retargeted to the
#            mdatp CLI. Trellix's cmdagent is not used here.)
#
# Deploy:   Jamf Pro policy. Pairs with the companion Extension Attribute
#           (mde_definitions_status_ea.sh) and a Smart Group so stale machines
#           self-heal. See README.md for the full closed-loop wiring.
#
# Runs as:  root (standard Jamf behavior)
#
# Jamf Script Parameters:
#   $4 = Log file path   (default: /var/log/mde_defupdate.log)
#   $5 = Max wait seconds for definitions to report current (default: 300)
#
# Requires: Microsoft Defender for Endpoint installed (/usr/local/bin/mdatp)
#
# NOTE: Validate the mdatp field names/values on your own build before trusting
#       this at scale. Run `mdatp health` on a test Mac and confirm that
#       definitions_status returns "up_to_date" when current. Adjust the two
#       status comparisons below if your build reports a different value.
###############################################################################

###############################################################################
# CONFIGURATION
###############################################################################

scriptLog="${4:-/var/log/mde_defupdate.log}"   # $4 = log path
maxWaitSeconds="${5:-300}"                     # $5 = seconds to wait for "up_to_date"
mdatp="/usr/local/bin/mdatp"
pollInterval=15                                # seconds between status checks

###############################################################################
# LOGGING
###############################################################################

[ -f "$scriptLog" ] || touch "$scriptLog"
function log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$scriptLog"; }

###############################################################################
# PREFLIGHT
###############################################################################

if [[ ! -x "$mdatp" ]]; then
    log "ERROR: mdatp not found at $mdatp — Defender not installed. Exiting."
    exit 1
fi

log "MDE Definitions Update: starting"
beforeVer=$("$mdatp" health --field definitions_version 2>/dev/null | tr -d '"')
beforeStatus=$("$mdatp" health --field definitions_status 2>/dev/null | tr -d '"')
log "Before: version=${beforeVer:-unknown} status=${beforeStatus:-unknown}"

###############################################################################
# TRIGGER UPDATE
###############################################################################

log "Requesting definitions update..."
"$mdatp" definitions update 2>&1 | tee -a "$scriptLog"

###############################################################################
# POLL UNTIL CURRENT (or timeout — handles slow/limited egress gracefully)
###############################################################################

elapsed=0
while (( elapsed < maxWaitSeconds )); do
    status=$("$mdatp" health --field definitions_status 2>/dev/null | tr -d '"')
    if [[ "$status" == "up_to_date" ]]; then
        log "Definitions report up_to_date after ${elapsed}s"
        break
    fi
    log "status='${status:-unknown}' after ${elapsed}s — re-checking in ${pollInterval}s"
    sleep "$pollInterval"
    (( elapsed += pollInterval ))
done

afterVer=$("$mdatp" health --field definitions_version 2>/dev/null | tr -d '"')
afterStatus=$("$mdatp" health --field definitions_status 2>/dev/null | tr -d '"')
log "After: version=${afterVer:-unknown} status=${afterStatus:-unknown}"

###############################################################################
# PHONE HOME — force inventory update so Jamf + the EA reflect reality
###############################################################################

log "Forcing inventory update (jamf recon)..."
/usr/local/bin/jamf recon 2>&1 | tee -a "$scriptLog"

log "MDE Definitions Update: complete"

# Exit non-zero if still stale so it also surfaces in the Jamf policy log,
# not just the Extension Attribute / Smart Group.
[[ "$afterStatus" == "up_to_date" ]] && exit 0 || exit 1
