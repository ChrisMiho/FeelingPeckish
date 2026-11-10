local addonName, ns = ...

-- WoW glue: events, the reminder timer, /peckish and FeelingPeckishDB.
-- Decisions live in Core.lua and phrases in Phrases.lua; this file only
-- reads game state, calls them and prints. See PRD.md section 3.

local Core = ns.Core
local pickPhrase = ns.Phrases.newPicker()

local BUFF_NAME = "Well Fed" -- English clients only (PRD section 3.1)
local PREFIX = "|cffffa500FeelingPeckish:|r "
local REMINDER_PREFIX = "Still peckish: "

local tracker = Core.newTracker()
local reminder -- pending C_Timer handle, or nil
local series -- the running reminder series (Core.newSeries), or nil

local function print(text)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
end

-- The normalised FeelingPeckishDB; a fresh defaults table before ADDON_LOADED.
function ns.getSettings()
	if type(FeelingPeckishDB) == "table" then
		return FeelingPeckishDB
	end
	return Core.normalizeSettings({})
end

local function isEnabled()
	return ns.getSettings().enabled
end

local function addonVersion()
	local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = getMetadata and getMetadata(addonName, "Version")
	if version and version ~= "" then
		return " " .. version
	end
	return ""
end

local function loadedMessage()
	return Core.loadedMessage(addonVersion(), isEnabled())
end

-- True or false, or nil when the client will not tell us (an aura name that
-- is a hidden "secret" value, or no aura API at all).
local function hasWellFed()
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local i = 1
		while true do
			local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
			if not aura then
				return false
			end
			if issecretvalue and issecretvalue(aura.name) then
				return nil
			end
			if aura.name == BUFF_NAME then
				return true
			end
			i = i + 1
		end
	end
	if not UnitBuff then
		return nil
	end
	for i = 1, 40 do
		local name = UnitBuff("player", i)
		if not name then
			return false
		end
		if name == BUFF_NAME then
			return true
		end
	end
	return false
end

local function context()
	return {
		hasBuff = hasWellFed(),
		dead = UnitIsDeadOrGhost("player") and true or false,
		resting = IsResting() and true or false,
	}
end

local function cancelSeries()
	if reminder then
		reminder:Cancel()
		reminder = nil
	end
	series = nil
end

local scheduleReminder

local function onReminderDue()
	reminder = nil
	if not series then
		return
	end
	local result = Core.reminderDue(series, context(), ns.getSettings())
	if result.print then
		print(REMINDER_PREFIX .. pickPhrase())
	end
	if result.again then
		scheduleReminder()
	else
		series = nil
	end
end

function scheduleReminder()
	reminder = C_Timer.NewTimer(ns.getSettings().reminderInterval, onReminderDue)
end

local function armSeries()
	cancelSeries()
	series = Core.newSeries()
	scheduleReminder()
end

-- Copy every setting from a draft into FeelingPeckishDB. A pending reminder
-- keeps its timer; later reminders read the new settings.
function ns.applySettings(draft)
	local db = ns.getSettings()
	for key in pairs(Core.DEFAULTS) do
		db[key] = draft[key]
	end
	Core.normalizeSettings(db)
	if not Core.keepsSeries(db) then
		cancelSeries()
	end
end

local auraCheckQueued = false

local function checkAuras()
	auraCheckQueued = false
	local result = Core.onAuraChange(tracker, context(), ns.getSettings())
	if result.cancel then
		cancelSeries()
	end
	if result.arm then
		armSeries()
	end
	if result.announce then
		print(pickPhrase())
	end
end

-- Decide one frame after the aura change, so that on death the dead state
-- has settled before we check it, and a burst of UNIT_AURA events is
-- handled once.
local function onAuraChange()
	if not auraCheckQueued then
		auraCheckQueued = true
		C_Timer.After(0, checkAuras)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			FeelingPeckishDB = Core.normalizeSettings(FeelingPeckishDB)
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		-- Once per login or /reload, not on every loading screen.
		print(loadedMessage())
	elseif event == "PLAYER_LEAVING_WORLD" then
		-- Loading screen: forget the state so it can't look like a falloff.
		Core.reset(tracker)
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Login, /reload and zoning only set the baseline; never a falloff.
		Core.baseline(tracker, hasWellFed())
	elseif event == "UNIT_AURA" then
		onAuraChange()
	end
end)

SLASH_FEELINGPECKISH1 = "/peckish"
SlashCmdList.FEELINGPECKISH = function(msg)
	local command = Core.parseCommand(msg)
	if command == "open" then
		if ns.Options then
			ns.Options.Toggle()
		end
	elseif command == "on" or command == "off" then
		local enabled = command == "on"
		ns.getSettings().enabled = enabled
		if enabled then
			print("on. Snack alerts armed.")
		else
			cancelSeries()
			print("off. Starve in peace.")
		end
		if ns.Options then
			ns.Options.SyncEnabled(enabled)
		end
	else
		print((isEnabled() and "on" or "off") .. ". Usage: /peckish opens settings, /peckish on, /peckish off")
	end
end
