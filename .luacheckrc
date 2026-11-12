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
	"FeelingPeckishOptionsFrame", -- the settings window (src/Options.lua)
}

-- WoW API this addon reads. Add each new API here as it is used,
-- so a typo in an API name fails lint instead of failing in game.
read_globals = {
	"C_AddOns",
	"C_Timer",
	"GetAddOnMetadata",
	"GetTime",
	"C_UnitAuras",
	"CreateFrame",
	"DEFAULT_CHAT_FRAME",
	"IsResting",
	"issecretvalue",
	"UnitBuff",
	"UnitIsDeadOrGhost",
	"UIParent",
	"UISpecialFrames",
}

files["spec/"] = {
	std = "+busted",
	read_globals = { "LoadAddonFile" },
}

files["spec/helper.lua"] = {
	globals = { "LoadAddonFile" },
}
