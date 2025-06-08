-- GearLister Addon for WoW Classic
-- Shows equipped gear in a copyable dialog with integrated history panel

local GearLister = {}
local frame = nil
local settingsFrame = nil
local inspectMode = false
local inspectTarget = nil
local currentHistoryIndex = nil -- Track which history entry is selected

-- Default settings
local settings = {
    delimiter = " - ",
    addNewline = false
}

-- History storage (will persist across sessions if saved variables are implemented)
local gearHistory = {}

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

-- Function to extract item ID from item link
function GearLister:GetItemIdFromLink(itemLink)
    if not itemLink then return nil end
    local itemId = string.match(itemLink, "item:(%d+)")
    return itemId
end

-- Function to get the actual delimiter (with optional newline)
function GearLister:GetActualDelimiter()
    local delimiter = settings.delimiter
    if settings.addNewline then
        delimiter = delimiter .. "\n"
    end
    return delimiter
end

-- Function to get all equipped items with Wowhead links
function GearLister:GetEquippedItems(unit)
    local items = {}
    local targetUnit = unit or "player"
    local actualDelimiter = GearLister:GetActualDelimiter()

    -- Iterate through slots in the specified display order
    for _, slotInfo in ipairs(DISPLAY_ORDER) do
        local slotId = slotInfo.slot
        local slotName = slotInfo.name
        local itemLink = GetInventoryItemLink(targetUnit, slotId)

        if itemLink then
            local itemName = GetItemInfo(itemLink)
            local itemId = GearLister:GetItemIdFromLink(itemLink)
            if itemName and itemId then
                local wowheadLink = "https://classic.wowhead.com/item=" .. itemId
                local itemEntry = slotName .. ": " .. itemName .. actualDelimiter .. wowheadLink
                table.insert(items, itemEntry)
            end
        end
    end

    return items
end

-- Function to create a hash of gear items for comparison
function GearLister:CreateGearHash(items)
    local concatenated = table.concat(items, "|")
    return concatenated
end

-- Function to save gear to history
function GearLister:SaveToHistory(characterName, items)
    local gearHash = GearLister:CreateGearHash(items)
    local timestamp = date("%Y-%m-%d %H:%M:%S")

    -- Check if this exact gear set already exists
    for i, entry in ipairs(gearHistory) do
        if entry.hash == gearHash then
            -- Update timestamp and move to front
            entry.timestamp = timestamp
            entry.displayTime = date("%m/%d %H:%M")
            table.remove(gearHistory, i)
            table.insert(gearHistory, 1, entry)
            GearLister:UpdateHistoryPanel()
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

    -- Keep only the most recent 50 entries
    while #gearHistory > 50 do
        table.remove(gearHistory)
    end

    -- Update history panel if frame exists
    GearLister:UpdateHistoryPanel()
end

-- Function to get current target name safely
function GearLister:GetCurrentTargetName()
    if inspectMode and UnitExists("target") and UnitIsPlayer("target") then
        return UnitName("target")
    end
    return nil
end

-- Function to start inspect mode
function GearLister:StartInspect()
    if not UnitExists("target") then
        print("|cffff0000GearLister:|r No target selected. Please target a player first.")
        return false
    end

    if not UnitIsPlayer("target") then
        print("|cffff0000GearLister:|r Target must be a player.")
        return false
    end

    if not CheckInteractDistance("target", 1) then
        print("|cffff0000GearLister:|r Target is too far away to inspect.")
        return false
    end

    -- Clear any previous inspect data
    ClearInspectPlayer()

    -- Set inspect mode and capture current target name
    inspectMode = true
    inspectTarget = UnitName("target")

    -- Start the inspect
    InspectUnit("target")

    print("|cff00ff00GearLister:|r Inspecting " .. inspectTarget .. "...")

    return true
end

