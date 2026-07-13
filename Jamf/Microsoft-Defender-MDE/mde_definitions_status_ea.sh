#!/bin/zsh
###############################################################################
# Extension Attribute — Microsoft Defender (MDE) Definitions Status
#
# Purpose:  Reports Microsoft Defender's current definitions status into Jamf
#           inventory so you can build a Smart Group of stale machines and
#           confirm "I'm up to date now" after remediation.
#
# Jamf setup: Computers > Extension Attributes > New
#   - Data Type:  String
#   - Input Type: Script
#   - Paste this script
#
# Typical values returned by definitions_status: up_to_date, could_be_older,
# updating, not_found, disabled. Confirm against `mdatp health` on your build.
#
# Runs as:  root (standard Jamf behavior)
###############################################################################

mdatp="/usr/local/bin/mdatp"

if [[ ! -x "$mdatp" ]]; then
    echo "<result>Not Installed</result>"
    exit 0
fi

status=$("$mdatp" health --field definitions_status 2>/dev/null | tr -d '"')
echo "<result>${status:-unknown}</result>"
