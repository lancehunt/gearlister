-- GearLister Addon for WoW Classic
-- Shows equipped gear in a copyable dialog with integrated history panel
-- Uses Ace3 libraries for modern UI and data management

-- Protected library loading to prevent initialization failures
local function SafeLibStub(lib)
    local success, result = pcall(LibStub, lib)
    if success then
        return result
    else
        print("GearLister: Failed to load " .. lib .. " - " .. tostring(result))
        return nil
    end
end

local AceAddon = SafeLibStub("AceAddon-3.0")
local AceGUI = SafeLibStub("AceGUI-3.0")
local AceDB = SafeLibStub("AceDB-3.0")

-- Check if all required libraries loaded successfully
if not AceAddon or not AceGUI or not AceDB then
    print("GearLister: Required libraries failed to load. Please restart WoW or reinstall the addon.")
    return
end

-- Prevent duplicate addon creation
if AceAddon:GetAddon("GearLister", true) then
    return
end

-- Protected addon creation
local GearLister
local success, error = pcall(function()
    GearLister = AceAddon:NewAddon("GearLister", "AceConsole-3.0", "AceEvent-3.0")
end)

if not success then
    print("GearLister: Failed to create addon - " .. tostring(error))
    return
end

-- Default database structure
local defaults = {
    profile = {
        settings = {
            delimiter = " - ",
            addNewline = false,
            maxHistoryEntries = 50
        },
        gearHistory = {}
    }
}

-- Equipment slot IDs for Classic WoW mapped to slot names
local EQUIPMENT_SLOTS = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulders",
    [4] = "Shirt",
    [5] = "Chest",
    [6] = "Belt",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Gloves",
    [11] = "Ring1",
    [12] = "Ring2",
    [13] = "Trinket1",
    [14] = "Trinket2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
    [18] = "Ranged",
    [19] = "Tabard"
}

