std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
	"Libs/",
	".release/",
	".lua/",      -- Lua installed by CI (leafo/gh-actions-lua)
	".luarocks/", -- LuaRocks installed by CI (leafo/gh-actions-luarocks)
	".luacheckrc",
	".worktrees/",
	".superpowers/", -- local tooling state
}

-- Globals this addon creates
globals = {
	"SlashCmdList",
	"SLASH_FEELINGPECKISH1",
	"FeelingPeckishDB",
}

-- WoW API this addon reads. Add each new API here as it is used,
-- so a typo in an API name fails lint instead of failing in game.
read_globals = {
	"AuraUtil",
	"C_Timer",
	"C_UnitAuras",
	"CreateFrame",
	"DEFAULT_CHAT_FRAME",
	"IsResting",
	"UnitIsDeadOrGhost",
}

files["spec/"] = {
	std = "+busted",
	read_globals = { "LoadAddonFile" },
}

files["spec/helper.lua"] = {
	globals = { "LoadAddonFile" },
}
