#!/bin/zsh
###############################################################################
# Microsoft Defender (MDE) — Pre-Deployment Validation / Field Dump
#
# Purpose:  READ-ONLY diagnostic. Run this once on a test Mac BEFORE deploying
#           the MDE definitions update scripts. It dumps the exact `mdatp health`
#           field names and values the production scripts rely on, so you can
#           confirm they match your Defender build (Microsoft occasionally
#           changes field names/values between versions).
#
#           Makes NO changes: it does not update definitions, does not run
#           recon, does not install anything.
#
# Run:      sudo zsh validate_mdatp_fields.sh
#           (Use sudo to mirror how Jamf runs scripts — root. Also works as a
#            normal user for comparison.)
#
# What to check in the output:
#   1. definitions_status shows "up_to_date" when the Mac IS current.
#      (This is the exact string the update scripts compare against.)
#   2. definitions_version and definitions_updated return sensible values.
#   3. mdatp behaves the same run as root vs. as your user.
###############################################################################

mdatp="/usr/local/bin/mdatp"
dialogPath="/usr/local/bin/dialog"

print_header() { echo; echo "==================================================================="; echo "  $1"; echo "==================================================================="; }

echo "MDE validation — $(date '+%Y-%m-%d %H:%M:%S')"
echo "Running as: $(/usr/bin/id -un) (uid $(/usr/bin/id -u))"

###############################################################################
print_header "1. Is Microsoft Defender installed?"
###############################################################################
if [[ -x "$mdatp" ]]; then
    echo "  FOUND: $mdatp"
    echo "  mdatp version: $("$mdatp" version 2>/dev/null | tr '\n' ' ')"
else
    echo "  NOT FOUND at $mdatp — the update scripts will exit early. Stop here."
    exit 1
fi

###############################################################################
print_header "2. Full 'mdatp health' output (reference for every field name)"
###############################################################################
"$mdatp" health 2>/dev/null

###############################################################################
print_header "3. The specific fields the production scripts use"
###############################################################################
# Read each field the scripts depend on and print it plainly.
for field in \
    definitions_status \
    definitions_version \
    definitions_updated \
    definitions_updated_minutes_ago \
    real_time_protection_enabled \
    healthy ; do
    value=$("$mdatp" health --field "$field" 2>/dev/null | tr -d '"')
    printf "  %-34s = %s\n" "$field" "${value:-<empty / field not present>}"
done

###############################################################################
print_header "4. Does the status match what the scripts expect?"
###############################################################################
status=$("$mdatp" health --field definitions_status 2>/dev/null | tr -d '"')
echo "  definitions_status currently = '${status:-<empty>}'"
if [[ "$status" == "up_to_date" ]]; then
    echo "  ✅ MATCH: scripts compare against exactly 'up_to_date' — no change needed."
else
    echo "  ⚠️  This Mac is NOT reporting 'up_to_date' right now."
    echo "     If you believe it IS current, then your build uses a different"
    echo "     value here. Note it and update the two status comparisons in"
    echo "     update_mde_definitions.sh and update_mde_definitions_gui.sh."
fi

###############################################################################
print_header "5. swiftDialog present? (only needed for the GUI variant)"
###############################################################################
if [[ -x "$dialogPath" ]]; then
    echo "  FOUND: $dialogPath (version $("$dialogPath" --version 2>/dev/null))"
else
    echo "  Not installed. The GUI script auto-installs it on first run (Team ID verified)."
fi

###############################################################################
print_header "6. Defender app icon path (used by the GUI variant)"
###############################################################################
iconfound="no"
for app in "/Applications/Microsoft Defender.app" "/Applications/Microsoft Defender ATP.app"; do
    if [[ -d "$app" ]]; then
        echo "  FOUND: $app"
        iconfound="yes"
    fi
done
[[ "$iconfound" == "no" ]] && echo "  No Defender .app at the known paths — GUI will use the SF Symbol fallback icon (fine)."

echo
echo "Validation complete. No changes were made to this Mac."
