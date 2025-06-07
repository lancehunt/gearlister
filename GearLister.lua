-- GearLister Addon for WoW Classic
-- Shows equipped gear in a copyable dialog

local GearLister = {}
local frame = nil
local settingsFrame = nil
local historyFrame = nil
local inspectMode = false
local inspectTarget = nil

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
    {slot = 1, name = "Head"},
    {slot = 2, name = "Neck"},
    {slot = 3, name = "Shoulders"},
    {slot = 15, name = "Back"},
    {slot = 5, name = "Chest"},
    {slot = 9, name = "Wrist"},
    {slot = 10, name = "Gloves"},
    {slot = 6, name = "Belt"},
    {slot = 7, name = "Legs"},
    {slot = 8, name = "Feet"},
    {slot = 11, name = "Ring1"},
    {slot = 12, name = "Ring2"},
    {slot = 13, name = "Trinket1"},
    {slot = 14, name = "Trinket2"},
    {slot = 16, name = "Main Hand"},
    {slot = 17, name = "Off Hand"},
    {slot = 18, name = "Ranged"}
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
        -- Small delay to ensure all data is loaded
        C_Timer.After(0.5, function()
            GearLister:CreateGearDialog()
        end)
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
        
        local exampleText = "Example: Head: Lionheart Helm" .. actualDelimiter .. "https://classic.wowhead.com/item/12640"
        settingsFrame.exampleLabel:SetText(exampleText)
    end
end

-- Function to create history dialog
function GearLister:CreateHistoryDialog()
    if historyFrame then
        historyFrame:Show()
        historyFrame:Raise()
        GearLister:UpdateHistoryList()
        return
    end
    
    -- Create history frame (keep full opacity)
    historyFrame = CreateFrame("Frame", "GearListerHistoryFrame", UIParent, "BasicFrameTemplateWithInset")
    historyFrame:SetSize(600, 500)
    historyFrame:SetPoint("CENTER", 50, 0) -- Offset from center to avoid overlap
    historyFrame:SetMovable(true)
    historyFrame:EnableMouse(true)
    historyFrame:RegisterForDrag("LeftButton")
    historyFrame:SetScript("OnDragStart", historyFrame.StartMoving)
    historyFrame:SetScript("OnDragStop", historyFrame.StopMovingOrSizing)
    historyFrame:SetFrameStrata("DIALOG")
    historyFrame:SetFrameLevel(90)
    
    -- Set title
    historyFrame.title = historyFrame:CreateFontString(nil, "OVERLAY")
    historyFrame.title:SetFontObject("GameFontHighlight")
    historyFrame.title:SetPoint("LEFT", historyFrame.TitleBg, "LEFT", 5, 0)
    historyFrame.title:SetText("Gear History")
    
    -- Create scroll frame for the history list
    local scrollFrame = CreateFrame("ScrollFrame", "GearListerHistoryScrollFrame", historyFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", historyFrame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", historyFrame, "BOTTOMRIGHT", -30, 70)
    
    -- Create content frame for history entries
    local contentFrame = CreateFrame("Frame", "GearListerHistoryContent", scrollFrame)
    contentFrame:SetSize(550, 400)
    scrollFrame:SetScrollChild(contentFrame)
    
    -- Create close button
    local closeButton = CreateFrame("Button", "GearListerHistoryCloseButton", historyFrame, "GameMenuButtonTemplate")
    closeButton:SetSize(80, 25)
    closeButton:SetPoint("BOTTOMRIGHT", historyFrame, "BOTTOMRIGHT", -10, 10)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        historyFrame:Hide()
    end)
    
    -- Create clear history button
    local clearButton = CreateFrame("Button", "GearListerHistoryClearButton", historyFrame, "GameMenuButtonTemplate")
    clearButton:SetSize(100, 25)
    clearButton:SetPoint("BOTTOMLEFT", historyFrame, "BOTTOMLEFT", 10, 10)
    clearButton:SetText("Clear History")
    clearButton:SetScript("OnClick", function()
        gearHistory = {}
        GearLister:UpdateHistoryList()
        print("|cff00ff00GearLister:|r History cleared.")
    end)
    
    -- Create refresh button
    local refreshButton = CreateFrame("Button", "GearListerHistoryRefreshButton", historyFrame, "GameMenuButtonTemplate")
    refreshButton:SetSize(80, 25)
    refreshButton:SetPoint("BOTTOM", historyFrame, "BOTTOM", 0, 10)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        GearLister:UpdateHistoryList()
    end)
    
    -- Store references
    historyFrame.contentFrame = contentFrame
    historyFrame.scrollFrame = scrollFrame
    historyFrame.entries = {}
    
    -- Initial population
    GearLister:UpdateHistoryList()
    
    -- Ensure dialog stays on top when shown
    historyFrame:SetScript("OnShow", function(self)
        self:Raise()
    end)
end

