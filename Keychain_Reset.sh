#!/bin/bash
#set -x

####################################################################################################
#
# # Reset User Keychain
#
# Purpose: Resets all of the users local keychain
#
# https://github.com/cocopuff2u
#
####################################################################################################
#
#   History
#
#  1.0 04/10/24 Original
#
#
####################################################################################################

# Define necessary variables
scriptLog="/private/var/log/Reset_User_Keychain.log"
icon="/System/Library/CoreServices/Applications/Keychain Access.app/Contents/Resources/AppIcon.icns"
ScriptVersion="1.0"
# Path to the dialog binary
dialogPath='/usr/local/bin/dialog'
currentUser=$(stat -f "%Su" /dev/console)

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${scriptLog}" ]]; then
    mkdir -p "$(dirname "${scriptLog}")"
    touch "${scriptLog}"
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Client-side Script Logging Function
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    echo -e "$( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

updateScriptLog "Reset User Keychain: Starting...."

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Checking for Icon Availability
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

updateScriptLog "Reset User Keychain: Checking for icon path...."
if [ ! -e "$icon" ]; then
    updateScriptLog "Reset User Keychain: icon path not valid, using default icon...."
    icon="SF=clock.arrow.2.circlepath,colour=green,colour2=blue,weight=bold"
else
    updateScriptLog "Reset User Keychain: Icon valid, proceeding...."
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / install swiftDialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogInstall() {
    dialogURL=$(curl -L --silent --fail "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
    expectedDialogTeamID="PWA5E9TQ59"
    updateScriptLog "Reset User Keychain: Installing swiftDialog...."
    workDirectory=$( /usr/bin/basename "$0" )
    tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )
    /usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"
    teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
    if [[ "$expectedDialogTeamID" == "$teamID" ]]; then
        /usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
        sleep 2
        dialogVersion=$( /usr/local/bin/dialog --version )
        updateScriptLog "Reset User Keychain: swiftDialog version ${dialogVersion} installed; proceeding...."
    else
        osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "Self Heal Your Mac: Error" buttons {"Close"} with icon caution' & exit 0
    fi
    /bin/rm -Rf "$tempDirectory"
}

function dialogCheck() {
    if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then
        updateScriptLog "Reset User Keychain: swiftDialog not found. Installing...."
        dialogInstall
    else
        dialogVersion=$(/usr/local/bin/dialog --version)
        if [[ "${dialogVersion}" < "${swiftDialogMinimumRequiredVersion}" ]]; then
            updateScriptLog "Reset User Keychain: swiftDialog version ${dialogVersion} found but swiftDialog ${swiftDialogMinimumRequiredVersion} or newer is required; updating...."
            dialogInstall
        else
            updateScriptLog "Reset User Keychain: swiftDialog version ${dialogVersion} found; proceeding...."
        fi
    fi
}

dialogCheck

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Main Workflow
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

updateScriptLog "Reset User Keychain: Prompting user for keychain reset...."
prompt_user=$(
    $dialogPath \
    --title "Keychain Reset" \
    --message "Do you want to delete all your local keychain? <br><br> /Users/$currentUser/Library/Keychains/*" \
    --ontop \
    --moveable \
    --icon "$icon" \
    --mini \
    --messagefont "size=14" \
    --button1 \
    --button1text "Yes" \
    --button2 \
    --button2text "No" \
    --infotext "   V $ScriptVersion" \
)
dialog_exit_status=$?

if [[ $dialog_exit_status == 0 ]]; then
    updateScriptLog "Reset User Keychain: User chose to delete the keychain."
    # User chose to delete the keychain
    rm -Rf /Users/$currentUser/Library/Keychains/*

    updateScriptLog "Reset User Keychain: Prompting user to reboot...."
    reboot_prompt=$(
        $dialogPath \
        --title "Reboot Recommended" \
        --message "It is recommended to reboot your system to complete the keychain reset. Would you like to reboot now?" \
        --ontop \
        --moveable \
        --icon "$icon" \
        --mini \
        --messagefont "size=14" \
        --button1 \
        --button1text "Reboot Now" \
        --button2 \
        --button2text "Reboot Later" \
        --infotext "   V $ScriptVersion" \
    )
    reboot_exit_status=$?

    if [[ $reboot_exit_status == 0 ]]; then
        updateScriptLog "Reset User Keychain: User chose to reboot now."
        # User chose to reboot now
        reboot
    else
        updateScriptLog "Reset User Keychain: User chose to reboot later."
        # User chose to reboot later
    fi
else
    updateScriptLog "Reset User Keychain: User chose not to delete the keychain."
    # User chose not to delete the keychain
fi
