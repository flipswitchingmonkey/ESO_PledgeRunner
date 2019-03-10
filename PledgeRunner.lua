local libScroll = LibStub:GetLibrary("LibScroll")

PledgeRunner = PledgeRunner or {}
local PR = PledgeRunner

-- set up some global vars
PR.name = "PledgeRunner"
PR.dataBoundaryPattern = "::PR::"
PR.writeGuildNoteSemaphore = false
PR.writeGuildNoteDelay = 0
PR.writeGuildNoteDelayAdd = 5000
PR.DEFAULT_TEXT = ZO_ColorDef:New(0.4627, 0.737, 0.7647, 1)
PR.defaults = {
    selectedGuildId = 1,
    left = 100,
    top = 100,
    width = 500,
    height = 500,
    guildEnabled = {false,false,false,false,false},
}
PR.scrollList = nil
PR.dataItems = { [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
PR.columnWidthUnit = 22
PR.columnUnits = { 0, 2.8, 2.8, 3.7, 0}
PR.currentZoneData = nil
PR.timerStart = nil
PR.filterQuestCategory = 1

-- set up enums
PR.EVENTS = {
    UNDEFINED = 99999999,
    COMBAT_STATE_ENTERED = 1,
    COMBAT_STATE_LEFT = 2,
    PLEDGE_ZONE_ENTERED = 3,
}

PR.ACTION = {
    UNDEFINED = 99999999,
    PLEDGE_ZONE_ENTERED = 1,
    PLEDGE_ZONE_STARTED = 2,
    PLEDGE_FINAL_REACHED = 3,
    PLEDGE_ZONE_LEFT = 4,
}

PR._last_event = PR.EVENTS.UNDEFINED
function PR:GetLastEvent()
    if self._last_event == nil then return PR.EVENTS.UNDEFINED
    else return self._last_event
    end
end
function PR:SetLastEvent(new_event)
    if new_event == nil then new_event = PR.EVENT.UNDEFINED end
    self._last_event = new_event
end

function PR.ClearDataItems(guildId)
    if guildId == nil then
        PR.dataItems = { [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
    else
        PR.dataItems[guildId] = {}
    end
end

-- basic addon register functions
function PR.OnAddOnLoaded(event, addonName)
    if addonName == PR.name then
        EVENT_MANAGER:UnregisterForEvent(PR.name, EVENT_ADD_ON_LOADED)
        PR:Initialize()
    end
end
EVENT_MANAGER:RegisterForEvent(PR.name,EVENT_ADD_ON_LOADED,PR.OnAddOnLoaded)

-- init function
function PR:Initialize()
    self.hidden = false
    self.locale = GetCVar('Language.2')
    if self.locale ~= 'en' and self.locale ~= 'de' then
        self.locale = 'en'
    end
    
    self.savedVariables = ZO_SavedVars:NewAccountWide("PledgeRunnerSavedVariables", 1, nil, self.defaults)
    -- Create the scrollList
    PR:CreateScrollList()

    if GetDisplayName() == "@flipswitchingmonkey" then
      SLASH_COMMANDS["/rr"] = function(cmd) ReloadUI() end
    end 
    SLASH_COMMANDS["/pledgerunner"] = function(cmd) PR.ShowUI() end

    -- REGISTER EVENTS
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_GUILD_MEMBER_NOTE_CHANGED, self.GuildMemberNoteChanged)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_QUEST_ADVANCED, self.OnQuestAdvanced)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_PLAYER_COMBAT_STATE, self.OnCombatStateChange)
    -- EVENT_MANAGER:RegisterForEvent(self.name, EVENT_ZONE_CHANGED, self.OnZoneChanged)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_PLAYER_ACTIVATED, self.OnPlayerActivated)
    
    -- EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_EXPERIENCE_GAIN, PledgeRunner.OnExperienceGain)
    -- EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_BOSSES_CHANGED, PledgeRunner.OnBossesChanged)
    -- EVENT_MANAGER:RegisterForEvent(PledgeRunner.name, EVENT_COMBAT_EVENT, PledgeRunner.OnCombatEvent)
    
    -- INIT MAINWINDOWS CONTROLS
    PR:InitWindow()
end

