-- tests/test_skinsetup.lua — the LibKa0s-Skin-1.0 seam (core/SkinSetup.lua, skinning-§3).
--
-- What this addon owes the skin engine, and nothing the library pins itself: the owner is
-- registered under the folder name with this addon's read and write seams; the eight `skin.*` keys
-- default to Ka0s Default and are skip-render schema rows on General's Skin tab; the tab lands last
-- on General; the profile's skin is applied right after AceDB exists and on every profile event;
-- one pick, from this addon's tab or another addon's copy, is ONE effective SetChoice (one
-- OnLooksChanged), however many store writes follow it; and the drag strips carry the owner.
--
-- Modeled on LootHistory's tests/test_skinsetup.lua, the reference adopter. After test_realpages,
-- which leaves the General page built and parked on its first tab; every case here parks it there
-- again and puts the skin back on Ka0s Default.

local T = _G.RM_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OWNER = "RangeMaster"
-- The client's default skin under the active kit profile (LibKa0s v1.94.0, skinning-§2): WoW Forever
-- on forever, Ka0s Default on retail. Pinned from the profile, never read back from the addon.
local CLIENT_SKIN = dofile("tests/_kit/mock_client.lua").current() == "forever" and "forever" or "ka0s"

-- ONE listener for the whole file: the library keeps a listener for the session, so each case
-- resets the counter instead of registering again.
local looks = 0
NS.Skin.OnLooksChanged(function() looks = looks + 1 end)

--- Back on Ka0s Default, stored and applied, with the Scope's defaults and no overrides, the
--- library's deferred page re-render run, and the counter cleared.
local function reset()
  NS.WriteSkinChoice("ka0s", "ka0s", { panel = true, fonts = false },
    { font = false, texture = false, outline = "hud" })
  Skin:SetChoice(OWNER, "ka0s", "ka0s")
  Skin:SetIgnore(OWNER, true, false)
  if Skin.SetOverride then Skin:SetOverride(OWNER, false, false) end
  if Skin.SetOutline then Skin:SetOutline(OWNER, "all") end
  mocks.__fireTimers()
  looks = 0
end

--- Run `fn` with the skin reset before and after, whatever `fn` raised.
local function clean(fn)
  return function()
    reset()
    local ok, err = pcall(fn)
    reset()
    if not ok then error(err, 0) end
  end
end

--- `/rm <line>` with chat swallowed.
local function quietly(line)
  local cf = mocks.DEFAULT_CHAT_FRAME
  local old = rawget(cf, "AddMessage")
  cf.AddMessage = function() end
  local ok, err = pcall(function() NS.Slash:OnSlash(line) end)
  cf.AddMessage = old
  if not ok then error(err, 0) end
end





-- ── the owner ────────────────────────────────────────────────────────────────────────────────

test("Skin seam: the owner is the folder name, and NS.Skin is its facade", function()
  -- red under: registering under the brand or a typo (the library keys every frame and every
  -- listener by owner), or publishing a facade of some other owner.
  assertTrue(Skin:IsOwner(OWNER), "core/SkinSetup.lua did not register the owner")
  assertTrue(rawequal(NS.Skin, Skin:For(OWNER)), "NS.Skin is not Skin:For(\"RangeMaster\")")
  assertEqual(NS.Skin.owner, OWNER)
  assertEqual(Skin:OwnerLabel(OWNER), NS.Constants.BRAND, "the copy confirmation names the brand")
end)

test("Skin seam: the read answers the client's default skin before the profile store exists", function()
  -- RegisterOwner calls `get` at FILE LOAD, before NS:InitDB; a getter that raised there would be a
  -- visible Lua error on every login.
  local db = NS.db
  NS.db = nil
  local ok, source, skin = pcall(NS.SkinChoice)
  local ok2, font, texture = pcall(NS.SkinOverride)
  NS.db = db
  assertTrue(ok, "NS.SkinChoice raised without a store: " .. tostring(source))
  assertEqual(source, "ka0s")
  assertEqual(skin, CLIENT_SKIN)
  assertTrue(ok2, "NS.SkinOverride raised without a store: " .. tostring(font))
  assertEqual(font, false)
  assertEqual(texture, false)
end)