-- Function to handle inspect ready event
function GearLister:OnInspectReady()
    if inspectMode then
        -- Verify we still have the same target
        local currentTarget = GearLister:GetCurrentTargetName()
        if currentTarget and currentTarget == inspectTarget then
            -- Small delay to ensure all data is loaded
            C_Timer.After(0.5, function()
                GearLister:CreateGearDialog()
            end)
        else
            -- Target changed or lost, cancel inspect mode
            print("|cffff0000GearLister:|r Target changed during inspect. Please try again.")
            inspectMode = false
            inspectTarget = nil
            ClearInspectPlayer()
        end
    end
end

-- Function to update example text in settings
function GearLister:UpdateExampleText()
    if settingsFrame and settingsFrame.exampleLabel then
        local delimiter = settingsFrame.delimiterInput:GetText()
        local actualDelimiter = delimiter
        if settingsFrame.newlineCheckbox:GetChecked() then
            actualDelimiter = delimiter .. "\n"
        end

        local exampleText = "Example: Head: Lionheart Helm" ..
            actualDelimiter .. "https://classic.wowhead.com/item/12640"
        settingsFrame.exampleLabel:SetText(exampleText)
    end
end

-- Function to select a history entry
function GearLister:SelectHistoryEntry(index)
    currentHistoryIndex = index

    -- Update button states
    GearLister:UpdateHistoryPanel()

    -- Update gear display
    if index and gearHistory[index] then
        local historyEntry = gearHistory[index]
        local gearText = table.concat(historyEntry.items, "\n")
        frame.editBox:SetText(gearText)
        frame.editBox:HighlightText()
        frame.editBox:SetCursorPosition(0)

        -- Update title
        frame.titleText:SetText("Gear History - " ..
            historyEntry.characterName .. " (" .. historyEntry.displayTime .. ")")
    else
        -- Show current gear
        GearLister:UpdateGearList()
    end
end