function PR:InitWindow()
    PledgeRunnerDialog:SetHandler("OnMoveStop", function(control)
        -- save new position
        self.savedVariables.left = control:GetLeft()
        self.savedVariables.top = control:GetTop()
    end)
    PledgeRunnerDialog:SetHandler("OnResizeStop", function(control)
        local width, height = control:GetDimensions()
        -- save new size
        self.savedVariables.width = width
        self.savedVariables.height = height
        -- adjust scrollList column widths to new dialog widths
        self.scrollList:SetAnchor(BOTTOMRIGHT, PledgeRunnerDialog, BOTTOMRIGHT, -10, -40)
        self.columnWidthUnit = (width - 128) / 10.0
        PledgeRunnerDialogHeadersName:SetDimensions(self.columnWidthUnit * self.columnUnits[2], 25)
        PledgeRunnerDialogHeadersZone:SetDimensions(self.columnWidthUnit * self.columnUnits[3], 25)
        PledgeRunnerDialogHeadersMessage:SetDimensions(self.columnWidthUnit * self.columnUnits[4], 25)
        PledgeRunnerDialogHeadersDeleteRow:SetDimensions(25, 25)
        self.scrollList:Update(self.dataItems[self.savedVariables.selectedGuildId])
    end)
    -- set button handlers
    -- PledgeRunnerDialogTestButton:SetHandler("OnClicked", self.TestButton_Clicked)
    PledgeRunnerDialogResetButton:SetHandler("OnClicked", self.ResetButton_Clicked)
    PledgeRunnerDialogResetButton:SetText(GetString(PLEDGERUNNER_BUTTON_CLEAR))
    PledgeRunnerDialogButtonCloseAddon:SetHandler("OnClicked", self.ToggleMainWindow)
  
    self.OnGuildSelectedCallback = function(_, _, entry)
        self:OnGuildSelected(entry)
    end
    self.OnFilterQuestSelectedCallback = function(_, _, entry)
        self:OnFilterQuestSelected(entry)
    end
  
    self.questFilterComboBox = PR:GetFilterQuestComboBox()
    self.guildComboBox = PR:GetGuildComboBox()
    self.guildComboBox:SetSortsItems(false)
    
    PR:RefreshGuildList()
    PR:RefreshFilterQuestList()
    PR:OnGuildSelected(self.guildComboEntries[self.savedVariables.selectedGuildId])
    PR:OnFilterQuestSelected(self.filterQuestComboEntries[1])
    self.questFilterComboBox:SetSelectedItemText(self.filterQuestComboEntries[1].name)
    ZO_CheckButton_SetToggleFunction(PledgeRunnerDialogEnableGuildCheck, self.EnableGuildCheck_OnToggle)
  
    self:RestorePosition()
end

-- Function that creates the scrollList 
function PR:CreateScrollList()
    -- setup scrollList parameters
    local categoriesTable = {1}
    for key, val in pairs(PR.ZONEDATA) do
        table.insert(categoriesTable, key)
    end
    local scrollData = {
    name            = "PledgeRunnerEvents",
    parent          = PledgeRunnerDialog,
    width           = 530,
    height          = 350,
    rowHeight       = 23,
    rowTemplate     = "PledgeRunnerEntryRow",
    setupCallback   = PR.SetupDataRow,
    sortFunction    = PR.SortScrollListByTime,
    -- selectTemplate  = "EmoteItSelectTemplate",
    -- selectCallback  = OnRowSelection,
    -- dataTypeSelectSound = SOUNDS.BOOK_CLOSE,
    -- hideCallback    = OnRowHide,
    -- resetCallback   = OnRowReset,
    categories  = categoriesTable,
    }
    
    self.scrollList = libScroll:CreateScrollList(scrollData)
    self.scrollList:SetAnchor(TOPLEFT, PledgeRunnerDialogHeaders, BOTTOMLEFT, 10, 10)
    self.scrollList:SetAnchor(BOTTOMRIGHT, PledgeRunnerDialog, BOTTOMRIGHT, -10, -40)

    -- Call Update to add the data items to the scrollList
    self.scrollList:Update(PR.dataItems[1])
end

