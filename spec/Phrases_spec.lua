describe("Phrases", function()
	local Phrases

	before_each(function()
		Phrases = LoadAddonFile("src/Phrases.lua").Phrases
	end)

	it("has exactly 50 unique, short phrases", function()
		assert.are.equal(50, #Phrases.list)
		local seen = {}
		for i, phrase in ipairs(Phrases.list) do
			assert.is_string(phrase)
			assert.is_nil(seen[phrase], "duplicate phrase at " .. i)
			assert.is_true(#phrase > 0 and #phrase <= 70, "phrase " .. i .. " is too long")
			seen[phrase] = true
		end
	end)

	it("matches the list in PRD.md section 5", function()
		local file = assert(io.open("PRD.md", "r"))
		local prd = file:read("*a")
		file:close()
		local section = prd:match("## 5%. Phrases(.-)\n## ")
		assert.is_string(section)
		local fromPrd = {}
		for phrase in section:gmatch("\n%d+%. ([^\n]+)") do
			fromPrd[#fromPrd + 1] = phrase
		end
		assert.same(fromPrd, Phrases.list)
	end)

	it("never repeats the previous phrase back-to-back", function()
		local pick = Phrases.newPicker()
		local previous = pick()
		for _ = 1, 2000 do
			local current = pick()
			assert.are_not.equal(previous, current)
			previous = current
		end
	end)

	it("steps over the last index when the roll lands on or after it", function()
		local rolls = { 3, 3, 1, 2 }
		local rand = function(n)
			local r = table.remove(rolls, 1)
			assert.is_true(r >= 1 and r <= n)
			return r
		end
		local pick = Phrases.newPicker(rand, { "a", "b", "c", "d" })
		assert.are.equal("c", pick()) -- first pick: any of 4
		assert.are.equal("d", pick()) -- 3 of the other 3 -> skips c
		assert.are.equal("a", pick()) -- 1 is before d, unchanged
		assert.are.equal("c", pick()) -- 2 is on/after a -> 3
	end)

	it("can reach every phrase", function()
		local pick = Phrases.newPicker()
		local seen, count = {}, 0
		for _ = 1, 5000 do
			local p = pick()
			if not seen[p] then
				seen[p] = true
				count = count + 1
			end
		end
		assert.are.equal(50, count)
	end)

	it("works with a one-phrase list", function()
		local pick = Phrases.newPicker(nil, { "only" })
		assert.are.equal("only", pick())
		assert.are.equal("only", pick())
	end)
end)
