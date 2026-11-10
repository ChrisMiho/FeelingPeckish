-- Loaded by busted before every spec (see .busted).
-- WoW runs each addon file as a chunk called with (addonName, namespace);
-- LoadAddonFile does the same so specs can test files as the game loads them.

local ADDON_NAME = "FeelingPeckish"

function _G.LoadAddonFile(path, ns)
	ns = ns or {}
	local chunk, err = loadfile(path)
	if not chunk then
		error(err, 2)
	end
	chunk(ADDON_NAME, ns)
	return ns
end
