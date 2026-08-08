#!/bin/bash

# ==============================================================================
#
# macOS App Thinner
#
# A script to find Universal macOS applications and strip the non-native
# architecture (x86_64) to save disk space on Apple Silicon Macs.
#
# Author: Your Name
# Version: 1.1.0
# License: MIT
#
# Options:
#   -n, --dry-run             Scan and report (with size estimates) only; never
#                             modifies anything.
#       --safe                Also skip security-sensitive and dev/system apps
#                             (password managers, MFA, VPNs, finance, Xcode...).
#       --resign              After stripping, re-apply an ad-hoc code signature
#                             so the binary keeps a valid (ad-hoc) signature.
#   -h, --help                Show this help and exit.
#
# ==============================================================================

# --- Configuration ---

# An array of application names (e.g., "Safari.app") to exclude from processing.
EXCLUDED_APPS=(
    "Safari.app"
)

# Additional exact app bundle names skipped only in --safe mode.
SAFE_EXCLUDED_APPS=(
    "Xcode.app"
    "Android Studio.app"
    "Developer.app"
    "TestFlight.app"
)

# Name substrings (case-insensitive) skipped only in --safe mode. These target
# security-sensitive / signature-fragile categories.
SAFE_EXCLUDED_PATTERNS=(
    # Password managers / secrets
    "1password" "bitwarden" "keeper" "dashlane" "lastpass" "enpass" "nordpass" "proton pass" "secretive"
    # MFA / identity / auth
    "okta" "authy" "duo" "yubico" "yubikey" "google authenticator"
    # VPN / network security
    "vpn" "wireguard" "tailscale" "little snitch" "lulu" "cloudflare warp" "mullvad" "proton vpn" "tunnelblick"
    # Finance / banking / crypto wallets
    "ledger" "trezor" "exodus" "coinbase" "metamask"
    # Endpoint / MDM / security agents
    "crowdstrike" "sentinelone" "jamf" "kandji" "sophos" "malwarebytes" "objective-see" "knockknock" "blockblock"
)

# --- ANSI Color Codes for Better Output ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'

# --- Option Parsing ---
DRY_RUN=false
SAFE_MODE=false
RESIGN=false

print_usage() {
    cat <<EOF
macOS App Thinner

Usage: $(basename "$0") [options]

Options:
  -n, --dry-run    Scan and report (with size estimates) only; never modifies.
      --safe       Also skip security-sensitive and dev/system apps.
      --resign     Re-apply an ad-hoc code signature after stripping.
  -h, --help       Show this help and exit.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true ;;
        --safe|--exclude-sensitive) SAFE_MODE=true ;;
        --resign) RESIGN=true ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo -e "${C_RED}Unknown option: $1${C_RESET}"; print_usage; exit 1 ;;
    esac
    shift
done

# --- Functions ---

# Helper function to check if an item is in an array
# Usage: contains_element "item" "${array[@]}"
contains_element() {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

# Lowercase a string (portable across bash 3.2).
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Decide whether an app bundle should be skipped, honoring --safe mode.
should_exclude() {
    local filename="$1"
    contains_element "$filename" "${EXCLUDED_APPS[@]}" && return 0
    if $SAFE_MODE; then
        contains_element "$filename" "${SAFE_EXCLUDED_APPS[@]}" && return 0
        local name_lc p
        name_lc=$(to_lower "${filename%.app}")
        for p in "${SAFE_EXCLUDED_PATTERNS[@]}"; do
            [[ "$name_lc" == *"$p"* ]] && return 0
        done
    fi
    return 1
}

# --- Main Logic ---

echo -e "${C_BLUE}${C_BOLD}macOS App Thinner${C_RESET}"
echo "This script will scan for Universal apps and offer to remove the Intel (x86_64) portion."
$SAFE_MODE && echo -e "${C_BLUE}Safe mode: security-sensitive and dev/system apps will be skipped.${C_RESET}"
$DRY_RUN && echo -e "${C_YELLOW}Dry run: nothing will be modified.${C_RESET}"
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
TOTAL_SAVE_BYTES=0

# 2. Find Universal Apps: Loop through all .app bundles.
for APP_PATH in "/Applications"/*.app; do
    APP_FILENAME=$(basename "$APP_PATH")

    # Skip if the app is excluded (always-excluded, or --safe categories).
    if should_exclude "$APP_FILENAME"; then
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

            # Estimate the reclaimable space (size of the x86_64 slice).
            SLICE_BYTES=$(lipo -detailed_info "$BINARY_PATH" 2>/dev/null | awk '/architecture x86_64/{f=1} f&&/^ *size /{print $2; exit}')
            [ -z "$SLICE_BYTES" ] && SLICE_BYTES=0
            TOTAL_SAVE_BYTES=$((TOTAL_SAVE_BYTES + SLICE_BYTES))

            echo -e "✅ Found: \"${C_BOLD}${APP_NAME}${C_RESET}\" (~$((SLICE_BYTES / 1048576)) MB)"

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
echo -e "Estimated reclaimable space: ${C_BOLD}~$((TOTAL_SAVE_BYTES / 1048576)) MB${C_RESET}"
echo ""

# In dry-run mode, stop here without modifying anything.
if $DRY_RUN; then
    echo -e "${C_YELLOW}Dry run complete. Re-run without --dry-run to apply.${C_RESET}"
    exit 0
fi

echo -e "${C_YELLOW}${C_BOLD}Important:${C_RESET} This operation modifies application files and requires administrator privileges."
echo -e "On its first run, macOS may ask you to grant ${C_BOLD}Terminal${C_RESET} permission for ${C_BOLD}'App Management'${C_RESET} in System Settings."
echo ""

read -p "Do you want to strip the Intel binary from ALL of these apps? (y/n): " CONFIRMATION
LOWER_CONFIRMATION=$(to_lower "$CONFIRMATION")

if [[ "$LOWER_CONFIRMATION" == "y" || "$LOWER_CONFIRMATION" == "yes" ]]; then
    echo ""
    echo -e "🚀 ${C_BLUE}Stripping binaries... You will be prompted for your password.${C_RESET}"

    PROCESSED_COUNT=0
    for BINARY_PATH in "${UNIVERSAL_BINARIES[@]}"; do
        # Use sudo with the lipo command to request privileges only when needed.
        if sudo lipo -remove x86_64 -output "$BINARY_PATH" "$BINARY_PATH"; then
            if $RESIGN; then
                APP_NAME_FROM_PATH=$(basename "$(dirname "$(dirname "$BINARY_PATH")")" .app)
                sudo codesign --force --sign - "$BINARY_PATH" >/dev/null 2>&1 \
                    || echo -e "${C_YELLOW}Re-sign skipped for \"${APP_NAME_FROM_PATH}\".${C_RESET}"
            fi
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