-- Function to update history panel
function GearLister:UpdateHistoryPanel()
    if not frame or not frame.historyPanel then
        return
    end

    -- Clear existing entries
    if frame.historyEntries then
        for _, entry in pairs(frame.historyEntries) do
            entry:Hide()
        end
    end
    frame.historyEntries = {}

    local yOffset = -5

    -- "Current Gear" button
    local currentButton = CreateFrame("Button", "GearListerCurrentButton", frame.historyPanel, "GameMenuButtonTemplate")
    currentButton:SetSize(180, 25)
    currentButton:SetPoint("TOP", frame.historyPanel, "TOP", 0, yOffset)
    currentButton:SetText("Current Gear")

    -- Highlight if current gear is selected
    if not currentHistoryIndex then
        currentButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
        currentButton:GetNormalTexture():SetVertexColor(0.2, 0.6, 1.0, 0.3)
    end

    currentButton:SetScript("OnClick", function()
        inspectMode = false
        inspectTarget = nil
        currentHistoryIndex = nil
        ClearInspectPlayer()
        GearLister:SelectHistoryEntry(nil)
    end)

    table.insert(frame.historyEntries, currentButton)
    yOffset = yOffset - 30

    -- History entries
    if #gearHistory == 0 then
        local emptyText = frame.historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        emptyText:SetPoint("TOP", frame.historyPanel, "TOP", 0, yOffset)
        emptyText:SetText("No history available")
        emptyText:SetTextColor(0.6, 0.6, 0.6)
        table.insert(frame.historyEntries, emptyText)
        yOffset = yOffset - 30
    else
        for i, historyEntry in ipairs(gearHistory) do
            local entryButton = CreateFrame("Button", "GearListerHistoryEntry" .. i, frame.historyPanel,
                "GameMenuButtonTemplate")
            entryButton:SetSize(180, 40)
            entryButton:SetPoint("TOP", frame.historyPanel, "TOP", 0, yOffset)

            -- Highlight if this entry is selected
            if currentHistoryIndex == i then
                entryButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
                entryButton:GetNormalTexture():SetVertexColor(0.2, 0.6, 1.0, 0.3)
            end

            -- Button text (character name and time)
            local buttonText = historyEntry.characterName .. "\n" .. historyEntry.displayTime
            entryButton:SetText(buttonText)
            entryButton:GetFontString():SetJustifyH("CENTER")

            entryButton:SetScript("OnClick", function()
                GearLister:SelectHistoryEntry(i)
            end)

            -- Delete button (small X in corner)
            local deleteButton = CreateFrame("Button", "GearListerHistoryDelete" .. i, entryButton)
            deleteButton:SetSize(16, 16)
            deleteButton:SetPoint("TOPRIGHT", entryButton, "TOPRIGHT", -2, -2)
            deleteButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
            deleteButton:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
            deleteButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
            deleteButton:SetScript("OnClick", function()
                table.remove(gearHistory, i)
                -- Reset selection if we deleted the selected entry
                if currentHistoryIndex == i then
                    currentHistoryIndex = nil
                    GearLister:SelectHistoryEntry(nil)
                elseif currentHistoryIndex and currentHistoryIndex > i then
                    currentHistoryIndex = currentHistoryIndex - 1
                end
                GearLister:UpdateHistoryPanel()
            end)

            table.insert(frame.historyEntries, entryButton)
            yOffset = yOffset - 45
        end
    end

    -- Add Clear History button at the bottom of the history panel
    local clearHistoryButton = CreateFrame("Button", "GearListerClearHistoryButton", frame.historyPanel,
        "GameMenuButtonTemplate")
    clearHistoryButton:SetSize(160, 25)
    clearHistoryButton:SetPoint("TOP", frame.historyPanel, "TOP", 0, yOffset - 20)
    clearHistoryButton:SetText("Clear History")
    clearHistoryButton:SetScript("OnClick", function()
        gearHistory = {}
        currentHistoryIndex = nil
        GearLister:UpdateHistoryPanel()
        GearLister:UpdateGearList()
        print("|cff00ff00GearLister:|r History cleared.")
    end)

    table.insert(frame.historyEntries, clearHistoryButton)

    -- Update scroll height to accommodate the new button
    frame.historyPanel:SetHeight(math.max(400, math.abs(yOffset - 50) + 50))
end

