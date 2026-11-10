describe("Core", function()
	local Core

	before_each(function()
		Core = LoadAddonFile("src/Core.lua").Core
	end)

	local function ctx(over)
		local c = { hasBuff = false, enabled = true, dead = false, resting = false }
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end

	describe("onAuraChange", function()
		it("only sets a baseline on the first observation", function()
			local t = Core.newTracker()
			local r = Core.onAuraChange(t, ctx({ hasBuff = false }))
			assert.same({ announce = false, arm = false, cancel = false }, r)
			assert.is_false(t.hadBuff)
		end)

		it("announces and arms the reminder when the buff falls off", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, ctx({ hasBuff = false }))
			assert.same({ announce = true, arm = true, cancel = false }, r)
		end)

		it("does nothing when nothing changed", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			assert.same({ announce = false, arm = false, cancel = false },
				Core.onAuraChange(t, ctx({ hasBuff = true })))
			Core.baseline(t, false)
			assert.same({ announce = false, arm = false, cancel = false },
				Core.onAuraChange(t, ctx({ hasBuff = false })))
		end)

		it("only fires once per falloff", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			Core.onAuraChange(t, ctx({ hasBuff = false }))
			local r = Core.onAuraChange(t, ctx({ hasBuff = false }))
			assert.is_false(r.announce)
			assert.is_false(r.arm)
		end)

		it("cancels the reminder when the buff comes back", function()
			local t = Core.newTracker()
			Core.baseline(t, false)
			local r = Core.onAuraChange(t, ctx({ hasBuff = true }))
			assert.same({ announce = false, arm = false, cancel = true }, r)
		end)

		it("stays silent but still arms the reminder when dead", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, ctx({ dead = true }))
			assert.is_false(r.announce)
			assert.is_true(r.arm)
		end)

		it("stays silent but still arms the reminder when resting", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, ctx({ resting = true }))
			assert.is_false(r.announce)
			assert.is_true(r.arm)
		end)

		it("decides nothing and keeps its state when buffs cannot be read", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local c = ctx()
			c.hasBuff = nil -- ctx() can't set nil through its overrides table
			local r = Core.onAuraChange(t, c)
			assert.same({ announce = false, arm = false, cancel = false }, r)
			assert.is_true(t.hadBuff)
		end)

		it("only re-baselines after a reset (loading screen)", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			Core.reset(t)
			local r = Core.onAuraChange(t, ctx({ hasBuff = false }))
			assert.same({ announce = false, arm = false, cancel = false }, r)
			assert.is_false(t.hadBuff)
		end)

		it("neither announces nor arms when the addon is off", function()
			local t = Core.newTracker()
			Core.baseline(t, true)
			local r = Core.onAuraChange(t, ctx({ enabled = false }))
			assert.same({ announce = false, arm = false, cancel = false }, r)
			assert.is_false(t.hadBuff)
		end)
	end)

	describe("shouldRemind", function()
		it("reminds when still unfed and nothing suppresses it", function()
			assert.is_true(Core.shouldRemind(ctx()))
		end)

		it("does not remind when fed again", function()
			assert.is_false(Core.shouldRemind(ctx({ hasBuff = true })))
		end)

		it("does not remind when buffs cannot be read", function()
			local c = ctx()
			c.hasBuff = nil
			assert.is_false(Core.shouldRemind(c))
		end)

		it("does not remind when dead, resting or off", function()
			assert.is_false(Core.shouldRemind(ctx({ dead = true })))
			assert.is_false(Core.shouldRemind(ctx({ resting = true })))
			assert.is_false(Core.shouldRemind(ctx({ enabled = false })))
		end)
	end)

	describe("parseCommand", function()
		it("reads on and off, trimmed and case-insensitive", function()
			assert.are.equal("on", Core.parseCommand("on"))
			assert.are.equal("on", Core.parseCommand("  ON "))
			assert.are.equal("off", Core.parseCommand("Off"))
		end)

		it("treats anything else as a status request", function()
			assert.are.equal("status", Core.parseCommand(""))
			assert.are.equal("status", Core.parseCommand(nil))
			assert.are.equal("status", Core.parseCommand("toggle"))
		end)
	end)
end)