function PR.SetupDataRow(rowControl, data, scrollList)
    -- Do whatever you want/need to setup the control
    rowControl.data = data
    rowControl.name = GetControl(rowControl, "Name")
    rowControl.time = GetControl(rowControl, "Time")
    rowControl.zone = GetControl(rowControl, "Zone")
    rowControl.message = GetControl(rowControl, "Message")
    rowControl.deleteRow = GetControl(rowControl, "DeleteRow")
    rowControl.deleteRow.fake_uuid = data.fake_uuid

    rowControl.name:SetText(data.name)
    rowControl.time:SetText(data.time)
    rowControl.zone:SetText(data.zone)
    rowControl.message:SetText(data.message)

    rowControl.name.normalColor = PR.DEFAULT_TEXT
    rowControl.time.normalColor = PR.DEFAULT_TEXT
    rowControl.zone.normalColor = PR.DEFAULT_TEXT
    rowControl.message.normalColor = PR.DEFAULT_TEXT
    -- rowControl:SetText(data.name)

    rowControl.name:SetDimensions(PR.columnWidthUnit * PR.columnUnits[2], 32)
    rowControl.zone:SetDimensions(PR.columnWidthUnit * PR.columnUnits[3], 32)
    rowControl.message:SetDimensions(PR.columnWidthUnit * PR.columnUnits[4], 32)
    rowControl.deleteRow:SetDimensions(25, 25)

    rowControl:SetFont("ZoFontWinH4")
end

function PR:GetGuildComboBox()
    local sc = WINDOW_MANAGER:GetControlByName("PledgeRunnerDialog")
    local guildComboBoxControl = sc:GetNamedChild("Guild")
    return ZO_ComboBox_ObjectFromContainer(guildComboBoxControl)
end

function PR:GetFilterQuestComboBox()
    local sc = WINDOW_MANAGER:GetControlByName("PledgeRunnerDialog")
    local guildComboBoxControl = sc:GetNamedChild("FilterQuest")
    return ZO_ComboBox_ObjectFromContainer(guildComboBoxControl)
end

function PR:RestorePosition()
    local left = self.savedVariables.left
    local top = self.savedVariables.top
    PledgeRunnerDialog:ClearAnchors()
    PledgeRunnerDialog:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, left, top)
    local width = PR.savedVariables.width
    local height = PR.savedVariables.height
    PR.columnWidthUnit = (width - 128) / 10.0
    PledgeRunnerDialogHeadersName:SetDimensions(PR.columnWidthUnit * PR.columnUnits[2], 25)
    PledgeRunnerDialogHeadersZone:SetDimensions(PR.columnWidthUnit * PR.columnUnits[3], 25)
    PledgeRunnerDialogHeadersMessage:SetDimensions(PR.columnWidthUnit * PR.columnUnits[4], 25)
    PledgeRunnerDialogHeadersDeleteRow:SetDimensions(25, 25)
    if (width ~= nil and height ~= nil) and (width > 100 and height > 100) then
        PledgeRunnerDialog:SetDimensions(width, height)
    else 
        PledgeRunnerDialog:SetDimensions(500,500)
    end
end

function PR.SortScrollListByName(objA, objB) return objA.data.name < objB.data.name end
function PR.SortScrollListByNameRev(objA, objB) return objA.data.name > objB.data.name end
function PR.SortScrollListByTime(objA, objB) return objA.data.time < objB.data.time end
function PR.SortScrollListByTimeRev(objA, objB) return objA.data.time > objB.data.time end
function PR.SortScrollListByZone(objA, objB) return objA.data.zone < objB.data.zone end
function PR.SortScrollListByZoneRev(objA, objB) return objA.data.zone > objB.data.zone end
function PR.SortScrollListByMessage(objA, objB) return objA.data.message < objB.data.message end
function PR.SortScrollListByMessageRev(objA, objB) return objA.data.message > objB.data.message end

function PR:HeaderTimeClicked()
    if PR.scrollList.SortFunction == PR.SortScrollListByTime then
        PR.scrollList.SortFunction = PR.SortScrollListByTimeRev
    else
        PR.scrollList.SortFunction = PR.SortScrollListByTime
    end
    PR.scrollList:Update(PR.dataItems[PR.savedVariables.selectedGuildId])
    -- PR:ApplyFilterQuest()
end
  
