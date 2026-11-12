describe("Core", function()
	local Core

	before_each(function()
		Core = LoadAddonFile("src/Core.lua").Core
	end)

	local function state(over)
		local c = { hasBuff = false, dead = false, resting = false }
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end

	local function settings(over)
		local c = {}
		for k, v in pairs(Core.DEFAULTS) do
			c[k] = v
		end
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end

	describe("onAuraChange", function()
		it("only sets a baseline on the first observation", function()
			local t = Core.newTracker()
			local r = Core.onAuraChange(t, state({ hasBuff = false }), settings())
			assert.same({ announce = false, arm = false, cancel = false, afterCombat = false }, r)
			assert.is_false(t.hadBuff)
		end)

		it("announces and arms the reminder when the buff falls off", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, state({ hasBuff = false }), settings())
			assert.same({ announce = true, arm = true, cancel = false, afterCombat = false }, r)
		end)

		it("does nothing when nothing changed", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			assert.same({ announce = false, arm = false, cancel = false, afterCombat = false },
				Core.onAuraChange(t, state({ hasBuff = true }), settings()))
			Core.baseline(t, false)
			assert.same({ announce = false, arm = false, cancel = false, afterCombat = false },
				Core.onAuraChange(t, state({ hasBuff = false }), settings()))
		end)

		it("only fires once per falloff", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			Core.onAuraChange(t, state({ hasBuff = false }), settings())
			local r = Core.onAuraChange(t, state({ hasBuff = false }), settings())
			assert.is_false(r.announce)
			assert.is_false(r.arm)
		end)

		it("cancels the reminder when the buff comes back", function()
			local t = Core.newTracker()
			Core.baseline(t, false)
			local r = Core.onAuraChange(t, state({ hasBuff = true }), settings())
			assert.same({ announce = false, arm = false, cancel = true, afterCombat = false }, r)
		end)

		it("stays silent but still arms the reminder when dead", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, state({ dead = true }), settings())
			assert.is_false(r.announce)
			assert.is_true(r.arm)
		end)

		it("stays silent but still arms the reminder when resting", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, state({ resting = true }), settings())
			assert.is_false(r.announce)
			assert.is_true(r.arm)
		end)

		it("decides nothing and keeps its state when buffs cannot be read", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local s = state()
			s.hasBuff = nil -- state() can't set nil through its overrides table
			local r = Core.onAuraChange(t, s, settings())
			assert.same({ announce = false, arm = false, cancel = false, afterCombat = false }, r)
			assert.is_true(t.hadBuff)
		end)

		it("only re-baselines after a reset (loading screen)", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			Core.reset(t)
			local r = Core.onAuraChange(t, state({ hasBuff = false }), settings())
			assert.same({ announce = false, arm = false, cancel = false, afterCombat = false }, r)
			assert.is_false(t.hadBuff)
		end)

		it("neither announces nor arms when the addon is off", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, state(), settings({ enabled = false }))
			assert.same({ announce = false, arm = false, cancel = false, afterCombat = false }, r)
			assert.is_false(t.hadBuff)
		end)

		it("announces but does not arm when reminders are off", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, state(), settings({ remindersOn = false }))
			assert.same({ announce = true, arm = false, cancel = false, afterCombat = false }, r)
		end)

		it("announces while resting when quietWhenResting is off", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, state({ resting = true }), settings({ quietWhenResting = false }))
			assert.is_true(r.announce)
		end)
	end)

	describe("onAuraChange while buffs are hidden (combat)", function()
		local NONE = { announce = false, arm = false, cancel = false, afterCombat = false }

		local function hidden(now, over)
			local s = state(over)
			s.hasBuff = nil
			s.now = now
			return s
		end

		local function fedUntil(expires)
			local t = Core.newTracker()
			Core.baseline(t, true, expires)
			return t
		end

		it("announces once the known end time has passed, but waits to arm", function()
			local t = fedUntil(100)
			local r = Core.onAuraChange(t, hidden(101), settings())
			assert.same({ announce = true, arm = false, cancel = false, afterCombat = false }, r)
			assert.is_false(t.hadBuff)
			assert.is_true(t.overdue)
			-- Only once.
			assert.same(NONE, Core.onAuraChange(t, hidden(102), settings()))
		end)

		it("decides nothing before the end time or without one", function()
			local t = fedUntil(100)
			assert.same(NONE, Core.onAuraChange(t, hidden(99), settings()))
			assert.is_true(t.hadBuff)
			local u = fedUntil(nil)
			assert.same(NONE, Core.onAuraChange(u, hidden(1e9), settings()))
			assert.is_true(u.hadBuff)
		end)

		it("follows the quiet rules for the combat message", function()
			local t = fedUntil(100)
			local r = Core.onAuraChange(t, hidden(101, { resting = true }), settings())
			assert.is_false(r.announce)
			assert.is_true(t.overdue)
		end)

		it("owes nothing when the addon is off", function()
			local t = fedUntil(100)
			assert.same(NONE, Core.onAuraChange(t, hidden(101), settings({ enabled = false })))
			assert.is_false(t.overdue)
		end)

		it("says so again and arms the series when combat ends", function()
			local t = fedUntil(100)
			Core.onAuraChange(t, hidden(101), settings())
			local r = Core.onAuraChange(t, state({ now = 130 }), settings())
			assert.same({ announce = false, arm = true, cancel = false, afterCombat = true }, r)
			assert.is_false(t.overdue)
			assert.same(NONE, Core.onAuraChange(t, state({ now = 131 }), settings()))
		end)

		it("prints nothing after combat when reminders are off", function()
			local t = fedUntil(100)
			Core.onAuraChange(t, hidden(101), settings({ remindersOn = false }))
			assert.same(NONE, Core.onAuraChange(t, state(), settings({ remindersOn = false })))
		end)

		it("arms but stays quiet after combat when a quiet rule applies", function()
			local t = fedUntil(100)
			Core.onAuraChange(t, hidden(101), settings())
			local r = Core.onAuraChange(t, state({ dead = true }), settings())
			assert.is_false(r.afterCombat)
			assert.is_true(r.arm)
		end)

		it("stays quiet if the buff turns out to be there after combat", function()
			local t = fedUntil(100)
			Core.onAuraChange(t, hidden(101), settings())
			assert.same(NONE, Core.onAuraChange(t, state({ hasBuff = true, expires = 500 }), settings()))
			assert.is_true(t.hadBuff)
			assert.is_false(t.overdue)
		end)

		it("treats a buff lost early in the fight as a normal falloff after combat", function()
			local t = fedUntil(100)
			assert.same(NONE, Core.onAuraChange(t, hidden(50), settings()))
			local r = Core.onAuraChange(t, state({ now = 60 }), settings())
			assert.same({ announce = true, arm = true, cancel = false, afterCombat = false }, r)
		end)

		it("remembers the end time from every readable check", function()
			local t = Core.newTracker()
			Core.onAuraChange(t, state({ hasBuff = true, expires = 200 }), settings())
			assert.equal(200, t.expires)
			Core.onAuraChange(t, state({ hasBuff = true, expires = 900 }), settings()) -- ate again
			assert.equal(900, t.expires)
			Core.onAuraChange(t, state({ hasBuff = false }), settings())
			assert.is_nil(t.expires)
		end)

		it("forgets the end time and any debt on a loading screen", function()
			local t = fedUntil(100)
			Core.onAuraChange(t, hidden(101), settings())
			Core.reset(t)
			assert.is_nil(t.expires)
			assert.is_false(t.overdue)
		end)
	end)

	describe("expiryCheckDelay", function()
		it("is the time left plus a small margin while fed with an end time", function()
			local t = Core.newTracker()
			Core.baseline(t, true, 100)
			assert.equal(40 + Core.EXPIRY_MARGIN, Core.expiryCheckDelay(t, 60))
			assert.equal(Core.EXPIRY_MARGIN, Core.expiryCheckDelay(t, 150)) -- already past
		end)

		it("is nil when not fed or the end time is unknown", function()
			local t = Core.newTracker()
			assert.is_nil(Core.expiryCheckDelay(t, 0))
			Core.baseline(t, true, nil)
			assert.is_nil(Core.expiryCheckDelay(t, 0))
			Core.baseline(t, false)
			assert.is_nil(Core.expiryCheckDelay(t, 0))
		end)
	end)

	describe("findBuff", function()
		local function reader(names)
			return function(i)
				return names[i]
			end
		end

		it("is true when the buff is among the auras", function()
			assert.is_true(Core.findBuff(reader({ "Fortitude", "Well Fed" }), "Well Fed"))
		end)

		it("also returns the buff's end time, if the reader gives one", function()
			local read = function(i)
				if i == 1 then
					return "Well Fed", 1234
				end
			end
			local found, expires = Core.findBuff(read, "Well Fed")
			assert.is_true(found)
			assert.equal(1234, expires)
		end)

		it("gives no end time for a permanent (0) or secret end time", function()
			local secret = {}
			local isSecret = function(v)
				return rawequal(v, secret)
			end
			local function one(expires)
				return function(i)
					if i == 1 then
						return "Well Fed", expires
					end
				end
			end
			assert.is_nil(select(2, Core.findBuff(one(0), "Well Fed")))
			assert.is_nil(select(2, Core.findBuff(one(secret), "Well Fed", isSecret)))
			assert.is_nil(select(2, Core.findBuff(one(nil), "Well Fed")))
		end)

		it("is false when the auras run out without it", function()
			assert.is_false(Core.findBuff(reader({ "Fortitude" }), "Well Fed"))
			assert.is_false(Core.findBuff(reader({}), "Well Fed"))
		end)

		it("is nil (unknown) when reading an aura raises an error", function()
			local read = function()
				error("Auras cannot be accessed when secret while tainted")
			end
			assert.is_nil(Core.findBuff(read, "Well Fed"))
		end)

		it("is nil when an earlier aura errors before the buff is seen", function()
			local read = function(i)
				if i == 2 then
					error("secret")
				end
				return ({ "Fortitude", nil, "Well Fed" })[i]
			end
			assert.is_nil(Core.findBuff(read, "Well Fed"))
		end)

		it("is nil when an aura name is secret, without comparing it", function()
			local secret = setmetatable({}, {
				__eq = function()
					error("compared a secret")
				end,
			})
			local isSecret = function(v)
				return v == nil and false or rawequal(v, secret)
			end
			assert.is_nil(Core.findBuff(reader({ secret, "Well Fed" }), "Well Fed", isSecret))
		end)

		it("lets any other error through, so real bugs still show", function()
			local read = function()
				error("attempt to index a nil value")
			end
			assert.has_error(function()
				Core.findBuff(read, "Well Fed")
			end, "attempt to index a nil value")
		end)

		it("is nil after MAX_AURAS reads that never end", function()
			local reads = 0
			local read = function()
				reads = reads + 1
				return "Fortitude"
			end
			assert.is_nil(Core.findBuff(read, "Well Fed"))
			assert.equal(Core.MAX_AURAS, reads)
		end)
	end)

	describe("baseline", function()
		it("records an unreadable state as unknown, not as no buff", function()
			local t = Core.newTracker()
			Core.baseline(t, nil)
			assert.is_nil(t.hadBuff)
			Core.baseline(t, true)
			assert.is_true(t.hadBuff)
			Core.baseline(t, false)
			assert.is_false(t.hadBuff)
		end)
	end)

	describe("snap", function()
		it("clamps, then rounds to a step counted from the minimum", function()
			local spec = { min = 45, max = 600, step = 30 }
			assert.equal(75, Core.snap(spec, 60)) -- tie rounds up
			assert.equal(45, Core.snap(spec, 59))
			assert.equal(45, Core.snap(spec, 0))
			assert.equal(585, Core.snap(spec, 9999)) -- largest step not above max
		end)

		it("never rounds up past the maximum", function()
			assert.equal(9, Core.snap({ min = 0, max = 10, step = 3 }, 10))
		end)

		it("covers every numeric setting through NUMBER_SPECS", function()
			for key, spec in pairs(Core.NUMBER_SPECS) do
				assert.is_number(Core.DEFAULTS[key])
				assert.equal(Core.DEFAULTS[key], Core.snap(spec, Core.DEFAULTS[key]))
			end
		end)
	end)

	describe("canSpeak", function()
		it("is true by default", function()
			assert.is_true(Core.canSpeak(state(), settings()))
		end)

		it("is false when dead, resting or off", function()
			assert.is_false(Core.canSpeak(state({ dead = true }), settings()))
			assert.is_false(Core.canSpeak(state({ resting = true }), settings()))
			assert.is_false(Core.canSpeak(state(), settings({ enabled = false })))
		end)

		it("speaks when dead if quietWhenDead is off", function()
			assert.is_true(Core.canSpeak(state({ dead = true }), settings({ quietWhenDead = false })))
		end)

		it("speaks when resting if quietWhenResting is off", function()
			assert.is_true(Core.canSpeak(state({ resting = true }), settings({ quietWhenResting = false })))
		end)
	end)

	describe("normalizeSettings", function()
		it("returns all defaults for nil or a non-table", function()
			assert.same(Core.DEFAULTS, Core.normalizeSettings(nil))
			assert.same(Core.DEFAULTS, Core.normalizeSettings("x"))
		end)

		it("upgrades a 0.1.0 save", function()
			local db = { enabled = false }
			local out = Core.normalizeSettings(db)
			assert.equal(db, out) -- same table, fixed in place
			assert.is_false(out.enabled)
			assert.is_true(out.quietWhenDead); assert.is_true(out.quietWhenResting)
			assert.is_true(out.remindersOn); assert.is_false(out.remindUntilFed)
			assert.equal(60, out.reminderInterval); assert.equal(1, out.reminderCount)
		end)

		it("clamps and rounds numbers", function()
			local n = function(i, c) return Core.normalizeSettings({ reminderInterval = i, reminderCount = c }) end
			assert.equal(60, n(45, 1).reminderInterval) -- tie rounds up
			assert.equal(30, n(44, 1).reminderInterval)
			assert.equal(30, n(0, 1).reminderInterval)
			assert.equal(600, n(9999, 1).reminderInterval)
			assert.equal(3, n(60, 2.5).reminderCount)
			assert.equal(1, n(60, -3).reminderCount)
			assert.equal(10, n(60, 99).reminderCount)
		end)

		it("replaces non-numbers and NaN", function()
			local out = Core.normalizeSettings({ reminderInterval = "60", reminderCount = 0 / 0, quietWhenDead = "no" })
			assert.equal(60, out.reminderInterval); assert.equal(1, out.reminderCount)
			assert.is_true(out.quietWhenDead)
		end)

		it("does not let callers mutate DEFAULTS through the result", function()
			Core.normalizeSettings(nil).reminderCount = 7
			assert.equal(1, Core.DEFAULTS.reminderCount)
		end)
	end)

	describe("keepsSeries", function()
		it("is true by default and false when off or reminders off", function()
			assert.is_true(Core.keepsSeries(settings()))
			assert.is_false(Core.keepsSeries(settings({ enabled = false })))
			assert.is_false(Core.keepsSeries(settings({ remindersOn = false })))
		end)
	end)

	describe("reminderDue", function()
		it("reproduces v0.1.0 with defaults", function()
			assert.same({ print = true, again = false }, Core.reminderDue(Core.newSeries(), state(), settings()))
		end)

		it("skips but counts when dead or resting", function()
			local s = Core.newSeries()
			assert.same({ print = false, again = false }, Core.reminderDue(s, state({ dead = true }), settings()))
			assert.equal(1, s.due)
		end)

		it("holds without counting when buffs cannot be read", function()
			local st = state()
			st.hasBuff = nil
			local s = Core.newSeries()
			assert.same({ print = false, again = false, hold = true }, Core.reminderDue(s, st, settings()))
			assert.equal(0, s.due)
			-- Readable again (combat over): the held reminder comes due as normal.
			assert.same({ print = true, again = false }, Core.reminderDue(s, state(), settings()))
			assert.equal(1, s.due)
		end)

		it("stops silently when fed again", function()
			assert.same({ print = false, again = false },
				Core.reminderDue(Core.newSeries(), state({ hasBuff = true }), settings({ reminderCount = 3 })))
		end)

		it("runs reminderCount times", function()
			local s, cfg = Core.newSeries(), settings({ reminderCount = 3 })
			assert.is_true(Core.reminderDue(s, state(), cfg).again)
			assert.is_true(Core.reminderDue(s, state(), cfg).again)
			assert.is_false(Core.reminderDue(s, state(), cfg).again)
		end)

		it("keeps going until fed", function()
			local s, cfg = Core.newSeries(), settings({ remindUntilFed = true, reminderCount = 1 })
			for _ = 1, 20 do
				assert.is_true(Core.reminderDue(s, state(), cfg).again)
			end
		end)

		it("stops when the addon or reminders are off", function()
			assert.same({ print = false, again = false },
				Core.reminderDue(Core.newSeries(), state(), settings({ enabled = false })))
			assert.same({ print = false, again = false },
				Core.reminderDue(Core.newSeries(), state(), settings({ remindersOn = false })))
		end)

		it("ends after the pending reminder when the new count is used up", function()
			local s = Core.newSeries()
			Core.reminderDue(s, state(), settings({ reminderCount = 5 }))
			Core.reminderDue(s, state(), settings({ reminderCount = 5 }))
			assert.same({ print = true, again = false }, Core.reminderDue(s, state(), settings({ reminderCount = 1 })))
		end)
	end)

	describe("formatInterval", function()
		it("formats seconds and minutes", function()
			assert.equal("30 s", Core.formatInterval(30))
			assert.equal("1 min", Core.formatInterval(60))
			assert.equal("1 min 30 s", Core.formatInterval(90))
			assert.equal("2 min 30 s", Core.formatInterval(150))
			assert.equal("10 min", Core.formatInterval(600))
		end)
	end)

	describe("controlStates", function()
		it("enables everything by default", function()
			assert.same({ interval = true, count = true, untilFed = true }, Core.controlStates(settings()))
		end)

		it("disables count when reminding until fed", function()
			assert.same({ interval = true, count = false, untilFed = true },
				Core.controlStates(settings({ remindUntilFed = true })))
		end)

		it("disables everything when reminders are off", function()
			assert.same({ interval = false, count = false, untilFed = false },
				Core.controlStates(settings({ remindersOn = false })))
		end)
	end)

	describe("loadedMessage", function()
		it("names the version and the on state", function()
			assert.are.equal("loaded v0.1.0. Snack alerts are on. /peckish off to mute.",
				Core.loadedMessage(" v0.1.0", true))
		end)

		it("tells you how to turn it back on when off", function()
			assert.are.equal("loaded. Snack alerts are off. /peckish on to arm them.",
				Core.loadedMessage("", false))
		end)
	end)

	describe("parseCommand", function()
		it("reads on and off, trimmed and case-insensitive", function()
			assert.are.equal("on", Core.parseCommand("on"))
			assert.are.equal("on", Core.parseCommand("  ON "))
			assert.are.equal("off", Core.parseCommand("Off"))
		end)

		it("opens the window for nil, empty or blank input", function()
			assert.are.equal("open", Core.parseCommand(""))
			assert.are.equal("open", Core.parseCommand(nil))
			assert.are.equal("open", Core.parseCommand("   "))
		end)

		it("treats anything else as a status request", function()
			assert.are.equal("status", Core.parseCommand("toggle"))
		end)
	end)
end)
