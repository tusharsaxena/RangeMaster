-- tests/run.lua — the headless test runner for Ka0s Range Master.
-- Run from the repo root:  lua tests/run.lua        (add --list for the case inventory)
--                          KA0S_KIT_CLIENT=forever lua tests/run.lua   (the WoW Forever profile)
--
-- The registry, the assertions, the source loader and the universal WoW-API mock live in the shared
-- kit under tests/_kit/ (vendored from the LibKa0s repo's testkit/). What stays here is what is this
-- addon's: the load list, the lifecycle kick, and the suite list.

local Kit        = dofile("tests/_kit/framework.lua")
local Loader     = dofile("tests/_kit/loader.lua")
local buildMocks = dofile("tests/wow_mock.lua")

local mocks = buildMocks()
local NS = {}

Loader.addonName = "RangeMaster"

-- The vendored library files, which the TOC reaches through libs\LibKa0s\LibKa0s.xml and so are
-- invisible to Loader.tocFiles. Derived from that XML: a hand-kept list short by one file does not
-- raise -- the module never registers, its degradation stub takes over, and the suite measures the
-- stub (testing-§9).
local LIB_FILES = Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml")
-- LibRangeCheck-3.0, which the TOC lists by its own line rather than through an XML, so neither
-- derivation above reaches it. Loaded after LibKa0s, as the TOC orders it, so a suite reaches the
-- vendored estimator through LibStub; tests/wow_mock.lua answers what it reads at load. The real
-- CallbackHandler-1.0 loads first (the TOC loads it through its XML, before the estimator): the
-- estimator's CHECKERS_CHANGED callback, a rebuild trigger (core/RangeMaster.lua), is built on it.
local RANGECHECK_FILES = { "libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
  "libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua" }

-- The addon's own files come from the TOC, so this runner cannot drift from what the client loads.
local ADDON_FILES = Loader.tocFiles("RangeMaster.toc")

Loader.loadAll(LIB_FILES, NS, mocks)
Loader.loadAll(RANGECHECK_FILES, NS, mocks)
Loader.loadAll(ADDON_FILES, NS, mocks)

-- Mirror the in-game lifecycle: OnInitialize (the database, the skin, the slash command, the
-- launcher), then OnEnable at PLAYER_LOGIN (the latch, the events, the settings panel).
NS.addon:OnInitialize()
NS.addon:OnEnable()
-- The boot profile is fresh, so OnEnable shows the first-run preset picker, which previews Simple on
-- an empty profile (settings/Presets.lua). Close it unanswered, as a player's Escape would: no suite
-- starts with a preview's containers on screen (their units would stay watched on the ticker).
if NS.HidePresetPicker then NS.HidePresetPicker() end

-- The live halves the degradation stubs are compared against: INSTANCES where the host mirrors an
-- instance, library tables where it wires members one by one.
Kit.setSurfaceSource{
  ["LibKa0s-Options-1.0"]   = NS.Helpers,
  ["LibKa0s-DebugLog-1.0"]  = NS.DebugLog,
  ["LibKa0s-Slash-1.0"]     = NS.Slash and NS.Slash.__cli,
  ["LibKa0s-Launcher-1.0"]  = NS.Launcher,
  ["LibKa0s-Bus-1.0"]       = mocks.LibStub("LibKa0s-Bus-1.0", true),
  ["LibKa0s-Schema-1.0"]    = mocks.LibStub("LibKa0s-Schema-1.0", true),
  ["LibKa0s-Lifecycle-1.0"] = NS.lifecycle,
  ["LibKa0s-Compat-1.0"]    = mocks.LibStub("LibKa0s-Compat-1.0", true),
  ["LibKa0s-Pool-1.0"]      = mocks.LibStub("LibKa0s-Pool-1.0", true),
}

_G.RM_TEST = Kit.expose{
  NS = NS, mocks = mocks,
  loadedAddonFiles = ADDON_FILES,
  loadedLibFiles   = LIB_FILES,
  loadedRangeCheckFiles = RANGECHECK_FILES,
  -- A raw profile write that bypasses the seam, for a case that sets up stored state.
  rawSet = function(path, value) NS.SetPath(NS.db.profile, path, value) end,
  -- The kit's secret-value simulator (tests/_kit/secrets.lua), for the range and compat suites.
  secret = Kit.secret,
  installSecretValue = Kit.installSecretValue,
}

-- The kit's diagnostics contract (debug-logging-§14), run against this addon's own dispatcher.
Kit.diagnostics = {
  brand       = NS.Constants.BRAND,
  dispatch    = function(line) NS.Slash:OnSlash(line) end,
  console     = function() return NS.DebugLog end,
  setDebug    = function(on) NS.State.debug = on and true or false end,
  setDisabled = function(off)
    NS.SetByPath("enabled", not off)
    NS.SyncEnabledHold()
  end,
}

-- The kit's typed-value gate (skinning-§1). Two rows, each a kit row category (test kit revision 58,
-- the owner's U-6): values the scanner reads as colors that no player ever sees. Two rows for the
-- preview nameplate, which cite skinning-§9's Preview stand-ins (owner ruling U-24 of 2026-11-20,
-- plan item SD-RULE of Ka0sAddonsCommonTasks docs/2026-11-20-LIBKA0S_94_97_99_100).
local STANDIN = "the unlocked preview's stand-in nameplate keeps an enemy nameplate's look under every "
  .. "skin, so offsets tuned against it match a real plate (skinning-§9 Preview stand-ins, owner U-24, 2026-11-20)"