function PR:HeaderNameClicked()
    if PR.scrollList.SortFunction == PR.SortScrollListByName then
        PR.scrollList.SortFunction = PR.SortScrollListByNameRev
    else
        PR.scrollList.SortFunction = PR.SortScrollListByName
    end
    PR.scrollList:Update(PR.dataItems[PR.savedVariables.selectedGuildId])
    -- PR:ApplyFilterQuest()
end
  
function PR:HeaderZoneClicked()
    if PR.scrollList.SortFunction == PR.SortScrollListByZone then
        PR.scrollList.SortFunction = PR.SortScrollListByZoneRev
    else
        PR.scrollList.SortFunction = PR.SortScrollListByZone
    end
    PR.scrollList:Update(PR.dataItems[PR.savedVariables.selectedGuildId])
    -- PR:ApplyFilterQuest()
end
  
function PR:HeaderMessageClicked()
    if PR.scrollList.SortFunction == PR.SortScrollListByMessage then
        PR.scrollList.SortFunction = PR.SortScrollListByMessageRev
    else
        PR.scrollList.SortFunction = PR.SortScrollListByMessage
    end
    PR.scrollList:Update(PR.dataItems[PR.savedVariables.selectedGuildId])
    -- PR:ApplyFilterQuest()
end

function PR:RefreshGuildList()
    self.guildComboEntries = {}
    if self.guildComboBox == nil then self.guildComboBox = PR:GetGuildComboBox() end
    self.guildComboBox:ClearItems()
    for i = 1, GetNumGuilds() do
        local guildId = GetGuildId(i)
        if(not self.filterFunction or self.filterFunction(guildId)) then
            local guildName = GetGuildName(guildId)
            local guildAlliance = GetGuildAlliance(guildId) 
            local guildText = zo_iconTextFormat(GetAllianceBannerIcon(guildAlliance), 24, 24, guildName)
            local entry = self.guildComboBox:CreateItemEntry(guildText, self.OnGuildSelectedCallback)
            entry.guildId = guildId
            entry.guildText = guildText
        self.guildComboEntries[guildId] = entry
        self.guildComboBox:AddItem(entry)
        end
    end
  
    if(next(self.guildComboEntries) == nil) then return false end

    return true
end

function PR:RefreshFilterQuestList()
    self.filterQuestComboEntries = {}
    if self.filterQuestComboBox == nil then self.filterQuestComboBox = PR:GetFilterQuestComboBox() end
    self.filterQuestComboBox:ClearItems()
    local nofilter = self.guildComboBox:CreateItemEntry("-- No filter", self.OnFilterQuestSelectedCallback)
    nofilter.categoryId = 1
    self.filterQuestComboEntries[1] = nofilter
    self.filterQuestComboBox:AddItem(nofilter)
    for zoneId, zoneData in pairs(PR.ZONEDATA) do
        local zoneText = zoneData[PR.locale]["zone"]
        local entry = self.guildComboBox:CreateItemEntry(zoneText, self.OnFilterQuestSelectedCallback)
        entry.categoryId = zoneId
        self.filterQuestComboEntries[zoneId] = entry
        self.filterQuestComboBox:AddItem(entry)
    end
  
    if(next(self.guildComboEntries) == nil) then return false end

    return true
end

function PR.RemoveListEntry(self, button)
    local deleteme = nil
    for key, val in pairs(PR.dataItems[PR.savedVariables.selectedGuildId]) do
        if val.fake_uuid == self.fake_uuid then deleteme = key end
    end
    if deleteme ~= nil then
        table.remove(PR.dataItems[PR.savedVariables.selectedGuildId], deleteme)
        PR.scrollList:Update(PR.dataItems[PR.savedVariables.selectedGuildId])
    end
end

function PR.EnableGuildCheck_OnToggle(checkButton, isChecked)
    PR.savedVariables["guildEnabled"][PR.savedVariables.selectedGuildId] = isChecked
end
  
function PR.ToggleMainWindow()
    PR.hidden = not PR.hidden
    PledgeRunnerDialog:SetHidden(PR.hidden)
end
  
function PR.CloseUI()
    PR.hidden = true;
    SCENE_MANAGER:HideTopLevel(PledgeRunnerDialog)
end
  
function PR.ShowUI()
    PR.hidden = false;
    PledgeRunnerDialog:SetHidden(PR.hidden)
end
  
function PR.HideUI()
    PR.hidden = true;
    PledgeRunnerDialog:SetHidden(PR.hidden)
