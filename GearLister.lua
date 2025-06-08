-- GearLister Addon for WoW Classic
-- Shows equipped gear in a copyable dialog with integrated history panel
-- Uses Ace3 libraries for modern UI and data management

local AceAddon = LibStub("AceAddon-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local AceDB = LibStub("AceDB-3.0")

-- Prevent duplicate addon creation
if AceAddon:GetAddon("GearLister", true) then
    return
end

local GearLister = AceAddon:NewAddon("GearLister", "AceConsole-3.0", "AceEvent-3.0")

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

function GearLister:OnInitialize()
    -- Initialize database
    self.db = AceDB:New("GearListerDB", defaults, true)

    -- Register slash commands
    self:RegisterChatCommand("gear", "SlashProcessor")
    self:RegisterChatCommand("gearlist", "SlashProcessor")

    -- Register events
    self:RegisterEvent("INSPECT_READY", "OnInspectReady")

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
                local itemEntry = slotName .. ": " .. itemName .. actualDelimiter .. wowheadLink
                table.insert(items, itemEntry)
            end
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

    -- Create main window
    mainFrame = AceGUI:Create("Frame")
    mainFrame:SetTitle("GearLister - Equipped Gear with Wowhead Links")
    mainFrame:SetWidth(900)
    mainFrame:SetHeight(650)
    mainFrame:SetLayout("Fill")
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

    -- History list label
    local historyLabel = AceGUI:Create("Label")
    historyLabel:SetText("Gear History:")
    historyLabel:SetWidth(200)
    historyLabel.frame:SetPoint("TOPLEFT", container.frame, "TOPLEFT", 10, -10)
    container:AddChild(historyLabel)

    -- History list
    local historyList = AceGUI:Create("ScrollFrame")
    historyList:SetWidth(200)
    historyList:SetHeight(500)
    historyList:SetLayout("List")
    historyList.frame:SetPoint("TOPLEFT", historyLabel.frame, "BOTTOMLEFT", 0, -5)
    container:AddChild(historyList)

    -- Store reference to history list
    mainFrame.historyList = historyList

    -- Current gear button
    local currentButton = AceGUI:Create("Button")
    currentButton:SetText("Current Gear")
    currentButton:SetFullWidth(true)
    currentButton:SetCallback("OnClick", function()
        self:SelectCurrentGear()
    end)
    historyList:AddChild(currentButton)

    -- Clear History button (positioned below history list)
    local clearHistoryButton = AceGUI:Create("Button")
    clearHistoryButton:SetText("Clear History")
    clearHistoryButton:SetWidth(200)
    clearHistoryButton:SetCallback("OnClick", function()
        self:ClearHistory()
    end)
    clearHistoryButton.frame:SetPoint("TOPLEFT", historyList.frame, "BOTTOMLEFT", 0, -10)
    container:AddChild(clearHistoryButton)

    -- Store reference for later updates
    mainFrame.clearHistoryButton = clearHistoryButton

    -- Gear display label
    local gearLabel = AceGUI:Create("Label")
    gearLabel:SetText("Equipped Gear:")
    gearLabel:SetWidth(600)
    gearLabel.frame:SetPoint("TOPLEFT", container.frame, "TOPLEFT", 230, -10)
    container:AddChild(gearLabel)

    -- Gear display
    local gearEditBox = AceGUI:Create("MultiLineEditBox")
    gearEditBox:SetWidth(600)
    gearEditBox:SetNumLines(20)
    gearEditBox:DisableButton(true)
    gearEditBox.frame:SetPoint("TOPLEFT", gearLabel.frame, "BOTTOMLEFT", 0, -5)
    container:AddChild(gearEditBox)

    -- Store reference to gear display
    mainFrame.gearEditBox = gearEditBox

    -- Control buttons - positioned manually
    local refreshButton = AceGUI:Create("Button")
    refreshButton:SetText("Refresh")
    refreshButton:SetWidth(100)
    refreshButton:SetCallback("OnClick", function()
        self:RefreshCurrentGear()
    end)
    refreshButton.frame:SetPoint("BOTTOMLEFT", container.frame, "BOTTOMLEFT", 230, 10)
    container:AddChild(refreshButton)

    local saveButton = AceGUI:Create("Button")
    saveButton:SetText("Save")
    saveButton:SetWidth(100)
    saveButton:SetCallback("OnClick", function()
        self:SaveCurrentGear()
    end)
    saveButton.frame:SetPoint("LEFT", refreshButton.frame, "RIGHT", 10, 0)
    container:AddChild(saveButton)

    local settingsButton = AceGUI:Create("Button")
    settingsButton:SetText("Settings")
    settingsButton:SetWidth(100)
    settingsButton:SetCallback("OnClick", function()
        self:ShowSettingsWindow()
    end)
    settingsButton.frame:SetPoint("LEFT", saveButton.frame, "RIGHT", 10, 0)
    container:AddChild(settingsButton)

    -- Credit text
    local creditText = AceGUI:Create("Label")
    creditText:SetText("|cff808080Made with <3 by Bunnycrits|r")
    creditText:SetWidth(200)
    creditText.frame:SetPoint("BOTTOM", container.frame, "BOTTOM", 0, -5)
    container:AddChild(creditText)

    -- Initialize display
    self:RefreshMainWindow()
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
            -- Keep the Current Gear button
            children[1] = child
        else
            child:Release()
        end
    end
    mainFrame.historyList.children = children

    -- Update current gear button highlighting
    if children[1] then
        if not currentHistoryIndex then
            children[1]:SetText("|cff00ff00Current Gear|r")
        else
            children[1]:SetText("Current Gear")
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
        if currentHistoryIndex == i then
            labelText = "|cff00ff00" .. labelText .. "|r"
        else
            labelText = "|cffffffff" .. labelText .. "|r"
        end
        entryLabel:SetText(labelText)
        entryLabel:SetWidth(160)
        entryLabel:SetCallback("OnClick", function()
            self:SelectHistoryEntry(i)
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
end

function GearLister:RefreshGearDisplay()
    if not mainFrame or not mainFrame.gearEditBox then return end

    local gearText = ""
    local titleSuffix = ""

    if currentHistoryIndex then
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

        -- Auto-save current gear to history
        if characterName then
            self:SaveToHistory(characterName, items)
        end
    end

    mainFrame.gearEditBox:SetText(gearText)
    mainFrame:SetTitle("GearLister - Equipped Gear with Wowhead Links" .. titleSuffix)
end

function GearLister:SelectCurrentGear()
    currentHistoryIndex = nil
    self:RefreshMainWindow()
end

function GearLister:SelectHistoryEntry(index)
    currentHistoryIndex = index
    self:RefreshMainWindow()
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
        inspectMode = false
        inspectTarget = nil
        currentHistoryIndex = nil
        ClearInspectPlayer()

        -- Re-determine target mode and fetch fresh gear
        if self:DetermineTargetMode() then
            if not inspectMode then
                -- No inspect mode, get current gear immediately
                local characterName = UnitName("player")
                local items = self:GetEquippedItems("player")
                self:SaveToHistory(characterName, items)
                self:RefreshMainWindow()
                self:Print("|cff00ff00Refreshed gear for " .. characterName .. "|r")
            else
                -- Inspect mode started, will update when ready
                self:Print("|cff00ff00Refreshing target gear...|r")
            end
        end
    end
end

function GearLister:SaveCurrentGear()
    local characterName = inspectMode and self:GetCurrentTargetName() or UnitName("player")
    if characterName then
        local items = self:GetEquippedItems(inspectMode and "target" or "player")
        self:SaveToHistory(characterName, items)
        self:Print("|cff00ff00Gear saved to history for " .. characterName .. "|r")
    else
        self:Print("|cffff0000Unable to determine character name.|r")
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
        settingsFrame:Raise()
        return
    end

    settingsFrame = AceGUI:Create("Frame")
    settingsFrame:SetTitle("GearLister Settings")
    settingsFrame:SetWidth(400)
    settingsFrame:SetHeight(350)
    settingsFrame:SetLayout("Flow")

    -- Make settings window completely opaque and always on top
    settingsFrame.frame:SetAlpha(1.0)
    settingsFrame.frame:SetFrameStrata("DIALOG")
    settingsFrame.frame:SetFrameLevel(100)

    settingsFrame:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)

    -- Ensure it stays on top when shown
    settingsFrame:SetCallback("OnShow", function(widget)
        widget.frame:Raise()
    end)

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
