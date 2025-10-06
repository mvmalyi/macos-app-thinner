#!/bin/bash

# ==============================================================================
#
# macOS App Thinner
#
# A script to find Universal macOS applications and strip the non-native
# architecture (x86_64) to save disk space on Apple Silicon Macs.
#
# Author: Your Name
# Version: 1.0.0
# License: MIT
#
# ==============================================================================

# --- Configuration ---

# An array of application names (e.g., "Safari.app") to exclude from processing.
EXCLUDED_APPS=(
    "Safari.app"
)

# --- ANSI Color Codes for Better Output ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'

# --- Functions ---

# Helper function to check if an item is in an array
# Usage: contains_element "item" "${array[@]}"
contains_element() {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

# --- Main Logic ---

echo -e "${C_BLUE}${C_BOLD}macOS App Thinner${C_RESET}"
echo "This script will scan for Universal apps and offer to remove the Intel (x86_64) portion."
echo ""

# 1. Architecture Check: Ensure the script is running on an Apple Silicon Mac.
if ! [[ "$(uname -m)" == "arm64" ]]; then
    echo -e "${C_RED}Error: This script is designed to run only on Apple Silicon (arm64) Macs.${C_RESET}"
    exit 1
fi

echo -e "🔎 ${C_YELLOW}Scanning /Applications for Universal Binaries...${C_RESET}"
echo "--------------------------------------------------"

UNIVERSAL_BINARIES=()
UNIVERSAL_APP_NAMES=()

# 2. Find Universal Apps: Loop through all .app bundles.
for APP_PATH in "/Applications"/*.app; do
    APP_FILENAME=$(basename "$APP_PATH")

    # Skip if the app is in our exclusion list.
    if contains_element "$APP_FILENAME" "${EXCLUDED_APPS[@]}"; then
        echo -e "➡️  Skipping excluded app: \"${APP_FILENAME%.app}\""
        continue
    fi

    # Define paths for the Info.plist and the main executable.
    PLIST_PATH="${APP_PATH}/Contents/Info.plist"
    [ ! -f "$PLIST_PATH" ] && continue

    EXECUTABLE_NAME=$(defaults read "${PLIST_PATH}" CFBundleExecutable 2>/dev/null)
    [ -z "$EXECUTABLE_NAME" ] && continue
    
    BINARY_PATH="${APP_PATH}/Contents/MacOS/${EXECUTABLE_NAME}"

    # Check if the binary exists and is a "fat" file with both architectures.
    if [ -f "$BINARY_PATH" ]; then
        ARCH_INFO=$(lipo -info "$BINARY_PATH" 2>/dev/null)

        if echo "$ARCH_INFO" | grep -q "x86_64" && echo "$ARCH_INFO" | grep -q "arm64"; then
            APP_NAME=$(basename "$APP_PATH" .app)
            echo -e "✅ Found: \"${C_BOLD}${APP_NAME}${C_RESET}\""
            
            UNIVERSAL_BINARIES+=("$BINARY_PATH")
            UNIVERSAL_APP_NAMES+=("$APP_NAME")
        fi
    fi
done

echo "--------------------------------------------------"

# 3. Confirmation and Processing
if [ ${#UNIVERSAL_BINARIES[@]} -eq 0 ]; then
    echo -e "👍 ${C_GREEN}No Universal applications requiring changes were found. All done!${C_RESET}"
    exit 0
fi

echo -e "The following ${C_BOLD}${C_YELLOW}${#UNIVERSAL_BINARIES[@]}${C_RESET} Universal application(s) can be thinned:"
printf " - %s\n" "${UNIVERSAL_APP_NAMES[@]}"
echo ""
echo -e "${C_YELLOW}${C_BOLD}Important:${C_RESET} This operation modifies application files and requires administrator privileges."
echo -e "On its first run, macOS may ask you to grant ${C_BOLD}Terminal${C_RESET} permission for ${C_BOLD}'App Management'${C_RESET} in System Settings."
echo ""

read -p "Do you want to strip the Intel binary from ALL of these apps? (y/n): " CONFIRMATION
LOWER_CONFIRMATION=$(echo "$CONFIRMATION" | tr '[:upper:]' '[:lower:]')

if [[ "$LOWER_CONFIRMATION" == "y" || "$LOWER_CONFIRMATION" == "yes" ]]; then
    echo ""
    echo -e "🚀 ${C_BLUE}Stripping binaries... You will be prompted for your password.${C_RESET}"
    
    PROCESSED_COUNT=0
    for BINARY_PATH in "${UNIVERSAL_BINARIES[@]}"; do
        # Use sudo with the lipo command to request privileges only when needed.
        if sudo lipo -remove x86_64 -output "$BINARY_PATH" "$BINARY_PATH"; then
            ((PROCESSED_COUNT++))
        else
            APP_NAME_FROM_PATH=$(basename "$(dirname "$(dirname "$BINARY_PATH")")" .app)
            echo -e "${C_RED}Failed to strip binary for \"${APP_NAME_FROM_PATH}\".${C_RESET}"
        fi
    done
    
    echo "--------------------------------------------------"
    echo -e "✨ ${C_GREEN}All done. Processed ${PROCESSED_COUNT} application(s).${C_RESET}"
else
    echo -e "👍 ${C_YELLOW}Operation cancelled. No changes were made.${C_RESET}"
fi

echo "--------------------------------------------------"
exit 0