-- Ordered list for display (excluding Shirt and Tabard as they're not combat gear)
local DISPLAY_ORDER = {
    { slot = 1,  name = "Head" },
    { slot = 2,  name = "Neck" },
    { slot = 3,  name = "Shoulders" },
    { slot = 15, name = "Back" },
    { slot = 5,  name = "Chest" },
    { slot = 9,  name = "Wrist" },
    { slot = 10, name = "Gloves" },
    { slot = 6,  name = "Belt" },
    { slot = 7,  name = "Legs" },
    { slot = 8,  name = "Feet" },
    { slot = 11, name = "Ring1" },
    { slot = 12, name = "Ring2" },
    { slot = 13, name = "Trinket1" },
    { slot = 14, name = "Trinket2" },
    { slot = 16, name = "Main Hand" },
    { slot = 17, name = "Off Hand" },
    { slot = 18, name = "Ranged" }
}

-- Addon state variables
local mainFrame = nil
local settingsFrame = nil
local inspectMode = false
local inspectTarget = nil
local currentHistoryIndex = nil
local comparisonMode = false
local comparisonIndexA = nil
local comparisonIndexB = nil
local visualMode = true -- Changed default to true (Visual Mode is default)

function GearLister:OnInitialize()
    -- Protected initialization with error handling
    local success, error = pcall(function()
        -- Get version from TOC file
        local version = GetAddOnMetadata("GearLister", "Version") or "Unknown"
        self.version = version

        -- Initialize database
        self.db = AceDB:New("GearListerDB", defaults, true)

        -- Register slash commands
        self:RegisterChatCommand("gear", "SlashProcessor")
        self:RegisterChatCommand("gearlist", "SlashProcessor")

        -- Register events
        self:RegisterEvent("INSPECT_READY", "OnInspectReady")
    end)

    if not success then
        print("GearLister: Initialization failed - " .. tostring(error))
        return
    end

    self:Print("GearLister loaded! Use /gear or /gearlist to show equipped items with Wowhead links.")
    self:Print("Use /gear inspect to inspect your target's gear.")
    self:Print("/gear will automatically inspect your target if you have one, otherwise shows your gear.")
end

function GearLister:OnEnable()
    -- Addon enabled
end

function GearLister:OnDisable()
    -- Cleanup when disabled
    if mainFrame then
        mainFrame:Release()
        mainFrame = nil
    end
    if settingsFrame then
        settingsFrame:Release()
        settingsFrame = nil
    end
end

-- Utility Functions
function GearLister:GetItemIdFromLink(itemLink)
    if not itemLink then return nil end
    local itemId = string.match(itemLink, "item:(%d+)")
    return itemId
end

function GearLister:GetActualDelimiter()
    local settings = self.db.profile.settings
    local delimiter = settings.delimiter
    if settings.addNewline then
        delimiter = delimiter .. "\n"
    end
    return delimiter
end

function GearLister:GetEquippedItems(unit)
    local items = {}
    local targetUnit = unit or "player"
    local actualDelimiter = self:GetActualDelimiter()

    for _, slotInfo in ipairs(DISPLAY_ORDER) do
        local slotId = slotInfo.slot
        local slotName = slotInfo.name
        local itemLink = GetInventoryItemLink(targetUnit, slotId)

        if itemLink then
            local itemName = GetItemInfo(itemLink)
            local itemId = self:GetItemIdFromLink(itemLink)
            if itemName and itemId then
                local wowheadLink = "https://classic.wowhead.com/item=" .. itemId
                -- Store both the formatted text and the item link for visual mode
                local itemEntry = slotName .. ": " .. itemLink .. actualDelimiter .. wowheadLink
                table.insert(items, itemEntry)
            end
        else
            -- Always include slot even if empty
            local itemEntry = slotName .. ": (empty)"
            table.insert(items, itemEntry)
        end
    end

    return items
end

function GearLister:CreateGearHash(items)
    return table.concat(items, "|")
end

function GearLister:SaveToHistory(characterName, items)
    local gearHash = self:CreateGearHash(items)
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    local gearHistory = self.db.profile.gearHistory

    -- Check if this exact gear set already exists
    for i, entry in ipairs(gearHistory) do
        if entry.hash == gearHash and entry.characterName == characterName then
            -- Update timestamp and move to front
            entry.timestamp = timestamp
            entry.displayTime = date("%m/%d %H:%M")
            table.remove(gearHistory, i)
            table.insert(gearHistory, 1, entry)
            self:RefreshHistoryList()
            self:Print("|cffff9900Updating gear for " .. characterName .. " |r")
            return
        end
    end

    -- Add new entry to the front
    local newEntry = {
        characterName = characterName,
        items = items,
        hash = gearHash,
        timestamp = timestamp,
        displayTime = date("%m/%d %H:%M")
    }
    table.insert(gearHistory, 1, newEntry)

    -- Keep only the most recent entries
    local maxEntries = self.db.profile.settings.maxHistoryEntries
    while #gearHistory > maxEntries do
        table.remove(gearHistory)
    end

    -- Force immediate history list refresh
    self:RefreshHistoryList()
end

function GearLister:GetCurrentTargetName()
    if inspectMode and UnitExists("target") and UnitIsPlayer("target") then
        return UnitName("target")
    end
    return nil
end

function GearLister:StartInspect()
    if not UnitExists("target") then
        self:Print("|cffff0000No target selected. Please target a player first.|r")
        return false
    end

    if not UnitIsPlayer("target") then
        self:Print("|cffff0000Target must be a player.|r")
        return false
    end

    if not CheckInteractDistance("target", 1) then
        self:Print("|cffff0000Target is too far away to inspect.|r")
        return false
    end

    -- Clear any previous inspect data
    ClearInspectPlayer()

    -- Set inspect mode and capture current target name
    inspectMode = true
    inspectTarget = UnitName("target")

    -- Start the inspect
    InspectUnit("target")

    self:Print("|cff00ff00Inspecting " .. inspectTarget .. "...|r")

    return true
end

function GearLister:OnInspectReady()
    if inspectMode then
        -- Verify we still have the same target
        local currentTarget = self:GetCurrentTargetName()
        if currentTarget and currentTarget == inspectTarget then
            -- Small delay to ensure all data is loaded
            C_Timer.After(0.5, function()
                self:ShowMainWindow()
            end)
        else
            -- Target changed or lost, cancel inspect mode
            self:Print("|cffff0000Target changed during inspect. Please try again.|r")
            inspectMode = false
            inspectTarget = nil
            ClearInspectPlayer()
        end
    end
end

function GearLister:DetermineTargetMode()
    if UnitExists("target") and UnitIsPlayer("target") then
        if CheckInteractDistance("target", 1) then
            return self:StartInspect()
        else
            self:Print("|cffff0000Target is too far to inspect. Showing your gear instead.|r")
            inspectMode = false
            inspectTarget = nil
            return true
        end
    else
        -- No target, default to player
        inspectMode = false
        inspectTarget = nil
        return true
    end
end

-- UI Creation Functions
function GearLister:ShowMainWindow()
    if mainFrame then
        mainFrame:Show()
        self:RefreshMainWindow()
        return
    end

    -- Protected UI creation with error handling
    local success, error = pcall(function()
        -- Create main window - reduced height by 20% (650 -> 520) and prevent resizing
        mainFrame = AceGUI:Create("Frame")
        mainFrame:SetTitle("GearList")
        mainFrame:SetWidth(900)
        mainFrame:SetHeight(520)
        mainFrame:SetLayout("Fill")
        mainFrame.frame:SetResizable(false) -- Prevent resizing

        -- Enable Escape key functionality
        mainFrame.frame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                mainFrame:Hide()
                -- Stop propagation to prevent WoW main menu from opening
                return
            end
            -- Allow other keys to propagate normally
            self:SetPropagateKeyboardInput(true)
        end)
        mainFrame.frame:SetPropagateKeyboardInput(false) -- Default to false, enable per-key
        mainFrame.frame:EnableKeyboard(true)

        -- Enhanced close callback with proper cleanup
        mainFrame:SetCallback("OnClose", function(widget)
            inspectMode = false
            inspectTarget = nil
            currentHistoryIndex = nil
            ClearInspectPlayer()
            widget:Hide()
        end)

        -- Create main container with manual positioning
        local container = AceGUI:Create("SimpleGroup")
        container:SetFullWidth(true)
        container:SetFullHeight(true)
        container:SetLayout(nil) -- No automatic layout
        mainFrame:AddChild(container)

        -- History panel with frame (taller to reach close button)
        local historyPanel = AceGUI:Create("InlineGroup")
        historyPanel:SetTitle("Gear History")
        historyPanel:SetWidth(220)
        historyPanel:SetHeight(440)
        historyPanel:SetLayout(nil) -- Manual layout
        historyPanel.frame:SetPoint("TOPLEFT", container.frame, "TOPLEFT", 5, -5)
        container:AddChild(historyPanel)

        -- History list inside the panel (taller)
        local historyList = AceGUI:Create("ScrollFrame")
        historyList:SetWidth(200)
        historyList:SetHeight(365)
        historyList:SetLayout("List")
        historyList.frame:SetPoint("TOPLEFT", historyPanel.frame, "TOPLEFT", 10, -25)
        historyPanel:AddChild(historyList)

        -- Store reference to history list
        mainFrame.historyList = historyList

        -- Current gear button - changed label to "Refresh"
        local currentButton = AceGUI:Create("Button")
        currentButton:SetText("Refresh")
        currentButton:SetFullWidth(true)
        currentButton:SetCallback("OnClick", function()
            self:SelectCurrentGear()
        end)
        historyList:AddChild(currentButton)

        -- Clear History button (positioned inside history panel)
        local clearHistoryButton = AceGUI:Create("Button")
        clearHistoryButton:SetText("Clear History")
        clearHistoryButton:SetWidth(200)
        clearHistoryButton:SetCallback("OnClick", function()
            self:ClearHistory()
        end)
        clearHistoryButton.frame:SetPoint("TOPLEFT", historyList.frame, "BOTTOMLEFT", 0, -10)
        historyPanel:AddChild(clearHistoryButton)

        -- Store reference for later updates
        mainFrame.clearHistoryButton = clearHistoryButton

        -- Gear display panel with frame (much narrower and taller)
        local gearPanel = AceGUI:Create("InlineGroup")
        gearPanel:SetTitle("Equipped Gear")
        gearPanel:SetWidth(615)
        gearPanel:SetHeight(440)
        gearPanel:SetLayout(nil) -- Manual layout
        gearPanel.frame:SetPoint("TOPLEFT", container.frame, "TOPLEFT", 235, -5)
        container:AddChild(gearPanel)

        -- Comparison mode toggle (positioned inside gear panel, moved up)
        local comparisonToggle = AceGUI:Create("CheckBox")
        comparisonToggle:SetLabel("Comparison Mode")
        comparisonToggle:SetValue(comparisonMode)
        comparisonToggle:SetWidth(150)
        comparisonToggle:SetCallback("OnValueChanged", function(widget, event, value)
            self:ToggleComparisonMode(value)
        end)
        comparisonToggle.frame:SetPoint("TOPRIGHT", gearPanel.frame, "TOPRIGHT", -20, 5)
        gearPanel:AddChild(comparisonToggle)
        mainFrame.comparisonToggle = comparisonToggle

        -- Text mode toggle (positioned inside gear panel, moved up)
        local textToggle = AceGUI:Create("CheckBox")
        textToggle:SetLabel("Text Mode")
        textToggle:SetValue(not visualMode) -- Inverted: checked when visual mode is false
        textToggle:SetWidth(120)
        textToggle:SetCallback("OnValueChanged", function(widget, event, value)
            self:ToggleVisualMode(not value) -- Invert the value since this is "Text Mode"
        end)
        textToggle.frame:SetPoint("TOPRIGHT", gearPanel.frame, "TOPRIGHT", -180, 5)
        gearPanel:AddChild(textToggle)
        mainFrame.textToggle = textToggle

        -- Gear display inside the gear panel (much narrower and taller)
        local gearEditBox = AceGUI:Create("MultiLineEditBox")
        gearEditBox:SetWidth(585)
        gearEditBox:SetHeight(360)
        gearEditBox:DisableButton(true)
        gearEditBox.frame:SetPoint("TOPLEFT", gearPanel.frame, "TOPLEFT", 10, -35)
        gearEditBox.frame:SetPoint("BOTTOMRIGHT", gearPanel.frame, "BOTTOMRIGHT", -10, 50)
        gearPanel:AddChild(gearEditBox)

        -- Store reference to gear display and gear panel
        mainFrame.gearEditBox = gearEditBox
        mainFrame.gearPanel = gearPanel

        -- Control buttons inside gear panel
        local refreshButton = AceGUI:Create("Button")
        refreshButton:SetText("Inspect")
        refreshButton:SetWidth(80)
        refreshButton:SetCallback("OnClick", function()
            self:RefreshCurrentGear()
        end)
        refreshButton.frame:SetPoint("BOTTOMLEFT", gearPanel.frame, "BOTTOMLEFT", 10, 10)
        gearPanel:AddChild(refreshButton)
        mainFrame.inspectButton = refreshButton

        local settingsButton = AceGUI:Create("Button")
        settingsButton:SetText("Settings")
        settingsButton:SetWidth(100)
        settingsButton:SetCallback("OnClick", function()
            self:ShowSettingsWindow()
        end)
        settingsButton.frame:SetPoint("BOTTOMRIGHT", container.frame, "BOTTOMRIGHT", -30, 15)
        gearPanel:AddChild(settingsButton)

        -- Credit text with version - right aligned inside gear panel
        local creditText = AceGUI:Create("Label")
        local version = self.version or "Unknown"
        creditText:SetText("|cff808080Made with <3 by Bunnycrits (v" .. version .. ")|r")
        creditText:SetWidth(300)
        creditText.frame:SetPoint("BOTTOMRIGHT", gearPanel.frame, "BOTTOMRIGHT", -10, 10)
        gearPanel:AddChild(creditText)

        -- Initialize display
        self:RefreshMainWindow()
    end)

    if not success then
        print("GearLister: UI creation failed - " .. tostring(error))
        return
    end
