local _, ns = ...

-- Pure buff-state decisions: when to announce a falloff, when to arm or
-- cancel the reminder, and how to read /peckish arguments. No WoW API, so
-- everything here is unit tested. See PRD.md section 3.

local Core = {}
ns.Core = Core

Core.REMINDER_DELAY = 60 -- seconds after a falloff

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
-- ctx: { enabled, dead, resting }
function Core.canSpeak(ctx)
	return ctx.enabled and not ctx.dead and not ctx.resting
end

-- Called whenever the player's auras change.
-- ctx: { hasBuff, enabled, dead, resting }
-- Returns { announce = bool, arm = bool, cancel = bool }:
--   announce: print a falloff phrase now
--   arm:      (re)start the reminder timer, replacing any pending one
--   cancel:   stop any pending reminder
function Core.onAuraChange(tracker, ctx)
	local result = { announce = false, arm = false, cancel = false }
	if ctx.hasBuff == nil then
		-- Buffs could not be read (e.g. hidden in combat): decide nothing.
		return result
	end
	local hasBuff = ctx.hasBuff and true or false

	if tracker.hadBuff == nil then
		tracker.hadBuff = hasBuff
		return result
	end

	if tracker.hadBuff and not hasBuff then
		-- Falloff. The reminder is armed even when the message itself is
		-- suppressed; it re-checks the conditions when it fires.
		if ctx.enabled then
			result.arm = true
			result.announce = Core.canSpeak(ctx)
		end
	elseif hasBuff and not tracker.hadBuff then
		result.cancel = true
	end

	tracker.hadBuff = hasBuff
	return result
end

-- Called when the reminder timer fires. True means print a reminder.
-- ctx: { hasBuff, enabled, dead, resting }
function Core.shouldRemind(ctx)
	return ctx.hasBuff == false and Core.canSpeak(ctx) and true or false
end

-- Reads a /peckish argument: returns "on", "off" or "status".
function Core.parseCommand(msg)
	local arg = (msg or ""):match("^%s*(.-)%s*$"):lower()
	if arg == "on" or arg == "off" then
		return arg
	end
	return "status"
end
