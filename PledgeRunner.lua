PledgeRunner = PledgeRunner or {}
local PR = PledgeRunner

-- set up some global vars
PR.name = "PledgeRunner"
PR.defaults = {
    selectedGuildId = 1,
    left = 100,
    top = 100,
    width = 500,
    height = 500,
    guildEnabledSend = {false,false,false,false,false},
    guildEnabledReceive = {false,false,false,false,false},
    guildEnabledChatNotify = {false,false,false,false,false}
}

-- set up enums
PR.EVENTS = {
    UNDEFINED = 99999999,
    COMBAT_STATE_ENTERED = 1,
    COMBAT_STATE_LEFT = 2,
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
    
    self.savedVariables = ZO_SavedVars:NewAccountWide("PledgeRunnerSavedVariables", 1, nil, PR.defaults)

    if GetDisplayName() == "@flipswitchingmonkey" then
      SLASH_COMMANDS["/rr"] = function(cmd) ReloadUI() end
    end 
    SLASH_COMMANDS["/pledgerunner"] = function(cmd) PR.ShowUI() end

    -- REGISTER EVENTS
    -- EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_GUILD_MEMBER_NOTE_CHANGED, Oversharer.GuildMemberNoteChanged)
    -- EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_QUEST_ADDED, Oversharer.OnQuestAdded)
    -- EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_QUEST_COMPLETE, Oversharer.OnQuestComplete)
    -- EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_QUEST_REMOVED, Oversharer.OnQuestRemoved)
    -- EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_QUEST_ADVANCED, Oversharer.OnQuestAdvanced)
    -- EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_EXPERIENCE_GAIN, Oversharer.OnExperienceGain)
    EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_PLAYER_COMBAT_STATE, PR.OnCombatStateChange)
    -- EVENT_MANAGER:RegisterForEvent(PR.name, EVENT_BOSSES_CHANGED, Oversharer.OnBossesChanged)
    
    -- EVENT_MANAGER:RegisterForEvent(Oversharer.name, EVENT_COMBAT_EVENT, Oversharer.OnCombatEvent)
    
    -- INIT MAINWINDOWS CONTROLS
    Oversharer:initWindow()
end

-- ESO_event functions
function PR.OnCombatStateChange(event, inCombat)
    if inCombat then
        PR:SetLastEvent(PR.EVENTS.COMBAT_STATE_ENTERED)
    else
        PR:SetLastEvent(PR.EVENTS.COMBAT_STATE_LEFT)
    end
  end

