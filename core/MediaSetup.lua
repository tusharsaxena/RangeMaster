local addonName, NS = ...
-- core/MediaSetup.lua — the LibKa0s-Media-1.0 seam: the shared icon catalog, the monospace face and
-- the bar textures (library-stack-§8).
--
-- The art ships inside the vendored payload at libs/LibKa0s/media/, so this addon carries no copy of
-- any of it (layout-§3, anti-pattern #63). Its icons are pruned to the names CLAUDE.md's
-- `LibKa0s icons:` line declares (library-stack-§7, the icon subset), so a new NS.Icon name must be
-- declared there or it draws blank.
--
-- LOAD-BEARING POSITION: core/Constants.lua resolves FONT_MONO from NS.MediaFont at FILE LOAD, so this
-- file must precede it; tests/test_loadorder.lua pins it.
--
-- NIL IS A REAL ANSWER from both functions: the library may be absent, or the name may not be one it
-- ships. Nothing here builds a path by concatenation to paper over that.

local Media = LibStub and LibStub("LibKa0s-Media-1.0", true)

--- The texture path for one shipped icon (extensionless, by the library's contract), or nil.
--- @param name string  an entry of the library's ICONS catalog, e.g. "settings"
--- @return string|nil
function NS.Icon(name)
    if not Media then return nil end
    return Media.Icon(addonName, name)
end

--- The path of one shipped font face, or nil.
--- @param name string  a key of the library's FONTS, e.g. "JetBrains Mono"
--- @return string|nil
function NS.MediaFont(name)
    if not Media then return nil end
    return Media.Font(addonName, name)
end

-- At FILE LOAD, not PLAYER_LOGIN: LibSharedMedia is vendored under libs/ and has already run, and a
-- shipped default naming a face or texture LSM has not heard of yet would resolve to nothing.
if Media then Media.RegisterLSM(addonName) end