end

function GearLister:RefreshMainWindow()
    if not mainFrame then return end

    self:RefreshHistoryList()
    self:RefreshGearDisplay()
end

function GearLister:RefreshHistoryList()
    if not mainFrame or not mainFrame.historyList then return end

    -- Clear existing history entries but keep the current gear button
    local children = {}
    for i, child in ipairs(mainFrame.historyList.children) do
        if i == 1 then
            -- Keep the Refresh button
            children[1] = child
        else
            child:Release()
        end
    end
    mainFrame.historyList.children = children

    -- Update current gear button highlighting
    if children[1] then
        if not currentHistoryIndex and not comparisonMode then
            children[1]:SetText("|cff00ff00Refresh|r")
        else
            children[1]:SetText("Refresh")
        end
    end

    -- Add history entries as clickable text rows
    local gearHistory = self.db.profile.gearHistory
    for i, entry in ipairs(gearHistory) do
        local entryContainer = AceGUI:Create("SimpleGroup")
        entryContainer:SetFullWidth(true)
        entryContainer:SetLayout(nil) -- Manual positioning
        entryContainer:SetHeight(35)

        -- Create clickable text label
        local entryLabel = AceGUI:Create("InteractiveLabel")
        local labelText = entry.characterName .. "\n" .. entry.displayTime

        -- Color coding for different modes
        if comparisonMode then
            if comparisonIndexA == i then
                labelText = "|cff00ff00[A] " .. labelText .. "|r"
            elseif comparisonIndexB == i then
                labelText = "|cff0099ff[B] " .. labelText .. "|r"
            else
                labelText = "|cffffffff" .. labelText .. "|r"
            end
        else
            if currentHistoryIndex == i then
                labelText = "|cff00ff00" .. labelText .. "|r"
            else
                labelText = "|cffffffff" .. labelText .. "|r"
            end
        end

        entryLabel:SetText(labelText)
        entryLabel:SetWidth(160)
        entryLabel:SetCallback("OnClick", function()
            if comparisonMode then
                self:SelectComparisonEntry(i)
            else
                self:SelectHistoryEntry(i)
            end
        end)
        entryLabel.frame:SetPoint("LEFT", entryContainer.frame, "LEFT", 5, 0)
        entryContainer:AddChild(entryLabel)

        -- Delete button (X)
        local deleteButton = AceGUI:Create("Button")
        deleteButton:SetText("×") -- Unicode multiplication sign (looks like X)
        deleteButton:SetWidth(20)
        deleteButton:SetHeight(20)
        deleteButton:SetCallback("OnClick", function()
            self:DeleteHistoryEntry(i)
        end)
        deleteButton.frame:SetPoint("RIGHT", entryContainer.frame, "RIGHT", -5, 0)
        entryContainer:AddChild(deleteButton)

        mainFrame.historyList:AddChild(entryContainer)
    end

    if #gearHistory == 0 then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText("|cff808080No history available|r")
        emptyLabel:SetFullWidth(true)
        mainFrame.historyList:AddChild(emptyLabel)
    end

    -- Add comparison instructions if in comparison mode
    if comparisonMode then
        local instructionLabel = AceGUI:Create("Label")
        instructionLabel:SetText(
            "|cffff9900Click entries to select:\n[A] First character (green)\n[B] Second character (blue)|r")
        instructionLabel:SetFullWidth(true)
        mainFrame.historyList:AddChild(instructionLabel)
    end