Kit.skinValues = {
  rows = {
    { file = "modules/Anchors_Mockplate.lua", substring = "p.bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)",
      why = STANDIN .. ": its ground", cause = "SD-RULE" },
    { file = "modules/Anchors_Mockplate.lua", substring = "p.fill:SetColorTexture(0.78, 0.16, 0.16, 1)",
      why = STANDIN .. ": its health fill", cause = "SD-RULE" },
    { file = "modules/Elements_Indicator.lua", substring = "colors = { { 1, 1, 1, 1 }, { 1, 1, 1, 1 } }",
      why = "the bar's two color slots, filled from Style.Color on every Paint before the bar reads one",
      category = "unreachable default" },
    { file = "settings/Containers_Display.lua", substring = "if type(col) ~= \"table\" then return 1, 1, 1 end",
      why = "a dot color the load pass always stores as a table; white tints the tile's art as it is",
      category = "unreachable default" },
  },
}

-- The kit's skin-switch test (skinning-§1; every surface this addon paints, test kit revision 58,
-- the skin-defaults audit's SD-SK-RM.13): the library windows it opens, a range container's parts,
-- the preset picker, the frame picker's overlay and the Display entry's Style tiles. A container
-- follows a switch through the renderer's OnLooksChanged re-apply, which ContainerManager runs on the
-- next frame (the flush runs it now: the mock has no frame to wait for). Its HUD faces are the skin's
-- (modules/Style.lua's S.HudFont), so an owner ignoring fonts keeps them stock (scope "fonts"). A
-- part colored by its band keeps the band's color (`hold`, the owner's U-30 of 2026-11-20: the band
-- color is the range's meaning); a Fixed part follows through its `colorFromSkin` companion.
--
-- NOT DECLARED: the mock nameplate the unlocked displays stand beside (modules/Anchors_Mockplate.lua).
-- It is a preview stand-in for a client nameplate (skinning-§9 Preview stand-ins, owner ruling U-24
-- of 2026-11-20), so it keeps a nameplate's look under every skin and has nothing to move; the
-- standard's class supersedes the audit's SD-SK-RM.7 and RM.8, which asked it to follow the skin.
-- tests/test_anchors_mockplate.lua's test_preview_plate_keeps_stock_look holds that look.
local skinContainer

--- A container made for one surface, applied now; answers its renderer instance. It shows with no
--- unit (the harness has no target here), so its Paint runs on every re-apply: a hidden one paints
--- nothing.
local function skinTarget(opts)
  opts.visibility = opts.visibility or { hideNoUnit = false }
  skinContainer = NS.CM.Create("target", opts)
  NS.CM.FlushPending()
  return NS.Container.Get(skinContainer)
end
local function flush() NS.CM.FlushPending() end
local function dropTarget()
  NS.CM.Delete(skinContainer)
  NS.CM.FlushPending()
end
-- The settings harness, loaded on first need by the Style tiles' surface.
local settingsEnv
local function styleTiles()
  settingsEnv = settingsEnv or dofile("tests/settings_env.lua")
  NS.SelectContainer(NS.CM.Create("target"))
  local ctx = settingsEnv.page("containers", "Containers")
  ctx.activeSection, ctx.sectionTabs = "containers_display", { containers_display = NS.L["Dot"] }
  NS.__renderContainersPage(ctx)
  skinContainer = NS.SelectedContainer and select(2, NS.SelectedContainer()) or nil
  local tiles = ctx.rmStyleTiles or {}
  return tiles[1], tiles[2]
end
local FIXED = { r = 0.2, g = 0.4, b = 0.6, a = 1 }
-- The kit's paint recorder (tests/_kit/mock_paint.lua), for a surface whose regions must be objects
-- of their own: the base mock answers CreateTexture with the frame itself, so a W.Bar's fill Texture
-- or the frame picker's strips and label are nothing a spy can find.
local installPaint = dofile("tests/_kit/mock_paint.lua")
local restorePaint
local function recorded(build)
  return function()
    restorePaint = installPaint(mocks)
    NS.Container.__reset()
    return build()
  end
end
local function unrecord()
  NS.Container.__reset()
  if restorePaint then restorePaint() end
  restorePaint = nil
  NS.CM.RequestApply()
  NS.CM.FlushPending()
end
-- A LibSharedMedia fake answering every skin's statusbar key with a path of its own (the advice of
-- skinning-§9 from test kit revision 58): the harness loads no LibSharedMedia, so S.BarTexture
-- would paint the flat white under every skin and a bar fill that stopped following could not be
-- told from one that follows. Installed for one surface only, and this addon's own NS.GetLSM held
-- off it meanwhile (it caches the first LibSharedMedia it finds).
local savedGetLSM
local function withBarMedia()
  local Skin, map = mocks.LibStub("LibKa0s-Skin-1.0"), {}
  for _, def in ipairs(Skin:Skins()) do
    local key = Skin:ResolveSkin(def.key)["bar.texture"]
    if type(key) == "string" and key ~= "" then map[key] = "Interface\\AddOns\\RangeMasterTest\\bar\\" .. key end
  end
  mocks.__libs["LibSharedMedia-3.0"] = { Fetch = function(_, kind, key)
    return kind == "statusbar" and map[tostring(key)] or nil
  end }
  savedGetLSM = NS.GetLSM
  NS.GetLSM = function() return nil end
