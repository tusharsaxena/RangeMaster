local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- tests/test_realpages.lua — the real settings pages, driven through their deferred OnShow: the
-- registered subcategories, the Profiles page's self-skip, the General tab strip and its Defaults
-- button, the combat cover on the sidebar path, and the landing (About) page.

local Helpers = NS.Helpers

-- ── The real pages, driven through their deferred OnShow ───────────────────────────

test("the Profiles page self-skips when AceDBOptions is unavailable", function()
  -- It is an optional dependency; the page must opt out silently rather than erroring the build.
  assertEqual(T.mocks.__subcategories["Profiles"], nil)
end)

-- The rendered ctx of a real page. `__panels()` also holds every throwaway panel this suite has
-- created, several of which share a pageKey with a real one -- so "has a scroll" is the half of the
-- match that says this one actually rendered.
local function renderedCtx(pageKey)
  for _, c in ipairs(Helpers.__panels()) do
    if c.pageKey == pageKey and c.scroll then return c end
  end
end

local function tabButtons(ctx)
  local out = {}
  for _, f in ipairs(ctx.__tabKids or {}) do
    if f.__frameType == "Button" then out[#out + 1] = f end
  end
  return out
end

test("the main page's About content renders on its first OnShow", function()
  local panel = T.mocks.__mainPanel
  assertTrue(panel ~= nil, "the main canvas was registered")
  local ok, err = pcall(function() panel:__fire("OnShow") end)
  assertTrue(ok, "BuildMainContent failed: " .. tostring(err))
end)

test("re-rendering the About page replaces its body rather than stacking a second copy", function()
  -- The main page is re-rendered on every re-show after a refresh marked it dirty (a /rm set, a
  -- profile change), so its renderer must clear the scroll first. The hand-rolled body this file
  -- used to carry did not, and the panel grew a second logo, description and command list per
  -- render. Driven through the renderer directly: OnShow short-circuits on a clean page, which is
  -- exactly why the bug survived the first-OnShow case above.
  local panel = T.mocks.__mainPanel
  local ctx
  for _, c in ipairs(NS.Helpers.__panels()) do
    if c.panel == panel then ctx = c end
  end
  assertTrue(ctx ~= nil, "the main canvas ctx is in the panel registry")

  NS.Helpers.BuildMainContent(ctx)
  local firstCount = #ctx.scroll.children
  assertTrue(firstCount > 0, "the About page rendered something")

  NS.Helpers.BuildMainContent(ctx)
  assertEqual(#ctx.scroll.children, firstCount,
    "the second render lands at the same child count, not a doubled/stacked set")
end)


test("the General page registered a real Blizzard subcategory at build time", function()
  assertTrue(T.mocks.__subcategories["General"] ~= nil, "General page was registered")
end)

test("first OnShow builds the General Defaults button, with the collection's reset tooltip", function()
  local panel = T.mocks.__subcategories["General"]
  panel:__fire("OnShow")
  assertTrue(panel.defaultsBtn ~= nil, "the button is built late, after skinners have loaded")
  assertEqual(panel.defaultsBtn.text, "Defaults")
  assertTrue(panel.defaultsBtn.callbacks.OnClick ~= nil, "the parked click handler got wired")
end)

test("the General page draws Master controls first, then Presets, and the Skin tab last", function()
  -- options-ui-§13/§15, skinning-§3: the page a player opens first leads with Master controls, and
  -- with no Keybindings tab the library's Skin tab closes the strip. The Presets host tab
  -- (settings/Presets.lua) sits between them.
  local panel = T.mocks.__subcategories["General"]
  panel:__fire("OnShow")
  local ctx = renderedCtx("general")
  assertTrue(ctx ~= nil, "the General page rendered")
  local tabs = tabButtons(ctx)
  assertEqual(#tabs, 3, "Master controls, Presets and the Skin tab")
  assertEqual(ctx.activeTab, "Master controls", "the General page opens on Master controls")
  assertFalse(tabs[1].__enabled, "the first tab is the selected one")
  assertTrue(tabs[2].__enabled and tabs[3].__enabled, "and the Presets and Skin tabs are clickable")

  local labels = {}
  local function walk(w)
    for _, child in ipairs(w.children or {}) do
      if child.labelText then labels[child.labelText] = true end
      walk(child)
    end
  end
  walk(ctx.scroll)
  for _, label in ipairs({ "Enable Range Master", "Lock frame", "Test mode", "Sim mode",
      "Debug console", "Minimap button" }) do
    assertTrue(labels[label], "the Master controls tab shows " .. label)
  end
  for _, child in ipairs(ctx.scroll.children) do
    assertTrue(child.type ~= "Heading", "a tabbed page draws no section headings")
  end
end)

test("the General page is covered in combat on the sidebar path, and the window stays open (options-ui-§2)", function()
  -- The Blizzard AddOns sidebar hands a canvas its OnShow directly, never through
  -- NS.OpenOptionsPanel, so the page declares its body through Helpers.SetRenderer and the combat
  -- lock is the library's: covered, nothing drawn, one gray notice, and the window is not closed.
  -- red under: giving the page back a ctx.panel:SetScript("OnShow", ...) of its own.
  local lib = T.mocks.LibStub("LibKa0s-Options-1.0")
  local savedICL = T.mocks.InCombatLockdown
  T.mocks.InCombatLockdown = function() return true end
  local out = {}
  local cf = T.mocks.DEFAULT_CHAT_FRAME
  local old = rawget(cf, "AddMessage")
  cf.AddMessage = function(_, msg) out[#out + 1] = msg end
  local closedBefore = T.mocks.__settingsClosed
  local page
  local ok, err = pcall(function()
    local panel = T.mocks.__subcategories["General"]
    panel:Show()
    panel:__fire("OnShow")
    for ctx in pairs(lib.__shownPages) do
      if ctx.panel == panel then page = ctx end
    end
  end)
  cf.AddMessage = old
  T.mocks.InCombatLockdown = savedICL
  assertTrue(ok, tostring(err))
  assertEqual(T.mocks.__settingsClosed, closedBefore, "the Settings window is not closed")
  assertTrue(page ~= nil, "General is an on-screen page the library watches combat for")
  assertTrue(page.__combatCover ~= nil and page.__combatCover:IsShown(), "General is covered")
  assertTrue(table.concat(out, "\n"):find(lib.STRINGS.COMBAT_LOCKED_NOTICE, 1, true) ~= nil,
    "the library's one gray notice")
  page.panel:Hide()
  page.panel:__fire("OnHide")
end)
