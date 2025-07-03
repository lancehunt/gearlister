#!/bin/bash

# GearLister Release Script
# Triggers GitHub Actions workflow to create release and publish to CurseForge

echo "🚀 Triggering GearLister release workflow..."
echo "This will:"
echo "  ✅ Create GitHub release"
echo "  ✅ Publish to CurseForge"
echo ""

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed"
    echo "Install with: brew install gh"
    exit 1
fi

# Check if logged in to GitHub
if ! gh auth status &> /dev/null; then
    echo "❌ Not logged in to GitHub"
    echo "Run: gh auth login"
    exit 1
fi

# Trigger the workflow
if gh workflow run "Build and Release GearLister" --field create_release=true --field publish_curseforge=true; then
    echo "✅ Release workflow triggered successfully!"
    echo ""
    echo "📋 Check progress at:"
    echo "   https://github.com/lancehunt/gearlister/actions"
    echo ""
    echo "📦 Release will be available at:"
    echo "   https://github.com/lancehunt/gearlister/releases"
    echo ""
    echo "🎮 CurseForge page:"
    echo "   https://www.curseforge.com/wow/addons/gearlister"
else
    echo "❌ Failed to trigger workflow"
    exit 1
fi