-- ── the keys and the rows ────────────────────────────────────────────────────────────────────

test("Skin seam: the skin row's values are every registered skin, in the library's order", function()
  local values = NS.FindSchemaRow("skin.skin").values
  local skins = Skin:Skins()
  assertEqual(#values, #skins, "one value per registered skin")
  for i, def in ipairs(skins) do assertEqual(values[i].value, def.key, "value " .. i) end
  assertEqual(values[1].value, "ka0s", "Ka0s Default first")
end)

test("Skin seam: /rm set refuses a skin that is not registered and applies one that is", clean(function()
  quietly("set skin.skin no-such-skin")
  assertEqual(NS.db.profile.skin.skin, "ka0s", "an unknown skin was stored")
  assertEqual(looks, 0, "a refused set repainted")
  quietly("set skin.skin obsidian")
  assertEqual(NS.db.profile.skin.skin, "obsidian", "a registered skin was refused")
  local _, applied = Skin:GetChoice(OWNER)
  assertEqual(applied, "obsidian", "a bare set must move the applied skin (the row's onChange)")
  assertEqual(looks, 1, "one set, one repaint")
end))

-- ── the tab ──────────────────────────────────────────────────────────────────────────────────

test("Skin seam: another addon's copy to every Ka0s addon repaints RangeMaster once", clean(function()
  -- The library's copy calls SetChoice for each other owner, then WriteChoice, which reaches this
  -- addon's registered setter. Driven directly, as the copy drives it.
  Skin:SetChoice(OWNER, "ka0s", "ember")
  assertTrue(Skin:WriteChoice(OWNER, "ka0s", "ember"), "the copy's write did not reach the setter")
  assertEqual(looks, 1, "a copy must repaint this addon exactly once")
  assertEqual(NS.db.profile.skin.skin, "ember", "the copy did not land in the profile")
end))

-- ── the stored exceptions and overrides ──────────────────────────────────────────────────────

test("Skin seam: a whole apply carries the stored exceptions and overrides with the skin", clean(function()
  -- addon:OnInitialize and the profile events call NS.ApplySkinChoice() with no argument.
  -- red under: applying the stored pair and not the rest.
  T.rawSet("skin.ignorePanel", false)
  T.rawSet("skin.ignoreFonts", true)
  T.rawSet("skin.texture", "Solid")
  T.rawSet("skin.outline", "off")
  NS.ApplySkinChoice()
  local panel, fonts = Skin:GetIgnore(OWNER)
  assertEqual(panel, false, "the stored panel exception")
  assertEqual(fonts, true, "the stored fonts exception")
  local _, texture = Skin:GetOverride(OWNER)
  assertEqual(texture, "Solid", "the stored texture override")
  assertEqual(Skin:GetOutline(OWNER), "off", "the stored Font outline (LibKa0s v1.82.0)")
end))

-- ── the Font outline (LibKa0s v1.82.0, Skin minor 9, ruling D-06) ───────────────────────────

test("Skin seam: the outline row offers the library's three modes, in its order", function()
  local row = NS.FindSchemaRow("skin.outline")
  assertTrue(row ~= nil, "a skin.outline row")
  local got = {}
  for _, opt in ipairs(row.values) do got[#got + 1] = opt.value end
  assertEqual(table.concat(got, ","), table.concat(Skin.OUTLINE_MODES, ","))
end)

test("Skin seam: the write seam stores media.outline, and leaves it alone when it is nil", clean(function()
  -- red under: WriteSkinChoice dropping media.outline (the Skin tab's Font outline and another
  -- addon's copy would move the look and never store it).
  NS.WriteSkinChoice(nil, nil, nil, { font = false, texture = false, outline = "all" })
  assertEqual(NS.db.profile.skin.outline, "all")
  NS.WriteSkinChoice(nil, nil, nil, { font = false, texture = false })
  assertEqual(NS.db.profile.skin.outline, "all", "a media table without outline leaves it")
  Skin:WriteChoice(OWNER, "ka0s", "ka0s", nil, { font = false, texture = false, outline = "off" })
  assertEqual(NS.db.profile.skin.outline, "off", "another addon's copy reaches the store")
end))

test("Skin seam: /rm set skin.outline applies the mode live and refuses an unknown one", clean(function()
  quietly("set skin.outline all")
  assertEqual(NS.db.profile.skin.outline, "all")
  assertEqual(Skin:GetOutline(OWNER), "all", "the row's onChange applied it")
  assertEqual(NS.Skin.Token("hud.outline"), "OUTLINE", "the HUD keeps its outline")
  quietly("set skin.outline off")
  assertEqual(NS.Skin.Token("hud.outline"), "", "Off takes it")
  quietly("set skin.outline thick")
  assertEqual(NS.db.profile.skin.outline, "off", "an unknown mode is refused")
end))

test("Skin seam: /rm set reaches an exception and an override, each only its own half", clean(function()
  quietly("set skin.ignoreFonts true")
  local panel, fonts = Skin:GetIgnore(OWNER)
  assertEqual(fonts, true, "the set applied")
  assertEqual(panel, true, "the other half untouched")
  quietly("set skin.font Friz Quadrata TT")
  local font, texture = Skin:GetOverride(OWNER)
  assertEqual(font, "Friz Quadrata TT", "a free-text font key is taken and applied")
  assertEqual(texture, nil, "the texture override untouched (nil, the skin's own)")
  assertEqual(NS.db.profile.skin.font, "Friz Quadrata TT")
end))

-- ── the profile events ───────────────────────────────────────────────────────────────────────

test("Skin seam: a profile switch applies the new profile's skin, and back", clean(function()
  -- AceDB replaces the whole profile with no row's onChange firing; adoptProfile
  -- (core/RangeMaster.lua) must apply the new profile's skin. red under: not applying it.
  local db = NS.db
  local ok, err = pcall(function()
    db:SetProfile("SkinProbe")
    T.rawSet("skin.skin", "glass")
    db:SetProfile("Default")
    assertEqual(select(2, Skin:GetChoice(OWNER)), "ka0s", "back on Default, Default's skin")
    looks = 0
    db:SetProfile("SkinProbe")
    assertEqual(select(2, Skin:GetChoice(OWNER)), "glass", "the switch did not move the applied skin")
    assertEqual(looks, 1, "one switch, one repaint")
  end)
  if db:GetCurrentProfile() ~= "Default" then db:SetProfile("Default") end
  if db.DeleteProfile then pcall(db.DeleteProfile, db, "SkinProbe", true) end
  if not ok then error(err, 0) end
end))

test("Skin seam: a profile switch applies the new profile's Font outline, and back", clean(function()
  -- red under: adoptProfile's whole apply leaving the outline the old profile's.
  local db = NS.db
  local ok, err = pcall(function()
    db:SetProfile("OutlineProbe")
    -- A stored All text stays All text (D-10: the default moved, a stored value never does).
    T.rawSet("skin.outline", "all")
    db:SetProfile("Default")
    assertEqual(Skin:GetOutline(OWNER), "hud", "back on Default, Default's Font outline")
    db:SetProfile("OutlineProbe")
    assertEqual(Skin:GetOutline(OWNER), "all", "the switch did not apply the profile's Font outline")
  end)
  if db:GetCurrentProfile() ~= "Default" then db:SetProfile("Default") end
  if db.DeleteProfile then pcall(db.DeleteProfile, db, "OutlineProbe", true) end
  if not ok then error(err, 0) end
end))

-- ── the factories ────────────────────────────────────────────────────────────────────────────
