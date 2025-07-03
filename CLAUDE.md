# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GearLister is a World of Warcraft Classic addon written in Lua that allows players to view, share, and compare equipped gear with Wowhead integration. The addon uses the Ace3 framework for modern UI components and data management.

## Architecture

### Core Structure
- **GearLister.lua**: Main addon file containing all functionality (~2000+ lines)
- **GearLister.toc**: WoW addon table of contents file defining dependencies and load order
- **Libs/**: Ace3 framework libraries (AceAddon, AceGUI, AceDB, AceConsole, AceEvent)

### Key Components
- **Ace3 Framework**: Professional addon development framework providing UI widgets, event handling, database management, and console commands
- **Equipment Slot System**: Maps WoW's 19 equipment slots to display names, with filtered display order excluding cosmetic items
- **Gear History System**: Persistent storage of gear snapshots with timestamps for comparison and tracking
- **Visual/Text Modes**: Dual display system showing gear as icons or copyable text with Wowhead links
- **Inspection System**: Automatic target inspection when in range, with gear caching
- **Comparison Mode**: Side-by-side gear comparison with visual highlighting of differences

### Data Flow
1. Gear collection via WoW API (`GetInventoryItemLink`, `GetInventoryItemTexture`)
2. Data storage in AceDB profile system with automatic cleanup
3. UI rendering through AceGUI widgets (Frame, ScrollFrame, EditBox, etc.)
4. Export system generating formatted text with Wowhead URLs

## Development Commands

This is a WoW addon project with no traditional build system. Development workflow:

### Testing
- Copy addon folder to `World of Warcraft/_classic_era_/Interface/AddOns/`
- Launch WoW Classic and test with `/gear` command
- Use `/reload` in-game to reload addon after changes

### Release Build Testing
- `scripts/test-release-build.sh` - Simulates GitHub Actions release build locally
- Tests version detection, package creation, and act workflow validation
- Creates ready-to-install addon zip file

### Code Validation
- Lua syntax can be checked with standard Lua interpreter
- WoW API compatibility must be tested in-game
- No automated test suite exists

## WoW Classic Context

- **Interface Version**: 11504 (WoW Classic Era)
- **API Limitations**: Classic WoW has restricted addon APIs compared to retail
- **Slash Commands**: `/gear` and `/gearlist` for main functionality
- **Saved Variables**: Uses `GearListerDB` for persistent data storage
- **Event System**: Hooks WoW events like `ADDON_LOADED`, `INSPECT_READY`

## Key Files to Understand

- `GearLister.lua:55-96`: Equipment slot mapping and display order
- `GearLister.lua:43-52`: Database schema and default settings
- `GearLister.toc:1-19`: Addon metadata and library dependencies

The addon is entirely self-contained with no external dependencies beyond the included Ace3 libraries.

## Git Commit Guidelines

- When performing git commits, follow the best practices of 80 char titles and use bullets for additional notes
- Omit any Claude attribution
- Whenever pushing git changes, only push the current branch not all branches

## Version Management
- Every time we make a change to the addon, bump the version following SemVer rules