end
  
function PR:OnGuildSelected(entry)
    -- d(entry.guildId, entry.guildText)
    ZO_CheckButton_SetCheckState(PledgeRunnerDialogEnableGuildCheck, self.savedVariables["guildEnabled"][entry.guildId])
    self.savedVariables.selectedGuildId = entry.guildId
    self.scrollList:Update(self.dataItems[self.savedVariables.selectedGuildId])
    PR:ApplyFilterQuest()
    self.guildComboBox:SetSelectedItemText(entry.guildText)
    if(self.selectedCallback) then
        self.selectedCallback(entry.guildId)
    end
end

function PR:OnFilterQuestSelected(entry)
    self.filterQuestCategory = entry.categoryId
    PR:ApplyFilterQuest()
end

function PR:ApplyFilterQuest()
    if self.filterQuestCategory == 1 then
        PR.scrollList:ShowAllCategories()
    else
        PR.scrollList:ShowOnlyCategory(self.filterQuestCategory)
    end
end

function PR:SelectGuildComboBox(guildId)
    if self.guildComboBox == nil then self.guildComboBox = PR:GetGuildComboBox() end
    local entry = self.guildComboEntries[guildId]
    self.guildComboBox:SetSelectedItemText(entry.guildText)
end

-- this loop sets the time display once per second, stop by setting PR.timerStart to nil
function PR.SetTimerTimeLoop(runOnce)
    local time = PR.TimeStringFromTimeStamp(PR.GetTimeElapsed())
    PledgeRunnerDialogTimerTime:SetText(time)
    if runOnce == true then return end
    zo_callLater(function() 
        if PR.timerStart ~= nil then 
            PR.SetTimerTimeLoop() 
        end
    end, 1000)
end

function PR.StartTimer()
    PR.timerStart = GetTimeStamp()
    PR.SetTimerTimeLoop()
end

function PR.StopTimer()
    PR.timerStart = nil
    PledgeRunnerDialogTimerTime:SetText("|c77777700:00:00|r")
end

function PR.GetTimeElapsed()
    if PR.timerStart == nil then return 0 end
    return GetTimeStamp() - PR.timerStart
end

-- ESO_event functions
function PR.OnCombatStateChange(event, inCombat)
    if inCombat == true then
        -- if we are in a pledge zone and the timer has not yet started...
        if PR.currentZoneData ~= nil and PR.timerStart == nil then
            PR.StartTimer()
            PR.CenterAnnounce("The fight begins in <<1>>", PR.currentZoneData[PR.locale]["zone"])
            PR.InjectAddonDataIntoGuildNote(PR.EncodeDataStringWithId(PR.currentZoneData["zone"], PR.ACTION.PLEDGE_ZONE_STARTED, GetTimeStamp()))
        end
    end
end

-- EVENT_ZONE_CHANGED is not triggered at initial entry, but EVENT_PLAYER_ACTIVATED is
function PR.OnPlayerActivated(event)
    local zoneName = GetUnitZone('player')
    local zoneId, worldX, worldY, worldZ = GetUnitWorldPosition('player')
    -- check if the new zone is actually the same as the previous zone, in which case do nothing
    -- this happens in some dungeons that are split into multiple sub zones (Darkshade for example)
    if PR.currentZoneData ~= nil and zoneId == PR.currentZoneData.zone then
        return
    end
    -- CHECK OLD ZONE DATA
    -- before checking for the _new_ zone data, see if we left a zone that had zone data, so we can log that
    if PR.currentZoneData ~= nil then
        PR.InjectAddonDataIntoGuildNote(PR.EncodeDataStringWithId(PR.currentZoneData["zone"], PR.ACTION.PLEDGE_ZONE_LEFT, PR.GetTimeElapsed()))
    end
    -- RENEW ZONE DATA
    -- now renew the currentZoneData with the current zone - if it's not in our PledgeData, it's going to be nil
    PR.currentZoneData = PR.ZONEDATA[zoneId]
    PR.StopTimer()
    if PR.currentZoneData ~= nil then
        PR.CenterAnnounce(zo_strformat("<<1>> entered", zoneName))
        PR.InjectAddonDataIntoGuildNote(PR.EncodeDataStringWithId(zoneId, PR.ACTION.PLEDGE_ZONE_ENTERED, 0))
        PledgeRunnerDialogCurrentZone:SetText(zoneName)
    else
        PledgeRunnerDialogCurrentZone:SetText("|c777777" .. zoneName .. "|r")
    end