-- Function to create settings dialog
function GearLister:CreateSettingsDialog()
    if settingsFrame then
        settingsFrame:Show()
        settingsFrame:Raise()
        return
    end

    -- Create settings frame (keep full opacity)
    settingsFrame = CreateFrame("Frame", "GearListerSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    settingsFrame:SetSize(350, 280)
    settingsFrame:SetPoint("CENTER")
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:RegisterForDrag("LeftButton")
    settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
    settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing)
    settingsFrame:SetFrameStrata("DIALOG")
    settingsFrame:SetFrameLevel(100)

    -- Set title
    settingsFrame.title = settingsFrame:CreateFontString(nil, "OVERLAY")
    settingsFrame.title:SetFontObject("GameFontHighlight")
    settingsFrame.title:SetPoint("LEFT", settingsFrame.TitleBg, "LEFT", 5, 0)
    settingsFrame.title:SetText("GearLister Settings")

    -- Delimiter label
    local delimiterLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    delimiterLabel:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 20, -50)
    delimiterLabel:SetText("Delimiter between item name and Wowhead link:")

    -- Delimiter input box
    local delimiterInput = CreateFrame("EditBox", "GearListerDelimiterInput", settingsFrame, "InputBoxTemplate")
    delimiterInput:SetSize(200, 20)
    delimiterInput:SetPoint("TOPLEFT", delimiterLabel, "BOTTOMLEFT", 0, -10)
    delimiterInput:SetText(settings.delimiter)
    delimiterInput:SetAutoFocus(false)
    delimiterInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    delimiterInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Newline checkbox
    local newlineCheckbox = CreateFrame("CheckButton", "GearListerNewlineCheckbox", settingsFrame,
        "UICheckButtonTemplate")
    newlineCheckbox:SetPoint("TOPLEFT", delimiterInput, "BOTTOMLEFT", 0, -10)
    newlineCheckbox:SetChecked(settings.addNewline)

    -- Newline checkbox label
    local newlineLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    newlineLabel:SetPoint("LEFT", newlineCheckbox, "RIGHT", 5, 0)
    newlineLabel:SetText("Add newline after delimiter")

    -- Example text (with wrapping)
    local exampleLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exampleLabel:SetPoint("TOPLEFT", newlineCheckbox, "BOTTOMLEFT", 0, -15)
    exampleLabel:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -20, -155)
    exampleLabel:SetJustifyH("LEFT")
    exampleLabel:SetWordWrap(true)
    exampleLabel:SetTextColor(0.7, 0.7, 0.7)

    -- Update example when delimiter changes
    delimiterInput:SetScript("OnTextChanged", function(self)
        GearLister:UpdateExampleText()
    end)

    -- Update example when checkbox changes
    newlineCheckbox:SetScript("OnClick", function(self)
        GearLister:UpdateExampleText()
    end)

    -- Also update on character input for immediate feedback
    delimiterInput:SetScript("OnChar", function(self)
        C_Timer.After(0.01, function()
            GearLister:UpdateExampleText()
        end)
    end)

    -- Save button
    local saveButton = CreateFrame("Button", "GearListerSaveButton", settingsFrame, "GameMenuButtonTemplate")
    saveButton:SetSize(80, 25)
    saveButton:SetPoint("BOTTOMLEFT", settingsFrame, "BOTTOMLEFT", 20, 15)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", function()
        settings.delimiter = delimiterInput:GetText()
        settings.addNewline = newlineCheckbox:GetChecked()
        local newlineText = settings.addNewline and " (with newline)" or ""
        print("|cff00ff00GearLister:|r Settings saved - Delimiter: '" .. settings.delimiter .. "'" .. newlineText)
        settingsFrame:Hide()
        -- Update current display if frame is open
        if frame and frame:IsShown() then
            if currentHistoryIndex then
                GearLister:SelectHistoryEntry(currentHistoryIndex)
            else
                GearLister:UpdateGearList()
            end
        end
    end)

    -- Cancel button
    local cancelButton = CreateFrame("Button", "GearListerCancelButton", settingsFrame, "GameMenuButtonTemplate")
    cancelButton:SetSize(80, 25)
    cancelButton:SetPoint("BOTTOMRIGHT", settingsFrame, "BOTTOMRIGHT", -20, 15)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function()
        delimiterInput:SetText(settings.delimiter)
        newlineCheckbox:SetChecked(settings.addNewline)
        GearLister:UpdateExampleText()
        settingsFrame:Hide()
    end)

    -- Reset button
    local resetButton = CreateFrame("Button", "GearListerResetButton", settingsFrame, "GameMenuButtonTemplate")
    resetButton:SetSize(80, 25)
    resetButton:SetPoint("BOTTOM", settingsFrame, "BOTTOM", 0, 15)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        delimiterInput:SetText(" - ")
        newlineCheckbox:SetChecked(false)
        GearLister:UpdateExampleText()
    end)

    -- Store references
    settingsFrame.delimiterInput = delimiterInput
    settingsFrame.newlineCheckbox = newlineCheckbox
    settingsFrame.exampleLabel = exampleLabel

    -- Initial example update
    GearLister:UpdateExampleText()

    -- Ensure dialog stays on top when shown
    settingsFrame:SetScript("OnShow", function(self)
        self:Raise()
    end)
end

