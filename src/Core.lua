local _, ns = ...

-- Pure decisions: settings rules, when to announce a falloff, when to arm or
-- cancel the reminder series, and how to read /peckish arguments. No WoW API,
-- so everything here is unit tested. See PRD.md section 3.

local Core = {}
ns.Core = Core

-- Callers must not mutate this table.
Core.DEFAULTS = {
	enabled = true,
	quietWhenDead = true,
	quietWhenResting = true,
	remindersOn = true,
	reminderInterval = 60, -- seconds between reminders
	reminderCount = 1,
	remindUntilFed = false,
}

-- Range and step for each numeric setting.
local NUMBER_SPECS = {
	reminderInterval = { min = 30, max = 600, step = 30 },
	reminderCount = { min = 1, max = 10, step = 1 },
}

-- Fix every key of DEFAULTS in place (db may be nil or junk) and return the
-- table. Unknown keys are left alone.
function Core.normalizeSettings(db)
	if type(db) ~= "table" then
		db = {}
	end
	for key, default in pairs(Core.DEFAULTS) do
		local spec = NUMBER_SPECS[key]
		local value = db[key]
		if spec then
			if type(value) ~= "number" or value ~= value then
				value = default
			else
				value = math.max(spec.min, math.min(spec.max, value))
				value = math.floor(value / spec.step + 0.5) * spec.step
			end
		elseif type(value) ~= "boolean" then
			value = default
		end
		db[key] = value
	end
	return db
end

-- A tracker remembers whether the player had Well Fed at the last check.
-- hadBuff is nil until the first observation, which only sets the baseline.
function Core.newTracker()
	return { hadBuff = nil }
end

-- Record the current state without deciding anything (login, /reload,
-- zoning), so those never count as a falloff.
function Core.baseline(tracker, hasBuff)
	tracker.hadBuff = hasBuff and true or false
end

-- Forget the last state (leaving the world for a loading screen). The next
-- observation only sets a new baseline, so a loading screen that briefly
-- reports no auras can never count as a falloff.
function Core.reset(tracker)
	tracker.hadBuff = nil
end

-- True when a message may be printed right now.
-- state: { dead, resting }
function Core.canSpeak(state, settings)
	return settings.enabled
		and not (state.dead and settings.quietWhenDead)
		and not (state.resting and settings.quietWhenResting)
end

-- True when a reminder series should stay alive.
function Core.keepsSeries(settings)
	return settings.enabled and settings.remindersOn
end

-- Called whenever the player's auras change.
-- state: { hasBuff, dead, resting }
-- Returns { announce = bool, arm = bool, cancel = bool }:
--   announce: print a falloff phrase now
--   arm:      (re)start the reminder series, replacing any pending one
--   cancel:   stop any pending reminder
function Core.onAuraChange(tracker, state, settings)
	local result = { announce = false, arm = false, cancel = false }
	if state.hasBuff == nil then
		-- Buffs could not be read (e.g. hidden in combat): decide nothing.
		return result
	end
	local hasBuff = state.hasBuff and true or false

	if tracker.hadBuff == nil then
		tracker.hadBuff = hasBuff
		return result
	end

	if tracker.hadBuff and not hasBuff then
		-- Falloff. The reminder is armed even when the message itself is
		-- suppressed; it re-checks the conditions when it fires.
		if settings.enabled then
			result.arm = settings.remindersOn and true or false
			result.announce = Core.canSpeak(state, settings) and true or false
		end
	elseif hasBuff and not tracker.hadBuff then
		result.cancel = true
	end

	tracker.hadBuff = hasBuff
	return result
end

-- A reminder series counts how many reminders have come due.
function Core.newSeries()
	return { due = 0 }
end

-- Called when a reminder timer fires.
-- Returns { print = bool, again = bool }: print a reminder now, and schedule
-- another one.
function Core.reminderDue(series, state, settings)
	series.due = series.due + 1
	if state.hasBuff == true or not Core.keepsSeries(settings) then
		return { print = false, again = false }
	end
	return {
		print = state.hasBuff == false and Core.canSpeak(state, settings) and true or false,
		again = settings.remindUntilFed or series.due < settings.reminderCount,
	}
end

-- "30 s", "1 min", "2 min 30 s".
function Core.formatInterval(seconds)
	local minutes = math.floor(seconds / 60)
	local rest = seconds % 60
	if minutes == 0 then
		return rest .. " s"
	elseif rest == 0 then
		return minutes .. " min"
	end
	return minutes .. " min " .. rest .. " s"
end

-- Which reminder controls are enabled for a draft of the settings.
function Core.controlStates(draft)
	return {
		interval = draft.remindersOn,
		count = draft.remindersOn and not draft.remindUntilFed,
		untilFed = draft.remindersOn,
	}
end

-- The line printed once at login. version is "" or " <version>".
function Core.loadedMessage(version, enabled)
	if enabled then
		return "loaded" .. version .. ". Snack alerts are on. /peckish off to mute."
	end
	return "loaded" .. version .. ". Snack alerts are off. /peckish on to arm them."
end

-- Reads a /peckish argument: returns "open", "on", "off" or "status".
function Core.parseCommand(msg)
	local arg = (msg or ""):match("^%s*(.-)%s*$"):lower()
	if arg == "" then
		return "open"
	elseif arg == "on" or arg == "off" then
		return arg
	end
	return "status"
end