end
local function withoutBarMedia()
  mocks.__libs["LibSharedMedia-3.0"] = nil
  if savedGetLSM then NS.GetLSM = savedGetLSM end
  savedGetLSM = nil
end

Kit.skinSwitch = {
  owner = "RangeMaster",
  skin  = function() return mocks.LibStub("LibKa0s-Skin-1.0") end,
  surfaces = {
    { name = "the debug console", build = function()
      NS.DebugLog:Show()
      return NS.DebugLog._frameForTest
    end, reset = function() NS.DebugLog:Hide() end },
    { name = "the perf panel", build = function()
      NS.Perf.ShowPanel()
      return NS.Perf.__panel()
    end, reset = function() NS.Perf.HidePanel() end },
    -- The number in Band, the default: its face and flags follow, its color is the band's under
    -- every skin. hold = "color" is the owner's U-30 of 2026-11-20 (the band color is the range's
    -- meaning, an OVERRIDE), and the container's border and background in Band are held by the same
    -- ruling.
    { name = "a range container's number", scope = "fonts", hold = "color", build = function()
      return skinTarget({ elements = { number = { shadowFromSkin = true, outline = "@skin" } } }).elements.number.fs
    end, paint = flush, reset = dropTarget },
    -- The caption: Fixed, its companion ticked (off by default): hud.label (SD-SK-RM.3).
    { name = "a container's caption", scope = "fonts", companion = function() end, build = function()
      return skinTarget({ label = { enabled = true, colorFromSkin = true, shadowFromSkin = true, outline = "@skin" } }).caption.fs
    end, paint = flush, reset = dropTarget },
    -- The Text element, Fixed with its companion on: hud.text (SD-SK-RM.4).
    { name = "a container's Text element (Fixed)", scope = "fonts", companion = function() end, build = function()
      return skinTarget({ layout = { joinText = false },
        elements = { text = { enabled = true, colorMode = "fixed", color = FIXED, colorFromSkin = true, shadowFromSkin = true, outline = "@skin" } } }).elements.text.fs
    end, paint = flush, reset = dropTarget },
    -- The dot's art, Fixed: only its tint follows (the shape is skinning-§9's icon-shape Leave).
    { name = "a container's dot (Fixed)", companion = function() end, build = function()
      return skinTarget({ elements = { indicator = { enabled = true, colorMode = "fixed", color = FIXED, colorFromSkin = true } } })
        .elements.indicator.tex
    end, paint = flush, reset = dropTarget },
    -- The Bar dot: LibKa0s-Widgets' data bar, its fill the skin's bar texture (SD-LK-97.2, 97.3);
    -- its fill color is the band's (owner U-30), its track and edge the skin's.
    { name = "a container's Bar dot", expect = "texture", build = recorded(function()
      withBarMedia()
      local inst = skinTarget({ elements = { indicator = { enabled = true, shape = "bar" } } })
      return inst.elements.indicator.bar
    end), paint = flush, reset = function()
      dropTarget()
      unrecord()
      withoutBarMedia()
    end },
    -- The border and background in Fixed, their companions on: bar.border and bar.bg (SD-SK-RM.4).
    { name = "a container's border and background (Fixed)", companion = function() end, build = function()
      local inst = skinTarget({ frame = { border = { colorMode = "fixed", color = FIXED, alpha = 1, colorFromSkin = true },
        background = { enabled = true, colorMode = "fixed", color = FIXED, colorFromSkin = true } } })
      return inst.border.frame, inst.background
    end, paint = flush, reset = dropTarget },
    -- The spell chips: each answer in the skin's sem.good / sem.bad / sem.unknown (SD-SK-RM.10).
    { name = "a container's spell chips", build = function()
      local inst = skinTarget({ elements = { spells = { enabled = true, list = { 100, 200 } } } })
      local chips = inst.elements.spells.chips
      return chips[1], chips[2]
    end, paint = flush, reset = dropTarget },
    -- The preset picker window (settings/Presets.lua): the library's shell, text and buttons.
    { name = "the preset picker", build = function()
      return NS.ShowPresetPicker()
    end, reset = function() NS.HidePresetPicker() end },
    -- The frame picker's overlay: its outline and label in the skin's accent and face (SD-SK-RM.9).
    { name = "the frame picker's overlay", build = function()
      restorePaint = installPaint(mocks)
      NS.FramePicker.__drop()
      NS.FramePicker.Start(function() end, function() end)
      return NS.FramePicker.__overlay()
    end, reset = function()
      NS.FramePicker.Cancel("escape")
      NS.FramePicker.__drop()
      if restorePaint then restorePaint() end
      restorePaint = nil
    end },
    -- The Display entry's Style tiles: the skin's input colors with the Scope cleared, stock while
    -- the owner ignores its settings panel (scope "panel", SD-SK-RM.12).
    { name = "the Dot tab's Style tiles", scope = "panel", build = styleTiles, reset = function()
      if skinContainer then NS.CM.Delete(skinContainer) end
      NS.SelectContainer(nil)
      NS.CM.FlushPending()
    end },
  },
}

