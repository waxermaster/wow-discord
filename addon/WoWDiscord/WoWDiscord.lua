-- Records level ups, turned-in quests, deaths and a character sheet (class, level,
-- professions) as ready-made "wow|..." lines in WoWDiscordDB. WoW writes that
-- file on logout, /reload and exit; the wow-discord script then posts the new
-- lines to the group's #wow-log webhook. Works with any client language.
-- It also takes a screenshot at each level up, which the script posts live.
-- Level-up shots are saved as PNG and the player's own shots as JPEG, so the
-- script can tell them apart and the bot posts them in different channels.
local KEEP = 300 -- lines kept in the file; the script remembers what it already sent

local f = CreateFrame("Frame")
local me, questTitle, current, level

-- String keys, so WoW always writes them out as ["12"] = "wow|...".
local function add(line)
  local db = WoWDiscordDB
  db.log[tostring(db.nextId)] = line
  db.log[tostring(db.nextId - KEEP)] = nil
  db.nextId = db.nextId + 1
end

local function clean(text)
  return (tostring(text or ""):gsub("|", "/"))
end

-- "wow|char|<name>|<CLASS>|<level>|Couture=33;Enchantement=8"
local function sheet()
  local profs = {}
  if GetNumSkillLines then -- classic skill list
    -- Skills under a collapsed header are not listed: open them all first.
    if ExpandSkillHeader then ExpandSkillHeader(0) end
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank = GetSkillLineInfo(i)
      if not isHeader and name and rank then
        profs[#profs + 1] = clean(name) .. "=" .. rank
      end
    end
  elseif GetProfessions then -- newer clients
    for _, index in pairs({ GetProfessions() }) do
      local name, _, rank = GetProfessionInfo(index)
      if name and rank then
        profs[#profs + 1] = clean(name) .. "=" .. rank
      end
    end
  end
  local _, classToken = UnitClass("player")
  level = math.max(level or 0, UnitLevel("player") or 0)
  return ("wow|char|%s|%s|%d|%s"):format(me, classToken or "?", level, table.concat(profs, ";"))
end

-- The game empties the skill list while logging out, so the sheet is read every
-- 10 s during play and the last one is saved at logout.
local sheetTimer = CreateFrame("Frame")
sheetTimer.t = 0
sheetTimer:SetScript("OnUpdate", function(self, elapsed)
  self.t = self.t + elapsed
  if self.t < 10 or not me then return end
  self.t = 0
  local ok, s = pcall(sheet)
  WoWDiscordDB.lastError = not ok and tostring(s) or nil -- kept in the file for debugging
  if ok and (not current or s:sub(-1) ~= "|" or current:sub(-1) == "|") then
    current = s -- never trade a sheet with professions for one without
  end
end)

-- Gold banner shown on screen for the level-up screenshot, so the picture says who and which level.
local banner = UIParent:CreateFontString(nil, "OVERLAY")
banner:SetFont(STANDARD_TEXT_FONT, 40, "THICKOUTLINE")
banner:SetPoint("TOP", 0, -230) -- below the "Objective complete" messages
banner:SetTextColor(1, 0.82, 0)
banner:Hide()

-- Takes the screenshot 1 s after showing the banner, hides it 2 s later.
-- (Own timer: C_Timer is not usable on this client.)
local shotTimer = CreateFrame("Frame")
shotTimer:Hide()
shotTimer:SetScript("OnUpdate", function(self, elapsed)
  self.t = self.t + elapsed
  if not self.shot and self.t >= 1 then
    self.shot = true
    SetCVar("screenshotFormat", "png")
    Screenshot() -- written right away: the script posts it live
  elseif self.t >= 3 then
    SetCVar("screenshotFormat", "jpeg") -- back to normal for the player's own shots
    banner:Hide()
    self:Hide()
  end
end)

local function levelUpShot(level)
  local word = GetLocale() == "frFR" and "Niveau" or "Level"
  banner:SetText(("%s - %s %d !"):format(me, word, level))
  banner:Show()
  shotTimer.t, shotTimer.shot = 0, false
  shotTimer:Show()
end

-- /wowdiscord : test the banner and the live screenshot without leveling up.
-- /wowdiscord update : asks the wow-discord script on this PC to install the latest version
-- (the request reaches it through the saved file, hence the /reload).
SLASH_WOWDISCORD1 = "/wowdiscord"
SlashCmdList.WOWDISCORD = function(arg)
  if not me then return end
  if strtrim(arg or ""):lower() == "update" then
    add("wow|update")
    WoWDiscordDB.updateAsked = true -- message shown after the reload
    ReloadUI()
  else
    levelUpShot(UnitLevel("player"))
  end
end

-- /screen : a normal screenshot (JPEG, posted in #wow), like the Print Screen key.
-- Taken 0.5 s later, once the chat box is closed.
local screenTimer = CreateFrame("Frame")
screenTimer:Hide()
screenTimer:SetScript("OnUpdate", function(self, elapsed)
  self.t = self.t + elapsed
  if self.t >= 0.5 then
    self:Hide()
    Screenshot()
  end
end)
SLASH_WOWDISCORDSCREEN1 = "/screen"
SlashCmdList.WOWDISCORDSCREEN = function()
  screenTimer.t = 0
  screenTimer:Show()
end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_DEAD")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    WoWDiscordDB = WoWDiscordDB or {}
    if WoWDiscordDB.lines then -- first test version used number keys
      WoWDiscordDB.lines, WoWDiscordDB.sheets = nil, nil
    end
    WoWDiscordDB.log = WoWDiscordDB.log or {}
    WoWDiscordDB.nextId = WoWDiscordDB.nextId or 1
    WoWDiscordDB.sheets = WoWDiscordDB.sheets or {}
    SetCVar("screenshotFormat", "jpeg") -- PNG is reserved for level-up shots
    -- GetUnitName gives the full "Name Surname" on WoW: Forever; UnitName only the first name.
    me = clean(GetUnitName and GetUnitName("player", true) or UnitName("player"))
    local getMeta = GetAddOnMetadata or (C_AddOns and C_AddOns.GetAddOnMetadata)
    local version = getMeta and getMeta("WoWDiscord", "Version")
    if WoWDiscordDB.updateAsked then
      WoWDiscordDB.updateAsked = nil
      print("|cffffd100WoW Discord|r " .. (version or "") .. " : recherche de mise à jour. S'il y en a une, refais /reload dans 1 minute pour la charger.")
    elseif version and WoWDiscordDB.version ~= version then
      print("|cffffd100WoW Discord|r version " .. version .. " chargée.")
    end
    WoWDiscordDB.version = version
  elseif not me then
    return
  elseif event == "PLAYER_LEVEL_UP" then
    level = arg1
    add(("wow|levelup|%s|%d"):format(me, arg1))
    levelUpShot(arg1)
  elseif event == "PLAYER_DEAD" then
    add(("wow|death|%s"):format(me))
  elseif event == "QUEST_COMPLETE" then
    questTitle = GetTitleText()
  elseif event == "QUEST_TURNED_IN" then
    local title = questTitle
    if (not title or title == "") and C_QuestLog and C_QuestLog.GetQuestInfo then
      title = C_QuestLog.GetQuestInfo(arg1)
    end
    add(("wow|quest|%s|%s"):format(me, clean(title or ("#" .. arg1))))
    questTitle = nil
  elseif event == "PLAYER_LOGOUT" then
    -- Also fires on /reload: send the sheet only when something changed.
    if current and WoWDiscordDB.sheets[me] ~= current then
      WoWDiscordDB.sheets[me] = current
      add(current)
    end
  end
end)