end

function GearLister:RefreshGearDisplay()
    if not mainFrame then return end

    -- Clear any existing visual displays
    if mainFrame.visualDisplayA then
        mainFrame.visualDisplayA:Hide()
        mainFrame.visualDisplayA = nil
    end
    if mainFrame.visualDisplayB then
        mainFrame.visualDisplayB:Hide()
        mainFrame.visualDisplayB = nil
    end
    if mainFrame.visualDisplaySingle then
        mainFrame.visualDisplaySingle:Hide()
        mainFrame.visualDisplaySingle = nil
    end

    local gearText = ""
    local titleSuffix = ""

    if visualMode then
        -- Visual mode - hide text box and show gear icons
        if mainFrame.gearEditBox then
            mainFrame.gearEditBox.frame:Hide()
        end

        if comparisonMode and comparisonIndexA and comparisonIndexB then
            -- Visual comparison mode
            local gearHistory = self.db.profile.gearHistory
            local entryA = gearHistory[comparisonIndexA]
            local entryB = gearHistory[comparisonIndexB]

            if entryA and entryB then
                -- Create side-by-side visual displays using the stored gear panel frame
                local gearPanelFrame = mainFrame.gearPanel and mainFrame.gearPanel.frame

                if gearPanelFrame then
                    -- Pass comparison data to highlight differences
                    mainFrame.visualDisplayA = self:CreateVisualGearDisplay(gearPanelFrame, entryA.items, 50, -45,
                        entryB.items)
                    mainFrame.visualDisplayB = self:CreateVisualGearDisplay(gearPanelFrame, entryB.items, 300, -45,
                        entryA.items)

                    -- Add character labels
                    local labelA = mainFrame.visualDisplayA:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                    labelA:SetPoint("TOP", mainFrame.visualDisplayA, "TOP", 0, 20)
                    labelA:SetText("|cff00ff00" .. entryA.characterName .. "|r")

                    local labelB = mainFrame.visualDisplayB:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                    labelB:SetPoint("TOP", mainFrame.visualDisplayB, "TOP", 0, 20)
                    labelB:SetText("|cff0099ff" .. entryB.characterName .. "|r")

                    -- Add legend at the bottom
                    local legend = containerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    legend:SetPoint("BOTTOM", containerFrame, "BOTTOM", 0, 65) -- Positioned above buttons with more clearance
                    legend:SetText("|cff808080Grey: Same Items|r")

                    titleSuffix = " - Visual Comparison: " .. entryA.characterName .. " vs " .. entryB.characterName
                else
                    -- Fallback to text mode if container not found
                    if mainFrame.gearEditBox then
                        mainFrame.gearEditBox.frame:Show()
                        mainFrame.gearEditBox:SetText("Visual comparison mode error - using text fallback:\n\n" ..
                            self:CompareGearSets(entryA, entryB))
                    end
                end
            end
        else
            -- Single character visual mode
            local items = {}
            local characterName = ""

            if currentHistoryIndex then
                local gearHistory = self.db.profile.gearHistory
                if gearHistory[currentHistoryIndex] then
                    local entry = gearHistory[currentHistoryIndex]
                    items = entry.items
                    characterName = entry.characterName
                    titleSuffix = " - Visual: " .. entry.characterName
                end
            else
                -- Current gear
                local targetUnit = "player"
                characterName = UnitName("player")

                if inspectMode then
                    local currentTarget = self:GetCurrentTargetName()
                    if currentTarget then
                        targetUnit = "target"
                        characterName = currentTarget
                        titleSuffix = " - Visual: " .. characterName
                    else
                        self:Print("|cffff0000Target lost, showing your gear instead.|r")
                        inspectMode = false
                        inspectTarget = nil
                        ClearInspectPlayer()
                        titleSuffix = " - Visual: " .. characterName
                    end
                else
                    titleSuffix = " - Visual: " .. characterName
                end

                items = self:GetEquippedItems(targetUnit)

                -- Auto-save current gear to history (but not in comparison mode)
                if characterName and not comparisonMode then
                    self:SaveToHistory(characterName, items)
                end
            end

            if #items > 0 then
                -- Use the stored gear panel frame
                local gearPanelFrame = mainFrame.gearPanel and mainFrame.gearPanel.frame

                if gearPanelFrame then
                    mainFrame.visualDisplaySingle = self:CreateVisualGearDisplay(gearPanelFrame, items, 150, -45)

                    -- Add character label
                    local label = mainFrame.visualDisplaySingle:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                    label:SetPoint("TOP", mainFrame.visualDisplaySingle, "TOP", 0, 20)
                    label:SetText("|cffffffff" .. characterName .. "|r")
                else
                    -- Fallback to text mode
                    if mainFrame.gearEditBox then
                        mainFrame.gearEditBox.frame:Show()
                        mainFrame.gearEditBox:SetText(table.concat(items, "\n"))
                    end
                end
            end
        end
    else
        -- Text mode - show text box and hide visual displays
        if mainFrame.gearEditBox then
            mainFrame.gearEditBox.frame:Show()
        end

        if comparisonMode then
            -- Text comparison mode
            if comparisonIndexA and comparisonIndexB then
                local gearHistory = self.db.profile.gearHistory
                local entryA = gearHistory[comparisonIndexA]
                local entryB = gearHistory[comparisonIndexB]

                if entryA and entryB then
                    gearText = self:CompareGearSets(entryA, entryB)
                    titleSuffix = " - Comparison Mode"
                else
                    gearText = "Error: Invalid comparison entries selected."
                end
            else
                gearText = "Comparison Mode: Select two characters from history to compare their gear.\n\n"
                if comparisonIndexA then
                    local gearHistory = self.db.profile.gearHistory
                    if gearHistory[comparisonIndexA] then
                        gearText = gearText ..
                            "First character selected: " .. gearHistory[comparisonIndexA].characterName .. "\n"
                        gearText = gearText .. "Now select a second character to compare."
                    end
                else
                    gearText = gearText ..
                        "Click on a character in the history list to select them as the first character for comparison."
                end
            end
            titleSuffix = " - Comparison Mode"
        elseif currentHistoryIndex then
            -- Show history entry
            local gearHistory = self.db.profile.gearHistory
            if gearHistory[currentHistoryIndex] then
                local entry = gearHistory[currentHistoryIndex]
                gearText = table.concat(entry.items, "\n")
                titleSuffix = " - " .. entry.characterName .. " (" .. entry.displayTime .. ")"
            end
        else
            -- Show current gear
            local targetUnit = "player"
            local characterName = UnitName("player")

            if inspectMode then
                local currentTarget = self:GetCurrentTargetName()
                if currentTarget then
                    targetUnit = "target"
                    characterName = currentTarget
                    titleSuffix = " - " .. characterName
                else
                    self:Print("|cffff0000Target lost, showing your gear instead.|r")
                    inspectMode = false
                    inspectTarget = nil
                    ClearInspectPlayer()
                end
            end

            local items = self:GetEquippedItems(targetUnit)
            gearText = table.concat(items, "\n")

            -- Auto-save current gear to history (always save when not in comparison mode)
            if characterName then
                self:SaveToHistory(characterName, items)
            end
        end

        if mainFrame.gearEditBox then
            mainFrame.gearEditBox:SetText(gearText)
        end
    end

    mainFrame:SetTitle("GearList" .. titleSuffix)