function GearLister:CreateGearDialog()
    if frame then
        frame:Show()
        GearLister:UpdateGearList()
        GearLister:UpdateHistoryPanel()
        return
    end

    -- Create main frame with 50% opacity - make it wider for split pane
    frame = CreateFrame("Frame", "GearListerFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(800, 600) -- Increased width for split pane
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Set 50% opacity for the main dialog
    frame:SetAlpha(0.5)

    -- Set title
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.title:SetText("Equipped Gear List (with Wowhead Links)")

    -- Store title reference for updates
    frame.titleText = frame.title

    -- Create history panel (left side)
    local historyPanel = CreateFrame("ScrollFrame", "GearListerHistoryPanel", frame, "UIPanelScrollFrameTemplate")
    historyPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    historyPanel:SetSize(200, 500) -- Fixed width for history panel

    -- Create content frame for history
    local historyContent = CreateFrame("Frame", "GearListerHistoryContent", historyPanel)
    historyContent:SetSize(180, 500)
    historyPanel:SetScrollChild(historyContent)

    -- Create vertical separator line
    local separator = frame:CreateTexture(nil, "OVERLAY")
    separator:SetSize(2, 500)
    separator:SetPoint("LEFT", historyPanel, "RIGHT", 10, 0)
    separator:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    -- Create gear list panel (right side)
    local gearScrollFrame = CreateFrame("ScrollFrame", "GearListerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    gearScrollFrame:SetPoint("TOPLEFT", separator, "TOPRIGHT", 15, 0)
    gearScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 70)

    -- Create editbox for the gear list
    local editBox = CreateFrame("EditBox", "GearListerEditBox", gearScrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(540) -- Adjusted for new layout
    editBox:SetHeight(500)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Enable text selection with mouse
    editBox:SetScript("OnMouseUp", function(self)
        self:HighlightText()
    end)

    gearScrollFrame:SetScrollChild(editBox)

    -- Create refresh button
    local refreshButton = CreateFrame("Button", "GearListerRefreshButton", frame, "GameMenuButtonTemplate")
    refreshButton:SetSize(80, 25)
    refreshButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 40)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        if currentHistoryIndex then
            GearLister:SelectHistoryEntry(currentHistoryIndex)
        else
            -- Force refresh current gear and update history
            local characterName = inspectMode and GearLister:GetCurrentTargetName() or UnitName("player")
            if characterName then
                local items = GearLister:GetEquippedItems(inspectMode and "target" or "player")
                GearLister:SaveToHistory(characterName, items)
                GearLister:UpdateGearList()
                print("|cff00ff00GearLister:|r Refreshed gear for " .. characterName)
            else
                GearLister:UpdateGearList()
            end
        end
    end)

    -- Create close button
    local closeButton = CreateFrame("Button", "GearListerCloseButton", frame, "GameMenuButtonTemplate")
    closeButton:SetSize(80, 25)
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
        -- Reset modes when closing
        inspectMode = false
        inspectTarget = nil
        currentHistoryIndex = nil
        ClearInspectPlayer()
    end)

    -- Create settings button - moved to avoid overlap
    local settingsButton = CreateFrame("Button", "GearListerSettingsButton", frame, "GameMenuButtonTemplate")
    settingsButton:SetSize(70, 25)
    settingsButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 40)
    settingsButton:SetText("Settings")
    settingsButton:SetScript("OnClick", function()
        GearLister:CreateSettingsDialog()
    end)

    -- Create save button (saves current gear to history)
    local saveButton = CreateFrame("Button", "GearListerSaveButton", frame, "GameMenuButtonTemplate")
    saveButton:SetSize(60, 25)
    saveButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", function()
        local characterName = inspectMode and GearLister:GetCurrentTargetName() or UnitName("player")
        if characterName then
            local items = GearLister:GetEquippedItems(inspectMode and "target" or "player")
            GearLister:SaveToHistory(characterName, items)
            print("|cff00ff00GearLister:|r Gear saved to history for " .. characterName)
        else
            print("|cffff0000GearLister:|r Unable to determine character name.")
        end
    end)

    -- Create credit text
    local creditText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    creditText:SetPoint("BOTTOM", frame, "BOTTOM", 0, -8)
    creditText:SetText("Made with <3 by Bunnycrits")
    creditText:SetTextColor(0.7, 0.7, 0.7)

    -- Store references
    frame.editBox = editBox
    frame.scrollFrame = gearScrollFrame
    frame.historyPanel = historyContent
    frame.historyEntries = {}

    -- Initial population
    GearLister:UpdateGearList()
    GearLister:UpdateHistoryPanel()
