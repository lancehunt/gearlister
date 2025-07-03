#!/bin/bash

# install-local.sh - Install addon to local WoW Classic directory
# This script copies the addon files to your local WoW installation for testing

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GearLister Local Installation ===${NC}"

# Default WoW Classic paths for different platforms
DEFAULT_PATHS=(
    "/Applications/World of Warcraft/_classic_era_/Interface/AddOns"
    "$HOME/Applications/World of Warcraft/_classic_era_/Interface/AddOns" 
    "/Program Files (x86)/World of Warcraft/_classic_era_/Interface/AddOns"
    "/Program Files/World of Warcraft/_classic_era_/Interface/AddOns"
    "$HOME/Games/World of Warcraft/_classic_era_/Interface/AddOns"
)

# Function to find WoW directory
find_wow_directory() {
    for path in "${DEFAULT_PATHS[@]}"; do
        if [ -d "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

# Try to auto-detect WoW directory
WOW_ADDON_DIR=""
if WOW_ADDON_DIR=$(find_wow_directory); then
    echo -e "${GREEN}Found WoW Classic AddOns directory: ${WOW_ADDON_DIR}${NC}"
else
    echo -e "${YELLOW}Could not auto-detect WoW Classic directory.${NC}"
    echo -e "${YELLOW}Please enter the full path to your WoW Classic AddOns directory:${NC}"
    echo -e "${YELLOW}Example: /Applications/World of Warcraft/_classic_era_/Interface/AddOns${NC}"
    read -r WOW_ADDON_DIR
    
    if [ ! -d "$WOW_ADDON_DIR" ]; then
        echo -e "${RED}Error: Directory '$WOW_ADDON_DIR' does not exist${NC}"
        exit 1
    fi
fi

# Define source and destination paths
ADDON_NAME="GearLister"
SOURCE_DIR="$(pwd)"
DEST_DIR="$WOW_ADDON_DIR/$ADDON_NAME"

echo -e "${BLUE}Installing addon...${NC}"
echo "Source: $SOURCE_DIR"
echo "Destination: $DEST_DIR"

# Remove existing installation
if [ -d "$DEST_DIR" ]; then
    echo -e "${YELLOW}Removing existing installation...${NC}"
    rm -rf "$DEST_DIR"
fi

# Create destination directory
mkdir -p "$DEST_DIR"

# Copy essential addon files (same as build process)
echo "Copying addon files..."
find . -maxdepth 1 -type f \( -name "*.lua" -o -name "*.toc" \) -exec cp {} "$DEST_DIR/" \;
cp -r Libs "$DEST_DIR/"

# Verify installation
if [ -f "$DEST_DIR/GearLister.toc" ] && [ -f "$DEST_DIR/GearLister.lua" ] && [ -d "$DEST_DIR/Libs" ]; then
    echo -e "${GREEN}✓ Installation successful!${NC}"
    echo -e "${BLUE}Addon installed to: $DEST_DIR${NC}"
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "${BLUE}1. Start/restart World of Warcraft Classic${NC}"
    echo -e "${BLUE}2. Enable GearLister in the AddOns menu${NC}"
    echo -e "${BLUE}3. Type '/gear' in game to test${NC}"
else
    echo -e "${RED}✗ Installation failed - missing files${NC}"
    exit 1
fi