end

function GearLister:SelectCurrentGear()
    currentHistoryIndex = nil
    self:RefreshMainWindow()
end

-- Visual gear display layout (like character pane)
local GEAR_SLOT_POSITIONS = {
    -- Left column (top to bottom)
    [1] = { x = 10, y = -30 },   -- Head
    [2] = { x = 10, y = -80 },   -- Neck
    [3] = { x = 10, y = -130 },  -- Shoulders
    [15] = { x = 10, y = -180 }, -- Back
    [5] = { x = 10, y = -230 },  -- Chest
    [9] = { x = 10, y = -280 },  -- Wrist

    -- Right column (top to bottom)
    [10] = { x = 130, y = -30 }, -- Gloves (Hands)
    [6] = { x = 130, y = -80 },  -- Belt (Waist)
    [7] = { x = 130, y = -130 }, -- Legs
    [8] = { x = 130, y = -180 }, -- Feet

    -- Right-aligned rings/trinkets (2x2 grid)
    [11] = { x = 90, y = -230 },  -- Ring1
    [12] = { x = 130, y = -230 }, -- Ring2
    [13] = { x = 90, y = -280 },  -- Trinket1
    [14] = { x = 130, y = -280 }, -- Trinket2

    -- Bottom row weapons (left to right)
    [16] = { x = 10, y = -330 }, -- Main Hand
    [17] = { x = 70, y = -330 }, -- Off Hand
    [18] = { x = 130, y = -330 } -- Ranged
}

