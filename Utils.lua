-- A bunch of generic utility functions

local function strSplit(delim,str)
  local t = {}
  for substr in string.gmatch(str, "[^".. delim.. "]*") do
    if substr ~= nil and string.len(substr) > 0 then
      table.insert(t,substr)
    end
  end
  return t
end

local function starts_with(str, start)
  return str:sub(1, #start) == start
end

local function ends_with(str, ending)
  return ending == "" or str:sub(-#ending) == ending
end

local function GetDateAndTimeString()
  return zo_strformat("<<1>> <<2>>", GetDateStringFromTimestamp(GetTimeStamp()), GetTimeString())
end

local function GetTimeFromTimeStamp(ts)
  local h = ts / 3600 % 24;
  local m = ts / 60 % 60; 
  local s = ts % 60;
  return h, m, s
end

local function GetDateAndTimeStringFromTimeStamp(ts)
  local hours, minutes, seconds = GetTimeFromTimeStamp(ts)
  local dateString = GetDateAndTimeStringFromTimeStamp(ts)
  return zo_strformat("<<1>> <<2>>:<<3>>:<<4>>", dateString, string.format("%02d",hours), string.format("%02d",minutes), string.format("%02d",seconds))
end

-- CSA_CATEGORY_SMALL_TEXT = 1
-- CSA_CATEGORY_LARGE_TEXT = 2
-- CSA_CATEGORY_NO_TEXT = 3
-- CSA_CATEGORY_RAID_COMPLETE_TEXT = 4
-- CSA_CATEGORY_MAJOR_TEXT = 5
-- CSA_CATEGORY_COUNTDOWN_TEXT = 6
-- Reset()
-- SetSound(sound)
-- GetSound()
-- SetText(mainText, secondaryText)
-- GetMainText()
-- GetSecondaryText()
-- SetIconData(icon, iconBg)
-- GetIconData()
-- SetExpiringCallback(callback)
-- GetExpiringCallback()
-- SetBarParams(barParams)
-- GetBarParams()
-- SetLifespanMS(lifespanMS)
-- GetLifespanMS()
-- MarkSuppressIconFrame()
-- GetSuppressIconFrame()
-- MarkQueueImmediately(reinsertStompedMessage)
-- GetQueueImmediately()
-- MarkShowImmediately()
-- GetShowImmediately()
-- GetMostUniqueMessage()
-- SetCategory(category)
-- GetCategory()
-- SetObjectPoolKey(key)
-- SetCSAType(csaType)
-- GetCSAType()
-- SetPriority(priority)
-- GetPriority()
-- SetQueuedOrder(queuedOrder)
-- GetQueuedOrder()
-- SetEndOfRaidData(endOfRaidData)
-- GetEndOfRaidData()
-- CallExpiringCallback()
-- PlaySound()

local function CenterAnnounce(text, category, sound, duration)
  if text == nil then return end
  if category == nil then category = CSA_CATEGORY_SMALL_TEXT end
  if sound == nil then sound = SOUNDS.QUEST_OBJECTIVE_INCREMENT end
  local message = CENTER_SCREEN_ANNOUNCE:CreateMessageParams(category, sound)
  if duration ~= nil then message:SetLifespanMS(duration) end
  -- message:SetSound(SOUNDS.QUEST_OBJECTIVE_INCREMENT)
  message:SetText(text)
  message:MarkSuppressIconFrame()
  message:MarkShowImmediately()
  CENTER_SCREEN_ANNOUNCE:QueueMessage(message)
end