end

-- Function to update the gear list in the dialog
function GearLister:UpdateGearList()
    if not frame or not frame.editBox then
        return
    end

    local targetUnit = "player"
    local characterName = UnitName("player")
    local titleSuffix = ""

    if inspectMode then
        local currentTarget = GearLister:GetCurrentTargetName()
        if currentTarget then
            targetUnit = "target"
            characterName = currentTarget
            titleSuffix = " - " .. characterName
            frame.titleText:SetText("Equipped Gear List (with Wowhead Links)" .. titleSuffix)
        else
            -- Target lost during inspect mode, fallback to player
            print("|cffff0000GearLister:|r Target lost, showing your gear instead.")
            inspectMode = false
            inspectTarget = nil
            ClearInspectPlayer()
            frame.titleText:SetText("Equipped Gear List (with Wowhead Links)")
        end
    else
        frame.titleText:SetText("Equipped Gear List (with Wowhead Links)")
    end

    local items = GearLister:GetEquippedItems(targetUnit)
    local gearText = table.concat(items, "\n")

    frame.editBox:SetText(gearText)
    frame.editBox:HighlightText()
    frame.editBox:SetCursorPosition(0)

    -- Auto-save current gear to history when viewing (only if we have valid character name)
    if characterName then
        GearLister:SaveToHistory(characterName, items)
    end

    -- Reset history selection since we're showing current
    currentHistoryIndex = nil
end

-- Function to check for target and determine mode
function GearLister:DetermineTargetMode()
    if UnitExists("target") and UnitIsPlayer("target") then
        -- We have a player target, check if we can inspect
        if CheckInteractDistance("target", 1) then
            -- Target is close enough to inspect
            return GearLister:StartInspect()
        else
            -- Target exists but too far, show player gear with message
            print("|cffff0000GearLister:|r Target is too far to inspect. Showing your gear instead.")
            inspectMode = false
            inspectTarget = nil
            return true
        end
    else
        -- No valid target, show player gear
        inspectMode = false
        inspectTarget = nil
        return true
    end
end

-- Slash command to show the dialog
SLASH_GEARLISTER1 = "/gear"
SLASH_GEARLISTER2 = "/gearlist"
SlashCmdList["GEARLISTER"] = function(msg)
    local command = string.lower(string.trim(msg or ""))

    if command == "inspect" then
        if GearLister:StartInspect() then
            -- Inspect started successfully, dialog will open when ready
        end
    else
        -- Reset any previous state
        ClearInspectPlayer()
        currentHistoryIndex = nil

        -- Check for target and determine mode automatically
        if GearLister:DetermineTargetMode() then
            -- Either inspect started or we're showing player gear
            if not inspectMode then
                -- No inspect mode, show dialog immediately
                GearLister:CreateGearDialog()
            end
            -- If inspect mode started, dialog will open when ready via event
        end
    end
end

-- Event handling for addon loaded and inspect ready
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GearLister" then
        print("|cff00ff00GearLister|r loaded! Use /gear or /gearlist to show your equipped items with Wowhead links.")
        print("|cff00ff00GearLister:|r Use /gearlist inspect to inspect your target's gear.")
        print(
            "|cff00ff00GearLister:|r /gear will automatically inspect your target if you have one, otherwise shows your gear.")
    elseif event == "INSPECT_READY" then
        GearLister:OnInspectReady()
    end
end)