function GearLister:CreateVisualGearDisplay(parent, items, offsetX, offsetY, comparisonItems)
    local visualFrame = CreateFrame("Frame", nil, parent)
    visualFrame:SetSize(160, 380) -- Size for compact character pane layout
    visualFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", offsetX or 0, offsetY or -25)

    -- Create item map for easy lookup
    local itemMap = {}
    for _, item in ipairs(items) do
        local slot = string.match(item, "^([^:]+):")
        if slot then
            itemMap[slot] = item
        end
    end

    -- Create comparison item map if provided
    local comparisonMap = {}
    if comparisonItems then
        for _, item in ipairs(comparisonItems) do
            local slot = string.match(item, "^([^:]+):")
            if slot then
                comparisonMap[slot] = item
            end
        end
    end

    -- Create gear slot buttons in the exact order from DISPLAY_ORDER
    local gearButtons = {}
    for i, slotInfo in ipairs(DISPLAY_ORDER) do
        local slotId = slotInfo.slot
        local slotName = slotInfo.name

        -- Use authentic character pane positions from GEAR_SLOT_POSITIONS
        local position = GEAR_SLOT_POSITIONS[slotId]
        local x = position and position.x or 10  -- Default to left if position not found
        local y = position and position.y or -50 -- Default to top if position not found

        local button = CreateFrame("Button", nil, visualFrame)
        button:SetSize(38, 38) -- Increased from 32 to 38px (20% increase)
        button:SetPoint("TOPLEFT", visualFrame, "TOPLEFT", x, y)

        -- Create border
        button.border = button:CreateTexture(nil, "BACKGROUND")
        button.border:SetAllPoints()
        button.border:SetTexture("Interface\\Buttons\\UI-EmptySlot")

        -- Create icon texture
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

        -- Create difference indicator overlay
        button.diffIndicator = button:CreateTexture(nil, "OVERLAY")
        button.diffIndicator:SetAllPoints()
        button.diffIndicator:Hide() -- Hidden by default

        -- Get item for this slot
        local itemData = itemMap[slotName]
        local comparisonData = comparisonMap[slotName]
        local isMatching = false
        local isDifferent = false
        local isMissing = false

        -- Determine comparison status
        if comparisonItems then
            if itemData and comparisonData then
                -- Both have items - compare them
                local itemLinkA = string.match(itemData, "(|c%x+|Hitem:[^|]+|h[^|]+|h|r)")
                local itemLinkB = string.match(comparisonData, "(|c%x+|Hitem:[^|]+|h[^|]+|h|r)")

                if itemLinkA and itemLinkB then
                    local nameA = string.match(itemLinkA, "|h([^|]+)|h")
                    local nameB = string.match(itemLinkB, "|h([^|]+)|h")
                    isMatching = (nameA == nameB)
                    isDifferent = not isMatching
                end
            elseif itemData and not comparisonData then
                -- This character has item, other doesn't
                isMissing = true
            elseif not itemData and comparisonData then
                -- Other character has item, this one doesn't
                isMissing = true
            elseif not itemData and not comparisonData then
                -- Both empty - considered matching
                isMatching = true
            end
        end

        if itemData then
            -- Extract item link from the saved data - look for item link pattern
            local itemLink = string.match(itemData, "(|c%x+|Hitem:[^|]+|h[^|]+|h|r)")
            if itemLink then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemLink)
                if texture then
                    button.icon:SetTexture(texture)
                    button.border:SetTexture("Interface\\Buttons\\UI-Slot-Background")

                    -- Apply comparison visual effects
                    if isMatching then
                        -- Grey out matching items
                        button.icon:SetDesaturated(true)
                        button.icon:SetVertexColor(0.5, 0.5, 0.5, 0.8)
                    else
                        -- Keep different items normal (no special highlighting)
                        button.icon:SetDesaturated(false)
                        button.icon:SetVertexColor(1, 1, 1, 1)
                    end

                    -- Set up tooltip
                    button.itemLink = itemLink
                    button:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(self.itemLink)
                        GameTooltip:Show()
                    end)
                    button:SetScript("OnLeave", function(self)
                        GameTooltip:Hide()
                    end)
                else
                    -- Item not cached yet, show placeholder and try to load
                    button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    -- Try to load the item info
                    local itemString = string.match(itemLink, "item:([^|]+)")
                    if itemString then
                        local itemID = string.match(itemString, "^(%d+)")
                        if itemID then
                            -- Force item loading
                            GetItemInfo(tonumber(itemID))
                        end
                    end
                end
            else
                -- No item link found, show empty slot
                button.icon:SetTexture(nil)
            end
        else
            -- Empty slot - show empty box
            button.icon:SetTexture(nil)
            button.border:SetTexture("Interface\\Buttons\\UI-EmptySlot")

            -- No special effects for empty slots in comparison mode
        end

        -- Add slot label positioned above the icon
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("BOTTOM", button, "TOP", 0, 2)
        button.label:SetText(slotName)
        button.label:SetTextColor(0.8, 0.8, 0.8)

        gearButtons[slotId] = button
    end

    return visualFrame, gearButtons
end

function GearLister:ToggleVisualMode(enabled)
    visualMode = enabled

    -- Update the text mode checkbox to reflect the opposite of visual mode
    if mainFrame and mainFrame.textToggle then
        mainFrame.textToggle:SetValue(not enabled)
    end

    if enabled then
        self:Print("|cff00ff00Visual Mode enabled - showing gear as icons.|r")
    else
        self:Print("|cff00ff00Text Mode enabled - showing text list.|r")
    end

    self:RefreshGearDisplay()
end

function GearLister:SelectHistoryEntry(index)
    currentHistoryIndex = index
    self:RefreshMainWindow()
end

function GearLister:ToggleComparisonMode(enabled)
    comparisonMode = enabled

    if enabled then
        -- Entering comparison mode
        currentHistoryIndex = nil
        comparisonIndexA = nil
        comparisonIndexB = nil
        self:Print("|cff00ff00Comparison Mode enabled. Click two history entries to compare.|r")

        -- Hide inspect button in comparison mode
        if mainFrame and mainFrame.inspectButton then
            mainFrame.inspectButton.frame:Hide()
        end
    else
        -- Exiting comparison mode
        comparisonIndexA = nil
        comparisonIndexB = nil
        self:Print("|cff00ff00Comparison Mode disabled.|r")

        -- Show inspect button again
        if mainFrame and mainFrame.inspectButton then
            mainFrame.inspectButton.frame:Show()
        end
    end

    self:RefreshMainWindow()
end

function GearLister:SelectComparisonEntry(index)
    if not comparisonIndexA then
        comparisonIndexA = index
        self:Print("|cff00ff00Selected first character for comparison.|r")
    elseif not comparisonIndexB and comparisonIndexA ~= index then
        comparisonIndexB = index
        self:Print("|cff0099ffSelected second character for comparison.|r")
    else
        -- Reset selection
        comparisonIndexA = index
        comparisonIndexB = nil
        self:Print("|cff00ff00Reset comparison - selected new first character.|r")
    end

    self:RefreshMainWindow()
end