end

function PR.OnZoneChanged(event, _, subZoneName, _, _, subZoneId)
    -- using Event Parameters would be way too easy! (since they don't work...)
    local zoneName = GetUnitZone('player')
    local zoneId, worldX, worldY, worldZ = GetUnitWorldPosition('player')
    -- d(zo_strformat("<<1>> entered, zoneId: <<2>>, subZoneName: <<3>>, subZoneId: <<4>>", zoneName, zoneId, subZoneName, subZoneId))
end

function PR.OnQuestAdvanced(event, journalIndex, questName, isPushed, isComplete, mainStepChanged)
    local questNameJournal, backgroundText, activeStepText, activeStepType, activeStepTrackerOverrideText, completed, tracked, questLevel, pushed, questType, instanceDisplayType = GetJournalQuestInfo(journalIndex)
    local conditionText, _, _, isFailCondition, isComplete, _, _, conditionType = GetJournalQuestConditionInfo(journalIndex)
    -- d(zo_strformat("<<1>>,<<2>>,isPushed <<3>>,isComplete <<4>>,mainStepChanged <<5>>", journalIndex, questName, isPushed, isComplete, mainStepChanged))
    -- d(questNameJournal, backgroundText, activeStepText, activeStepType, activeStepTrackerOverrideText, completed, tracked, questLevel, pushed, questType, instanceDisplayType)
    -- d(zo_strformat("<<1>>,<<2>>", questName, activeStepTrackerOverrideText))
    -- d(conditionText)
    if PR.currentZoneData ~= nil then
        d(PR.currentZoneData[PR.locale]["pledge"])
        if questName == PR.currentZoneData[PR.locale]["pledge"] and conditionText == PR.currentZoneData[PR.locale]["final"] then
            -- d("FINAL STEP REACHED")
            PR.InjectAddonDataIntoGuildNote(PR.EncodeDataStringWithId(PR.currentZoneData["zone"], PR.ACTION.PLEDGE_FINAL_REACHED, PR.GetTimeElapsed()))
        end
    end
  end


function PR.CenterAnnounce(text, category, sound, duration)
  if text == nil then return end
  if category == nil then category = CSA_CATEGORY_SMALL_TEXT end
  if sound == nil then sound = SOUNDS.QUEST_OBJECTIVE_INCREMENT end
  local message = CENTER_SCREEN_ANNOUNCE:CreateMessageParams(category, sound)
  if duration ~= nil then message:SetLifespanMS(duration) end
  -- message:SetSound(SOUNDS.QUEST_OBJECTIVE_INCREMENT)
  message:SetText(zo_strformat("<<1>>: <<2>>", PR.name, text))
  message:MarkSuppressIconFrame()
  message:MarkShowImmediately()
  CENTER_SCREEN_ANNOUNCE:QueueMessage(message)
end

function PR.GuildMemberNoteChanged(event, guildId, displayName, note)
    if PR.savedVariables["guildEnabled"][guildId] == false then return end
    local guildMemberId = GetGuildMemberIndexFromDisplayName(guildId, displayName)
    local addonData, noteWithoutData = PR.ExtractAddonDataFromGuildNote(note)
    if addonData ~= nil then
      for k, val in pairs(addonData) do
        PR.AddRow(val, displayName)
      end
    end
  end
  
  function PR.AddRow(dataString, playerName)
    local data = PR.DecodeDataString(dataString, playerName)
    if data == nil then return end
    local doInsert = true
    for k, v in pairs(PR.dataItems[PR.savedVariables.selectedGuildId]) do
        if v.name == data.name and v.zone == data.zone and v.message == data.message then 
            v.time = data.time
            doInsert = false
        elseif v.name == data.name and v.zone == data.zone then
            if v.action == PR.ACTION.PLEDGE_FINAL_REACHED then
                doInsert = true 
            elseif v.action == PR.ACTION.PLEDGE_ZONE_ENTERED or v.action == PR.ACTION.PLEDGE_ZONE_STARTED then
                v.time = data.time
                v.message = data.message
                v.action = data.action
                doInsert = false
            end
        end
    end
    if doInsert == true then table.insert(PR.dataItems[PR.savedVariables.selectedGuildId], data) end
    PR.scrollList:Update(PR.dataItems[PR.savedVariables.selectedGuildId])
    PR:ApplyFilterQuest()
    if PR.savedVariables["guildEnabled"][PR.savedVariables.selectedGuildId] == true then
      local s = zo_strformat("PledgeRunner: <<1>> - <<2>> - <<3>> - <<4>>", data.time, data.name, data.zone, data.message)
      CHAT_SYSTEM:AddMessage(s)
    end
end
  
function PR.EncodeDataStringWithName(zoneName, action, parameter)
    local zoneData = PR.GetZoneDataByName(zoneName)
    if zoneData == nil then
      d("No Zone Data found")
      return nil
    end
    return zo_strformat("<<1>>##<<2>>##<<3>>", zoneData["zone"], action, parameter)
end
  
function PR.EncodeDataStringWithId(zoneId, action, parameter)
    return zo_strformat("<<1>>##<<2>>##<<3>>", zoneId, action, parameter)
end
  
function PR.DecodeDataString(dataString, playerName)
    if dataString == nil then return end
    local data = PR.strSplit("##", dataString)
    if data == nil or #data < 3 then return end
    -- d("AddRow", dataString)
    local zoneId = tonumber(data[1])
    local action = tonumber(data[2])
    local parameter = tonumber(data[3])
    if zoneId == nil then return end
    if action == nil then return end
    local zoneName = PR.ZONEDATA[zoneId][PR.locale]["zone"]
    if zoneName == nil then zoneName = data[1] end
    local msg = ""
    if     action==PR.ACTION.PLEDGE_ZONE_ENTERED then 
        msg = GetString(PLEDGERUNNER_PLEDGE_ZONE_ENTERED)
    elseif action==PR.ACTION.PLEDGE_ZONE_STARTED then 
        msg = zo_strformat("|c96C05F<<1>>|r", GetString(PLEDGERUNNER_PLEDGE_ZONE_STARTED))
    elseif action==PR.ACTION.PLEDGE_FINAL_REACHED then 
        msg = zo_strformat("|cD2B568<<1>> <<2>>|r", GetString(PLEDGERUNNER_PLEDGE_FINAL_REACHED), PR.TimeStringFromTimeStamp(parameter))
    elseif action==PR.ACTION.PLEDGE_ZONE_LEFT then
        msg = zo_strformat("|cD26868<<1>> <<2>>|r", GetString(PLEDGERUNNER_PLEDGE_ZONE_LEFT), PR.TimeStringFromTimeStamp(parameter))
    end
    local fake_uuid = zo_strformat("<<1>><<2>><<3>><<4>>", zoneId,playerName,action,msg)
    return {time=PR.GetDateAndTimeString(), zone=zoneName, message=msg, name=playerName, action=action, categoryId=zoneId, fake_uuid=fake_uuid}
end
  
-- Do not call this too often, as it is a rate-limited function - calling it too often per minute will kick the player
function PR.SetOwnMemberNote(guildId, note)
    local displayName = GetDisplayName()
    local guildMemberId = GetGuildMemberIndexFromDisplayName(guildId, displayName)
    if PR.writeGuildNoteDelay == 0 then
        SetGuildMemberNote(guildId, guildMemberId, note)
        PR.writeGuildNoteDelay = PR.writeGuildNoteDelay + PR.writeGuildNoteDelayAdd
        zo_callLater(function() 
                PR.writeGuildNoteDelay = PR.writeGuildNoteDelay - PR.writeGuildNoteDelayAdd
            end, PR.writeGuildNoteDelay)
    else
        PR.writeGuildNoteDelay = PR.writeGuildNoteDelay + PR.writeGuildNoteDelayAdd
        zo_callLater(function() 
                SetGuildMemberNote(guildId, guildMemberId, note)
                PR.writeGuildNoteDelay = PR.writeGuildNoteDelay - PR.writeGuildNoteDelayAdd
            end, PR.writeGuildNoteDelay)
    end
end
  
function PR.GetOwnMemberNote(guildId)
    local displayName = GetDisplayName()
    local guildMemberId = GetGuildMemberIndexFromDisplayName(guildId, displayName)
    local name, note, rankIndex, playerStatus, secsSinceLogoff = GetGuildMemberInfo(guildId, guildMemberId)
    return note
end
  
  function PR.ExtractAddonDataFromGuildNote(param)
    local note
    if type(param) == "number" then note = PR.GetOwnMemberNote(param)
    elseif type(param) == "string" then note = param
    else return nil, param
    end

    -- looking for first and last occurrence of the addon pattern
    local osFirst, _ = note:find(PR.dataBoundaryPattern)
    local osLast, _ = note:reverse():find(PR.dataBoundaryPattern:reverse())
    if (osFirst ~= nil) and (osLast ~= nil) then
      osLast = #note - osLast + 2
      -- cut out the entire addon string, then remove the patterns to get the "pure" data
      local addonData = note:sub(osFirst, osLast):gsub(PR.dataBoundaryPattern, "")
      -- if we have data, return the data string and the original note without the datastring
      if addonData ~= nil then
        local noteWithoutData = note:sub(1, osFirst-1) .. note:sub(osLast, #note)
        local datastrings = PR.strSplit(",",addonData)
        return datastrings, noteWithoutData
      end
    end
    return nil, note
  end
  
function PR.InjectAddonDataIntoGuildNote(dataString)
    for i=1,GetNumGuilds()+1,1 do
        if DoesPlayerHaveGuildPermission(i, GUILD_PERMISSION_NOTE_EDIT) == true then
            if PR.savedVariables["guildEnabled"][i] == true then
                local addonData, noteWithoutData = PR.ExtractAddonDataFromGuildNote(i)
                local newNote = noteWithoutData .. PR.dataBoundaryPattern .. dataString .. PR.dataBoundaryPattern
                PR.SetOwnMemberNote(i, newNote)
            end
        end
    end
end

-- function PR.TestButton_Clicked()
--     PR.StartTimer()
--     PR.InjectAddonDataIntoGuildNote(PR.EncodeDataStringWithId(1052, PR.ACTION.PLEDGE_FINAL_REACHED, GetTimeStamp()))
--     PR.InjectAddonDataIntoGuildNote(PR.EncodeDataStringWithId(1055, PR.ACTION.PLEDGE_ZONE_ENTERED, GetTimeStamp()))
--     PR.InjectAddonDataIntoGuildNote(PR.EncodeDataStringWithId(380, PR.ACTION.PLEDGE_ZONE_ENTERED, GetTimeStamp()))
-- end

function PR.ResetButton_Clicked()
    PR.ClearDataItems(PR.savedVariables.selectedGuildId)
    PR.scrollList:Update(PR.dataItems[PR.savedVariables.selectedGuildId])
end

-- A bunch of generic utility functions

function PR.strSplit(delim,str)
    local t = {}
    for substr in string.gmatch(str, "[^".. delim.. "]*") do
        if substr ~= nil and string.len(substr) > 0 then
            table.insert(t,substr)
        end
    end
    return t
end

function PR.starts_with(str, start)
    return str:sub(1, #start) == start
end

function PR.ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

function PR.GetDateAndTimeString()
    return zo_strformat("<<1>> <<2>>", GetDateStringFromTimestamp(GetTimeStamp()), GetTimeString())
end

function PR.GetTimeFromTimeStamp(ts)
    if ts == nil then return 0,0,0 end
    local h = math.floor(ts / 3600 % 24)
    local m = math.floor(ts / 60 % 60) 
    local s = math.floor(ts % 60)
    return h, m, s
end

function PR.TimeStringFromTimeStamp(ts)
    local hours, minutes, seconds = PR.GetTimeFromTimeStamp(ts)
    return zo_strformat("<<1>>:<<2>>:<<3>>", string.format("%02d",hours), string.format("%02d",minutes), string.format("%02d",seconds))
end

function PR.GetDateAndTimeStringFromTimeStamp(ts)
    local hours, minutes, seconds = PR.GetTimeFromTimeStamp(ts)
    local dateString = GetDateStringFromTimestamp(ts)
    return zo_strformat("<<1>> <<2>>:<<3>>:<<4>>", dateString, string.format("%02d",hours), string.format("%02d",minutes), string.format("%02d",seconds))
end