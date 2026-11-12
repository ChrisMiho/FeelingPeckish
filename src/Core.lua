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

-- Range and step for each numeric setting. The settings window builds its
-- sliders from these. Callers must not mutate this table.
Core.NUMBER_SPECS = {
	reminderInterval = { min = 30, max = 600, step = 30 },
	reminderCount = { min = 1, max = 10, step = 1 },
}

-- Clamp value into spec's range and round it to the nearest step counted
-- from spec.min, never above spec.max.
function Core.snap(spec, value)
	value = math.max(spec.min, math.min(spec.max, value))
	local steps = math.floor((value - spec.min) / spec.step + 0.5)
	steps = math.min(steps, math.floor((spec.max - spec.min) / spec.step))
	return spec.min + steps * spec.step
end

-- Fix every key of DEFAULTS in place (db may be nil or junk) and return the
-- table. Unknown keys are left alone.
function Core.normalizeSettings(db)
	if type(db) ~= "table" then
		db = {}
	end
	for key, default in pairs(Core.DEFAULTS) do
		local spec = Core.NUMBER_SPECS[key]
		local value = db[key]
		if spec then
			if type(value) ~= "number" or value ~= value then
				value = default
			else
				value = Core.snap(spec, value)
			end
		elseif type(value) ~= "boolean" then
			value = default
		end
		db[key] = value
	end
	return db
end

-- A tracker remembers what the last readable check saw:
--   hadBuff: had Well Fed; nil until the first observation (baseline only)
--   expires: when that Well Fed runs out (GetTime() clock), nil if unknown
--   overdue: Well Fed ran out while buffs were hidden (combat) and the
--            "fight's over" message and reminder series are still owed
function Core.newTracker()
	return { hadBuff = nil, expires = nil, overdue = false }
end

-- Record the current state without deciding anything (login, /reload,
-- zoning), so those never count as a falloff. hasBuff nil (unreadable) stays
-- unknown, so the next readable observation sets the baseline.
function Core.baseline(tracker, hasBuff, expires)
	if hasBuff == nil then
		tracker.hadBuff = nil
	else
		tracker.hadBuff = hasBuff and true or false
	end
	tracker.expires = tracker.hadBuff and expires or nil
	tracker.overdue = false
end

-- Forget the last state (leaving the world for a loading screen). The next
-- observation only sets a new baseline, so a loading screen that briefly
-- reports no auras can never count as a falloff.
function Core.reset(tracker)
	tracker.hadBuff = nil
	tracker.expires = nil
	tracker.overdue = false
end

-- Seconds past the end time before the expiry check runs, so it never runs
-- a moment too early.
Core.EXPIRY_MARGIN = 0.5

-- How long until the addon should check again because Well Fed is due to
-- run out (so it notices even while buffs are hidden), or nil for no check.
function Core.expiryCheckDelay(tracker, now)
	if tracker.hadBuff and tracker.expires then
		return math.max(0, tracker.expires - now) + Core.EXPIRY_MARGIN
	end
	return nil
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

-- Most auras findBuff reads before giving up (a unit has far fewer), so an
-- aura API that never reports the end cannot loop forever.
Core.MAX_AURAS = 255

-- Look for the aura named wanted. readAura(i) returns the i-th aura's name
-- (nil past the last aura) and, optionally, its end time. Returns found, then
-- the end time when found and known (0 = never ends, or secret, gives nil).
-- found is true, false, or nil when the client will
-- not tell us: readName raised the "secret" error (newer clients refuse aura
-- reads from addon code while auras are secret, e.g. in combat), a name is
-- secret, or MAX_AURAS reads found no end. Any other error is raised again,
-- so a real bug is not silently swallowed. isSecret (optional) is checked
-- before comparing, since secrets can't be compared.
function Core.findBuff(readAura, wanted, isSecret)
	for i = 1, Core.MAX_AURAS do
		local ok, name, expires = pcall(readAura, i)
		if not ok then
			if type(name) == "string" and name:find("secret", 1, true) then
				return nil
			end
			error(name, 0)
		end
		if name == nil then
			return false
		end
		if isSecret and isSecret(name) then
			return nil
		end
		if name == wanted then
			if type(expires) ~= "number" or (isSecret and isSecret(expires)) or expires <= 0 then
				expires = nil
			end
			return true, expires
		end
	end
	return nil
end

-- Called whenever the player's auras change, when Well Fed is due to run
-- out, and when combat ends.
-- state: { hasBuff, expires, now, dead, resting }
-- Returns { announce = bool, arm = bool, cancel = bool, afterCombat = bool }:
--   announce:    print a falloff phrase now
--   arm:         (re)start the reminder series, replacing any pending one
--   cancel:      stop any pending reminder
--   afterCombat: print the "fight's over" message now
function Core.onAuraChange(tracker, state, settings)
	local result = { announce = false, arm = false, cancel = false, afterCombat = false }
	if state.hasBuff == nil then
		-- Buffs could not be read (e.g. hidden in combat). Food can't be eaten
		-- in combat, so once the known end time has passed, Well Fed is gone.
		if tracker.hadBuff and tracker.expires and state.now and state.now >= tracker.expires then
			tracker.hadBuff = false
			tracker.expires = nil
			tracker.overdue = settings.enabled and true or false
			result.announce = Core.canSpeak(state, settings) and true or false
		end
		return result
	end
	local hasBuff = state.hasBuff and true or false
	local hadBuff, overdue = tracker.hadBuff, tracker.overdue
	tracker.hadBuff = hasBuff
	tracker.expires = hasBuff and state.expires or nil
	tracker.overdue = false

	if overdue then
		-- First readable check after Well Fed ran out in combat.
		if not hasBuff and Core.keepsSeries(settings) then
			result.arm = true
			result.afterCombat = Core.canSpeak(state, settings) and true or false
		end
		return result
	end

	if hadBuff == nil then
		return result
	end

	if hadBuff and not hasBuff then
		-- Falloff. The reminder is armed even when the message itself is
		-- suppressed; it re-checks the conditions when it fires.
		if settings.enabled then
			result.arm = settings.remindersOn and true or false
			result.announce = Core.canSpeak(state, settings) and true or false
		end
	elseif hasBuff and not hadBuff then
		result.cancel = true
	end
	return result
end

-- A reminder series counts how many reminders have come due.
function Core.newSeries()
	return { due = 0 }
end

-- Called when a reminder timer fires.
-- Returns { print = bool, again = bool }: print a reminder now, and schedule
-- another one. While buffs cannot be read (combat) it returns
-- { print = false, again = false, hold = true } without counting: call it
-- again once they can be read.
function Core.reminderDue(series, state, settings)
	if state.hasBuff == true or not Core.keepsSeries(settings) then
		return { print = false, again = false }
	end
	if state.hasBuff == nil then
		return { print = false, again = false, hold = true }
	end
	series.due = series.due + 1
	return {
		print = Core.canSpeak(state, settings) and true or false,
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