function GearLister:CompareGearSets(entryA, entryB)
    local comparisonText = "|cffffff00=== GEAR COMPARISON ===|r\n"
    comparisonText = comparisonText ..
        "|cff00ff00" .. entryA.characterName .. "|r vs |cff0099ff" .. entryB.characterName .. "|r\n\n"

    -- Create item maps for easier comparison
    local itemsA = {}
    local itemsB = {}

    for _, item in ipairs(entryA.items) do
        local slot = string.match(item, "^([^:]+):")
        if slot then
            itemsA[slot] = item
        end
    end

    for _, item in ipairs(entryB.items) do
        local slot = string.match(item, "^([^:]+):")
        if slot then
            itemsB[slot] = item
        end
    end

    -- Compare each slot
    for _, slotInfo in ipairs(DISPLAY_ORDER) do
        local slotName = slotInfo.name
        local itemA = itemsA[slotName]
        local itemB = itemsB[slotName]

        if itemA and itemB then
            -- Both have items - extract item names for comparison
            -- Handle both old format (item name) and new format (item link)
            local nameA, nameB

            -- Try to extract from item link first, then fall back to plain text
            local linkA = string.match(itemA, "(|c%x+|Hitem:[^|]+|h([^|]+)|h|r)")
            if linkA then
                nameA = string.match(linkA, "|h([^|]+)|h")
            else
                nameA = string.match(itemA,
                    slotName ..
                    ": ([^" .. string.gsub(self:GetActualDelimiter(), "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "]+)")
            end

            local linkB = string.match(itemB, "(|c%x+|Hitem:[^|]+|h([^|]+)|h|r)")
            if linkB then
                nameB = string.match(linkB, "|h([^|]+)|h")
            else
                nameB = string.match(itemB,
                    slotName ..
                    ": ([^" .. string.gsub(self:GetActualDelimiter(), "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "]+)")
            end

            if nameA and nameB then
                if nameA == nameB then
                    -- Same item
                    comparisonText = comparisonText .. "|cff808080" .. slotName .. ": " .. nameA .. " (Same)|r\n"
                else
                    -- Different items
                    comparisonText = comparisonText .. "|cffffff00" .. slotName .. ":|r\n"
                    comparisonText = comparisonText .. "  |cff00ff00A: " .. nameA .. "|r\n"
                    comparisonText = comparisonText .. "  |cff0099ffB: " .. nameB .. "|r\n"
                end
            end
        elseif itemA and not itemB then
            -- A has item, B doesn't
            local nameA
            local linkA = string.match(itemA, "(|c%x+|Hitem:[^|]+|h([^|]+)|h|r)")
            if linkA then
                nameA = string.match(linkA, "|h([^|]+)|h")
            else
                nameA = string.match(itemA,
                    slotName ..
                    ": ([^" .. string.gsub(self:GetActualDelimiter(), "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "]+)")
            end

            if nameA then
                comparisonText = comparisonText .. "|cffff0000" .. slotName .. ": " .. nameA .. " (B missing)|r\n"
            end
        elseif not itemA and itemB then
            -- B has item, A doesn't
            local nameB
            local linkB = string.match(itemB, "(|c%x+|Hitem:[^|]+|h([^|]+)|h|r)")
            if linkB then
                nameB = string.match(linkB, "|h([^|]+)|h")
            else
                nameB = string.match(itemB,
                    slotName ..
                    ": ([^" .. string.gsub(self:GetActualDelimiter(), "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "]+)")
            end

            if nameB then
                comparisonText = comparisonText .. "|cffff9900" .. slotName .. ": " .. nameB .. " (A missing)|r\n"
            end
        end
        -- If neither has item, skip the slot
    end

    return comparisonText
end

function GearLister:DeleteHistoryEntry(index)
    table.remove(self.db.profile.gearHistory, index)

    -- Reset selection if we deleted the selected entry
    if currentHistoryIndex == index then
        currentHistoryIndex = nil
    elseif currentHistoryIndex and currentHistoryIndex > index then
        currentHistoryIndex = currentHistoryIndex - 1
    end

    self:RefreshMainWindow()
    self:Print("|cff00ff00History entry deleted.|r")
end

function GearLister:RefreshCurrentGear()
    if currentHistoryIndex then
        -- Just refresh the display if viewing history
        self:RefreshGearDisplay()
    else
        -- Reset state and re-determine target mode (like a fresh /gear call)
        local oldInspectMode = inspectMode
        local oldInspectTarget = inspectTarget

        inspectMode = false
        inspectTarget = nil
        currentHistoryIndex = nil
        ClearInspectPlayer()

        -- Re-determine target mode and fetch fresh gear
        if self:DetermineTargetMode() then
            if not inspectMode then
                -- No inspect mode, get current gear immediately and save
                local characterName = UnitName("player")
                local items = self:GetEquippedItems("player")
                self:SaveToHistory(characterName, items)
                -- Force complete UI refresh
                self:RefreshMainWindow()
                self:Print("|cff00ff00Inspected and saved gear for " .. characterName .. "|r")
            else
                -- Inspect mode started, will update and save when ready
                self:Print("|cff00ff00Inspecting target gear...|r")
            end
        end
    end
end

function GearLister:ClearHistory()
    self.db.profile.gearHistory = {}
    currentHistoryIndex = nil
    self:RefreshMainWindow()
    self:Print("|cff00ff00History cleared.|r")
end