-- Function to update history list display
function GearLister:UpdateHistoryList()
    if not historyFrame or not historyFrame.contentFrame then
        return
    end
    
    -- Clear existing entries
    for _, entry in pairs(historyFrame.entries) do
        entry:Hide()
    end
    historyFrame.entries = {}
    
    local yOffset = 0
    
    if #gearHistory == 0 then
        -- Show empty message
        local emptyText = historyFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("TOP", historyFrame.contentFrame, "TOP", 0, -20)
        emptyText:SetText("No gear history available.")
        emptyText:SetTextColor(0.7, 0.7, 0.7)
        table.insert(historyFrame.entries, emptyText)
        return
    end
    
    -- Create history entries
    for i, historyEntry in ipairs(gearHistory) do
        -- Create entry frame
        local entryFrame = CreateFrame("Frame", "GearListerHistoryEntry" .. i, historyFrame.contentFrame)
        entryFrame:SetSize(540, 80)
        entryFrame:SetPoint("TOP", historyFrame.contentFrame, "TOP", 0, yOffset)
        
        -- Create background for entry
        local bg = entryFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
        
        -- Character name and timestamp
        local headerText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        headerText:SetPoint("TOPLEFT", entryFrame, "TOPLEFT", 10, -5)
        headerText:SetText(historyEntry.characterName .. " - " .. historyEntry.displayTime)
        
        -- Gear summary (first few items)
        local summaryItems = {}
        for j = 1, math.min(3, #historyEntry.items) do
            local item = historyEntry.items[j]
            local itemName = string.match(item, ": (.+)" .. string.gsub(GearLister:GetActualDelimiter(), "([^%w])", "%%%1"))
            if itemName then
                table.insert(summaryItems, itemName)
            end
        end
        if #historyEntry.items > 3 then
            table.insert(summaryItems, "... (" .. (#historyEntry.items - 3) .. " more)")
        end
        
        local summaryText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        summaryText:SetPoint("TOPLEFT", headerText, "BOTTOMLEFT", 0, -5)
        summaryText:SetPoint("TOPRIGHT", entryFrame, "TOPRIGHT", -100, -25)
        summaryText:SetJustifyH("LEFT")
        summaryText:SetWordWrap(true)
        summaryText:SetText(table.concat(summaryItems, ", "))
        summaryText:SetTextColor(0.8, 0.8, 0.8)
        
        -- View button
        local viewButton = CreateFrame("Button", "GearListerHistoryViewButton" .. i, entryFrame, "GameMenuButtonTemplate")
        viewButton:SetSize(60, 20)
        viewButton:SetPoint("TOPRIGHT", entryFrame, "TOPRIGHT", -10, -5)
        viewButton:SetText("View")
        viewButton:SetScript("OnClick", function()
            GearLister:ShowHistoryEntry(historyEntry)
        end)
        
        -- Delete button
        local deleteButton = CreateFrame("Button", "GearListerHistoryDeleteButton" .. i, entryFrame, "GameMenuButtonTemplate")
        deleteButton:SetSize(60, 20)
        deleteButton:SetPoint("TOPRIGHT", viewButton, "BOTTOMRIGHT", 0, -5)
        deleteButton:SetText("Delete")
        deleteButton:SetScript("OnClick", function()
            table.remove(gearHistory, i)
            GearLister:UpdateHistoryList()
        end)
        
        table.insert(historyFrame.entries, entryFrame)
        yOffset = yOffset - 90
    end
    
    -- Update content frame height
    historyFrame.contentFrame:SetHeight(math.max(400, math.abs(yOffset)))
end

-- Function to show a specific history entry in the main dialog
function GearLister:ShowHistoryEntry(historyEntry)
    -- Create or show main dialog
    if not frame then
        GearLister:CreateGearDialog()
    end
    
    frame:Show()
    
    -- Update title to show it's a historical entry
    frame.titleText:SetText("Gear History - " .. historyEntry.characterName .. " (" .. historyEntry.displayTime .. ")")
    
    -- Display the historical gear
    local gearText = table.concat(historyEntry.items, "\n")
    frame.editBox:SetText(gearText)
    frame.editBox:HighlightText()
    frame.editBox:SetCursorPosition(0)
end

-- Function to create settings dialog
function GearLister:CreateSettingsDialog()
    if settingsFrame then
        settingsFrame:Show()
        settingsFrame:Raise() -- Bring to front
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
    settingsFrame:SetFrameStrata("DIALOG") -- Ensure it's on top
    settingsFrame:SetFrameLevel(100) -- High frame level
    
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
    local newlineCheckbox = CreateFrame("CheckButton", "GearListerNewlineCheckbox", settingsFrame, "UICheckButtonTemplate")
    newlineCheckbox:SetPoint("TOPLEFT", delimiterInput, "BOTTOMLEFT", 0, -10)
    newlineCheckbox:SetChecked(settings.addNewline)
    
    -- Newline checkbox label
    local newlineLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    newlineLabel:SetPoint("LEFT", newlineCheckbox, "RIGHT", 5, 0)
    newlineLabel:SetText("Add newline after delimiter")
    
    -- Example text (with wrapping)
    local exampleLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exampleLabel:SetPoint("TOPLEFT", newlineCheckbox, "BOTTOMLEFT", 0, -15)
    exampleLabel:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -20, -155) -- Adjusted for new checkbox
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
        C_Timer.After(0.01, function() -- Tiny delay to ensure text is updated
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
            GearLister:UpdateGearList()
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
        return
    end
    
    -- Create main frame with 50% opacity
    frame = CreateFrame("Frame", "GearListerFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 600)
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
    
    -- Create scroll frame for the text
    local scrollFrame = CreateFrame("ScrollFrame", "GearListerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 70) -- Adjusted for additional button row
    
    -- Create editbox for the gear list
    local editBox = CreateFrame("EditBox", "GearListerEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(460)
    editBox:SetHeight(500)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    
    -- Enable text selection with mouse
    editBox:SetScript("OnMouseUp", function(self)
        self:HighlightText()
    end)
    
    scrollFrame:SetScrollChild(editBox)
    
    -- Create refresh button
    local refreshButton = CreateFrame("Button", "GearListerRefreshButton", frame, "GameMenuButtonTemplate")
    refreshButton:SetSize(80, 25)
    refreshButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 40)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        GearLister:UpdateGearList()
    end)
    
    -- Create close button
    local closeButton = CreateFrame("Button", "GearListerCloseButton", frame, "GameMenuButtonTemplate")
    closeButton:SetSize(80, 25)
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
        -- Reset inspect mode when closing
        inspectMode = false
        inspectTarget = nil
        ClearInspectPlayer()
    end)
    
    -- Create settings button (gear icon)
    local settingsButton = CreateFrame("Button", "GearListerSettingsButton", frame, "GameMenuButtonTemplate")
    settingsButton:SetSize(25, 25)
    settingsButton:SetPoint("BOTTOM", frame, "BOTTOM", -40, 40)
    settingsButton:SetText("⚙")
    settingsButton:SetScript("OnClick", function()
        GearLister:CreateSettingsDialog()
    end)
    
    -- Create history button
    local historyButton = CreateFrame("Button", "GearListerHistoryButton", frame, "GameMenuButtonTemplate")
    historyButton:SetSize(80, 25)
    historyButton:SetPoint("BOTTOM", frame, "BOTTOM", 40, 40)
    historyButton:SetText("History")
    historyButton:SetScript("OnClick", function()
        GearLister:CreateHistoryDialog()
    end)
    
    -- Create save button (saves current gear to history)
    local saveButton = CreateFrame("Button", "GearListerSaveButton", frame, "GameMenuButtonTemplate")
    saveButton:SetSize(60, 25)
    saveButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", function()
        local characterName = inspectMode and inspectTarget or UnitName("player")
        local items = GearLister:GetEquippedItems(inspectMode and "target" or "player")
        GearLister:SaveToHistory(characterName, items)
        print("|cff00ff00GearLister:|r Gear saved to history for " .. characterName)
    end)
    
    -- Create credit text
    local creditText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    creditText:SetPoint("BOTTOM", frame, "BOTTOM", 0, -8)
    creditText:SetText("Made with <3 by Bunnycrits")
    creditText:SetTextColor(0.7, 0.7, 0.7)
    
    -- Store references
    frame.editBox = editBox
    frame.scrollFrame = scrollFrame
    
    -- Initial population
    GearLister:UpdateGearList()
end

-- Function to update the gear list in the dialog
function GearLister:UpdateGearList()
    if not frame or not frame.editBox then
        return
    end
    
    local targetUnit = "player"
    local titleSuffix = ""
    
    if inspectMode and inspectTarget then
        targetUnit = "target"
        titleSuffix = " - " .. inspectTarget
        frame.titleText:SetText("Equipped Gear List (with Wowhead Links)" .. titleSuffix)
    else
        frame.titleText:SetText("Equipped Gear List (with Wowhead Links)")
    end
    
    local items = GearLister:GetEquippedItems(targetUnit)
    local gearText = table.concat(items, "\n")
    
    frame.editBox:SetText(gearText)
    frame.editBox:HighlightText()
    frame.editBox:SetCursorPosition(0)
    
    -- Auto-save current gear to history when viewing
    local characterName = inspectMode and inspectTarget or UnitName("player")
    GearLister:SaveToHistory(characterName, items)
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
    elseif command == "history" then
        GearLister:CreateHistoryDialog()
    else
        -- Reset inspect mode for normal use
        inspectMode = false
        inspectTarget = nil
        ClearInspectPlayer()
        GearLister:CreateGearDialog()
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
        print("|cff00ff00GearLister:|r Use /gearlist history to view gear history.")
    elseif event == "INSPECT_READY" then
        GearLister:OnInspectReady()
    end
end)