local addonName, ns = ...

-- WoW glue: events, the reminder timer, /peckish and FeelingPeckishDB.
-- Decisions live in Core.lua and phrases in Phrases.lua; this file only
-- reads game state, calls them and prints. See PRD.md section 3.

local Core = ns.Core
local pickPhrase = ns.Phrases.newPicker()

local BUFF_NAME = "Well Fed" -- English clients only (PRD section 3.1)
local PREFIX = "|cffffa500FeelingPeckish:|r "
local REMINDER_PREFIX = "Still peckish: "
local AFTER_COMBAT_PREFIX = "Fight's over, still no Well Fed: "
-- After combat ends, how many times (one second apart) to retry while buffs
-- are still hidden, before waiting for the next aura change instead.
local COMBAT_END_RETRIES = 5

local tracker = Core.newTracker()
local reminder -- pending C_Timer handle, or nil
local series -- the running reminder series (Core.newSeries), or nil
local reminderHeld = false -- a reminder came due while buffs were hidden
local expiryTimer -- C_Timer handle for the check when Well Fed runs out
local combatEndRetries = 0

local function say(text)
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

-- Name and end time of the i-th buff. The name is nil only past the last
-- aura: a nameless aura reads as "" so the scan carries on instead of
-- stopping early and missing Well Fed.
local function readAura(i)
	local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
	if aura then
		return aura.name or "", aura.expirationTime
	end
end

local function readUnitBuff(i)
	local name, _, _, _, _, expires = UnitBuff("player", i)
	return name, expires
end

-- True or false, or nil when the client will not tell us (auras are secret
-- right now, or no aura API at all). Core.findBuff catches the "secret" error
-- that GetAuraDataByIndex raises for addon code; other errors still surface.
local function hasWellFed()
	local read
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		read = readAura
	elseif UnitBuff then
		read = readUnitBuff
	else
		return nil
	end
	return Core.findBuff(read, BUFF_NAME, issecretvalue)
end

-- Then, when it has Well Fed, its end time (GetTime() clock) if known.
local function context()
	local hasBuff, expires = hasWellFed()
	return {
		hasBuff = hasBuff,
		expires = expires,
		now = GetTime(),
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
	reminderHeld = false
end

local scheduleReminder

local function onReminderDue()
	reminder = nil
	if not series then
		return
	end
	local result = Core.reminderDue(series, context(), ns.getSettings())
	if result.hold then
		-- Buffs are hidden (combat): checkAuras runs it once they are readable.
		reminderHeld = true
		return
	end
	if result.print then
		say(REMINDER_PREFIX .. pickPhrase())
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
local onAuraChange

-- Check again just after Well Fed is due to run out, so it is noticed even
-- when buffs are hidden then and no readable UNIT_AURA arrives.
local function refreshExpiryCheck(now)
	if expiryTimer then
		expiryTimer:Cancel()
		expiryTimer = nil
	end
	local delay = Core.expiryCheckDelay(tracker, now)
	if delay then
		expiryTimer = C_Timer.NewTimer(delay, function()
			expiryTimer = nil
			onAuraChange()
		end)
	end
end

local function checkAuras()
	auraCheckQueued = false
	local state = context()
	local result = Core.onAuraChange(tracker, state, ns.getSettings())
	if result.cancel then
		cancelSeries()
	end
	if result.announce then
		say(pickPhrase())
	end
	if result.afterCombat then
		say(AFTER_COMBAT_PREFIX .. pickPhrase())
	end
	if result.arm then
		armSeries()
	end

	if state.hasBuff == nil then
		if combatEndRetries > 0 then
			combatEndRetries = combatEndRetries - 1
			C_Timer.After(1, onAuraChange)
		end
		return
	end
	combatEndRetries = 0
	refreshExpiryCheck(state.now)
	if reminderHeld and series then
		reminderHeld = false
		onReminderDue()
	end
end

-- Decide one frame after the aura change, so that on death the dead state
-- has settled before we check it, and a burst of UNIT_AURA events is
-- handled once.
function onAuraChange()
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
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			FeelingPeckishDB = Core.normalizeSettings(FeelingPeckishDB)
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		-- Once per login or /reload, not on every loading screen.
		say(loadedMessage())
	elseif event == "PLAYER_LEAVING_WORLD" then
		-- Loading screen: forget the state so it can't look like a falloff.
		Core.reset(tracker)
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Login, /reload and zoning only set the baseline; never a falloff.
		local hasBuff, expires = hasWellFed()
		Core.baseline(tracker, hasBuff, expires)
		refreshExpiryCheck(GetTime())
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Combat over: buffs can be read again, so settle anything that
		-- happened while they were hidden.
		combatEndRetries = COMBAT_END_RETRIES
		onAuraChange()
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
			say("on. Snack alerts armed.")
		else
			cancelSeries()
			say("off. Starve in peace.")
		end
		if ns.Options then
			ns.Options.SyncEnabled(enabled)
		end
	else
		say((isEnabled() and "on" or "off") .. ". Usage: /peckish opens settings, /peckish on, /peckish off")
	end
end