-- Settings Window
function GearLister:ShowSettingsWindow()
    if settingsFrame then
        settingsFrame:Show()
        settingsFrame.frame:Raise()
        settingsFrame.frame:SetFrameStrata("FULLSCREEN_DIALOG")
        return
    end

    -- Protected settings window creation
    local success, error = pcall(function()
        settingsFrame = AceGUI:Create("Frame")
        settingsFrame:SetTitle("GearLister Settings")
        settingsFrame:SetWidth(400)
        settingsFrame:SetHeight(350)
        settingsFrame:SetLayout("Flow")

        -- Force settings window to always be on top with solid background
        settingsFrame.frame:SetAlpha(1.0)
        settingsFrame.frame:SetFrameStrata("FULLSCREEN_DIALOG")
        settingsFrame.frame:SetFrameLevel(200)

        -- Enable Escape key functionality for settings window
        settingsFrame.frame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                settingsFrame:Hide()
                -- Stop propagation to prevent WoW main menu from opening
                return
            end
            -- Allow other keys to propagate normally
            self:SetPropagateKeyboardInput(true)
        end)
        settingsFrame.frame:SetPropagateKeyboardInput(false) -- Default to false, enable per-key
        settingsFrame.frame:EnableKeyboard(true)

        -- Create a solid black background
        if not settingsFrame.frame.solidBG then
            settingsFrame.frame.solidBG = settingsFrame.frame:CreateTexture(nil, "BACKGROUND")
            settingsFrame.frame.solidBG:SetAllPoints(settingsFrame.frame)
            settingsFrame.frame.solidBG:SetColorTexture(0, 0, 0, 1) -- Solid black
        end

        settingsFrame:SetCallback("OnClose", function(widget)
            widget:Hide()
            widget:Release()
            settingsFrame = nil
        end)

        -- Ensure it always stays on top
        settingsFrame:SetCallback("OnShow", function(widget)
            widget.frame:SetFrameStrata("FULLSCREEN_DIALOG")
            widget.frame:SetFrameLevel(200)
            widget.frame:Raise()
        end)

        -- Force raise when main window is shown
        if mainFrame then
            mainFrame:SetCallback("OnShow", function(widget)
                if settingsFrame and settingsFrame:IsShown() then
                    settingsFrame.frame:Raise()
                end
            end)
        end

        -- Delimiter setting
        local delimiterLabel = AceGUI:Create("Label")
        delimiterLabel:SetText("Delimiter between item name and Wowhead link:")
        delimiterLabel:SetFullWidth(true)
        settingsFrame:AddChild(delimiterLabel)

        local delimiterInput = AceGUI:Create("EditBox")
        delimiterInput:SetText(self.db.profile.settings.delimiter)
        delimiterInput:SetFullWidth(true)
        delimiterInput:SetCallback("OnTextChanged", function(widget, event, text)
            self:UpdateSettingsExample()
        end)
        settingsFrame:AddChild(delimiterInput)
        settingsFrame.delimiterInput = delimiterInput

        -- Newline checkbox
        local newlineCheckbox = AceGUI:Create("CheckBox")
        newlineCheckbox:SetLabel("Add newline after delimiter")
        newlineCheckbox:SetValue(self.db.profile.settings.addNewline)
        newlineCheckbox:SetFullWidth(true)
        newlineCheckbox:SetCallback("OnValueChanged", function(widget, event, value)
            self:UpdateSettingsExample()
        end)
        settingsFrame:AddChild(newlineCheckbox)
        settingsFrame.newlineCheckbox = newlineCheckbox

        -- Max history entries
        local maxEntriesLabel = AceGUI:Create("Label")
        maxEntriesLabel:SetText("Maximum history entries:")
        maxEntriesLabel:SetFullWidth(true)
        settingsFrame:AddChild(maxEntriesLabel)

        local maxEntriesInput = AceGUI:Create("EditBox")
        maxEntriesInput:SetText(tostring(self.db.profile.settings.maxHistoryEntries))
        maxEntriesInput:SetFullWidth(true)
        settingsFrame:AddChild(maxEntriesInput)
        settingsFrame.maxEntriesInput = maxEntriesInput

        -- Example text
        local exampleLabel = AceGUI:Create("Label")
        exampleLabel:SetFullWidth(true)
        settingsFrame:AddChild(exampleLabel)
        settingsFrame.exampleLabel = exampleLabel

        -- Update example initially
        self:UpdateSettingsExample()

        -- Buttons
        local buttonGroup = AceGUI:Create("SimpleGroup")
        buttonGroup:SetFullWidth(true)
        buttonGroup:SetLayout("Flow")
        settingsFrame:AddChild(buttonGroup)

        local saveButton = AceGUI:Create("Button")
        saveButton:SetText("Save")
        saveButton:SetWidth(100)
        saveButton:SetCallback("OnClick", function()
            self:SaveSettings()
        end)
        buttonGroup:AddChild(saveButton)

        local cancelButton = AceGUI:Create("Button")
        cancelButton:SetText("Cancel")
        cancelButton:SetWidth(100)
        cancelButton:SetCallback("OnClick", function()
            settingsFrame:Hide()
            settingsFrame:Release()
            settingsFrame = nil
        end)
        buttonGroup:AddChild(cancelButton)

        local resetButton = AceGUI:Create("Button")
        resetButton:SetText("Reset")
        resetButton:SetWidth(100)
        resetButton:SetCallback("OnClick", function()
            delimiterInput:SetText(" - ")
            newlineCheckbox:SetValue(false)
            maxEntriesInput:SetText("50")
            self:UpdateSettingsExample()
        end)
        buttonGroup:AddChild(resetButton)
    end)

    if not success then
        print("GearLister: Settings window creation failed - " .. tostring(error))
        return
    end
end

function GearLister:UpdateSettingsExample()
    if not settingsFrame or not settingsFrame.exampleLabel then return end

    local delimiter = settingsFrame.delimiterInput:GetText()
    local addNewline = settingsFrame.newlineCheckbox:GetValue()

    local actualDelimiter = delimiter
    if addNewline then
        actualDelimiter = delimiter .. "\n"
    end

    local exampleText = "|cff808080Example: Head: Lionheart Helm" ..
        actualDelimiter .. "https://classic.wowhead.com/item/12640|r"
    settingsFrame.exampleLabel:SetText(exampleText)
end

function GearLister:SaveSettings()
    if not settingsFrame then return end

    local settings = self.db.profile.settings
    settings.delimiter = settingsFrame.delimiterInput:GetText()
    settings.addNewline = settingsFrame.newlineCheckbox:GetValue()

    local maxEntries = tonumber(settingsFrame.maxEntriesInput:GetText())
    if maxEntries and maxEntries > 0 then
        settings.maxHistoryEntries = maxEntries

        -- Trim history if needed
        local gearHistory = self.db.profile.gearHistory
        while #gearHistory > maxEntries do
            table.remove(gearHistory)
        end
    end

    local newlineText = settings.addNewline and " (with newline)" or ""
    self:Print("|cff00ff00Settings saved - Delimiter: '" .. settings.delimiter .. "'" .. newlineText .. "|r")

    settingsFrame:Hide()
    settingsFrame:Release()
    settingsFrame = nil

    -- Update main window if open
    if mainFrame then
        self:RefreshGearDisplay()
    end
end

-- Slash Command Handler
function GearLister:SlashProcessor(input)
    -- Safety check to ensure addon is fully loaded
    if not self.db then
        self:Print("|cffff0000GearLister is not fully loaded yet. Please try again in a moment.|r")
        return
    end
    local command = string.lower(string.trim(input or ""))

    if command == "inspect" then
        if self:StartInspect() then
            -- Inspect started successfully, dialog will open when ready
        end
    else
        -- Reset any previous state
        ClearInspectPlayer()
        currentHistoryIndex = nil

        -- Check for target and determine mode automatically
        if self:DetermineTargetMode() then
            if not inspectMode then
                -- No inspect mode, show dialog immediately
                self:ShowMainWindow()
            end
            -- If inspect mode started, dialog will open when ready via event
        end
    end
end
