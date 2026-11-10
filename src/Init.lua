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

local function print(text)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
end

local function isEnabled()
	return FeelingPeckishDB == nil or FeelingPeckishDB.enabled ~= false
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
		enabled = isEnabled(),
		dead = UnitIsDeadOrGhost("player") and true or false,
		resting = IsResting() and true or false,
	}
end

local function cancelReminder()
	if reminder then
		reminder:Cancel()
		reminder = nil
	end
end

local function armReminder()
	cancelReminder()
	reminder = C_Timer.NewTimer(Core.REMINDER_DELAY, function()
		reminder = nil
		if Core.shouldRemind(context()) then
			print(REMINDER_PREFIX .. pickPhrase())
		end
	end)
end

local auraCheckQueued = false

local function checkAuras()
	auraCheckQueued = false
	local result = Core.onAuraChange(tracker, context())
	if result.cancel then
		cancelReminder()
	end
	if result.arm then
		armReminder()
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
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			if type(FeelingPeckishDB) ~= "table" then
				FeelingPeckishDB = {}
			end
			if type(FeelingPeckishDB.enabled) ~= "boolean" then
				FeelingPeckishDB.enabled = true
			end
			self:UnregisterEvent("ADDON_LOADED")
		end
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
	if command == "on" then
		FeelingPeckishDB.enabled = true
		print("on. Snack alerts armed.")
	elseif command == "off" then
		FeelingPeckishDB.enabled = false
		cancelReminder()
		print("off. Starve in peace.")
	else
		print((isEnabled() and "on" or "off") .. ". Usage: /peckish on, /peckish off")
	end
end
