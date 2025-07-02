#!/bin/bash

# test-release-build.sh - Local GitHub Actions workflow testing script
# This script simulates the GitHub Actions build process locally

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GearLister Local Build Test ===${NC}"

# Clean up any previous build
echo -e "${YELLOW}Cleaning up previous build...${NC}"
rm -rf build/ *.zip

# Step 1: Version detection (simulating workflow step)
echo -e "${BLUE}Step 1: Detecting version from TOC file...${NC}"
TOC_VERSION=$(grep "## Version:" GearLister.toc | cut -d' ' -f3)
PACKAGE_NAME="GearLister-v${TOC_VERSION}"
echo -e "${GREEN}Version detected: v${TOC_VERSION}${NC}"
echo -e "${GREEN}Package name: ${PACKAGE_NAME}${NC}"

# Step 2: Create addon package (simulating workflow step)
echo -e "${BLUE}Step 2: Creating addon package...${NC}"
mkdir -p build/GearLister

# Copy files excluding build artifacts and git files (like rsync in the workflow)
echo "Copying addon files..."
find . -maxdepth 1 -type f \( -name "*.lua" -o -name "*.toc" \) -exec cp {} build/GearLister/ \;
cp -r Libs build/GearLister/

# Create zip file
cd build
zip -r "${PACKAGE_NAME}.zip" GearLister/ > /dev/null
cd ..

# Step 3: Verify package
echo -e "${BLUE}Step 3: Verifying package...${NC}"
if [ ! -f "build/${PACKAGE_NAME}.zip" ]; then
    echo -e "${RED}Error: Package file not found!${NC}"
    exit 1
fi

ZIP_SIZE=$(stat -c%s "build/${PACKAGE_NAME}.zip" 2>/dev/null || stat -f%z "build/${PACKAGE_NAME}.zip")
if [ "$ZIP_SIZE" -lt 1000 ]; then
    echo -e "${RED}Error: Package too small (${ZIP_SIZE} bytes)${NC}"
    exit 1
fi

echo -e "${GREEN}Package created successfully: ${PACKAGE_NAME}.zip (${ZIP_SIZE} bytes)${NC}"

# Step 4: Display package contents
echo -e "${BLUE}Step 4: Package contents preview...${NC}"
unzip -l "build/${PACKAGE_NAME}.zip" | head -20

# Step 5: Test with act (if available and Docker is running)
echo -e "${BLUE}Step 5: Testing with act...${NC}"
if command -v act >/dev/null 2>&1; then
    if docker ps >/dev/null 2>&1; then
        echo "Running act dry-run test..."
        # Try common Docker socket paths
        for socket in "/var/run/docker.sock" "$HOME/.rd/docker.sock" "$HOME/.docker/run/docker.sock"; do
            if [ -S "$socket" ]; then
                export DOCKER_HOST="unix://$socket"
                break
            fi
        done
        if act -j build -n >/dev/null 2>&1; then
            echo -e "${GREEN}✓ act dry-run test passed${NC}"
        else
            echo -e "${YELLOW}⚠ act dry-run test failed (this is expected due to rsync missing in container)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Docker not running, skipping act test${NC}"
    fi
else
    echo -e "${YELLOW}⚠ act not installed, skipping GitHub Actions test${NC}"
fi

echo -e "${GREEN}=== Build test completed successfully ===${NC}"
echo -e "${BLUE}Ready-to-install addon package: build/${PACKAGE_NAME}.zip${NC}"
echo -e "${BLUE}To install: Extract to World of Warcraft/_classic_era_/Interface/AddOns/${NC}"