Kit.run{
  dir = "tests/",
  suites = {
    "test_loadorder",
    "test_schema",
    "test_database",
    "test_bandsets",
    "test_bandset_choice",
    "test_container_manager",
    "test_presets",
    "test_number_format",
    "test_container_render",
    "test_anchors_screen",
    "test_anchors_frame",
    "test_anchors_nameplate",
    "test_anchors_cursor",
    "test_anchors_mockplate",
    "test_visibility",
    "test_sounds",
    "test_compat",
    "test_range",
    "test_ticker",
    "test_envsetup",
    "test_coresetup",
    "test_mediasetup",
    "test_debuglog",
    "test_slash",
    "test_slashgate",
    "test_perf",
    "test_bus",
    "test_layers",
    "test_launcher",
    "test_launcher_skin_entry",
    "test_modes",
    "test_sim_start_panel",
    "test_sample_names",
    "test_optionssetup",
    "test_realpages",
    "test_settings_containers",
    "test_settings_bandsets",
    "test_settings_bandset_dialogs",
    "test_settings_presets",
    "test_skinsetup",
    "test_skin_picker",
    "test_skin_picker_preview",
    "test_glyphs",
    "test_locale",
    "test_docs",
    { name = "test_prose", dir = "tests/_kit/" },
    "test_surface_parity",
    "test_vendor_sync",
    "test_lintconfig",
    "test_events",
    "test_disabled",
    "test_diagnostics",
    { name = "test_diagnostics_contract", dir = "tests/_kit/" },
    { name = "test_eol", dir = "tests/_kit/" },
    { name = "test_layout_cap", dir = "tests/_kit/" },
    { name = "test_lizard_sighted", dir = "tests/_kit/" },
    { name = "test_skin_values", dir = "tests/_kit/" },
    { name = "test_skin_switch", dir = "tests/_kit/" },
    { name = "test_client_globals", dir = "tests/_kit/" },
  },
}
