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

-- The kit's typed-value gate (skinning-§1): no allowance of this addon's own.
Kit.skinValues = {}

-- The kit's skin-switch test (skinning-§1): the surfaces this addon draws through the skin: the
-- library windows it opens, and a range container's number, whose HUD face is the skin's
-- (modules/Style.lua's S.HudFont) and follows a switch through the renderer's OnLooksChanged
-- re-apply, which ContainerManager runs on the next frame. Its colors are the band set's, never
-- the skin's, so the face is what moves, and an owner
-- ignoring fonts keeps it stock (scope "fonts").
local skinContainer
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
    { name = "a range container's number", scope = "fonts", build = function()
      skinContainer = NS.CM.Create("target")
      NS.CM.FlushPending()
      return NS.Container.Get(skinContainer).elements.number.fs
    end, paint = function()
      -- The skin's OnLooksChanged asks ContainerManager for an apply on the next frame (held
      -- through combat); the mock has no frame to wait for, so the flush runs it now.
      NS.CM.FlushPending()
    end, reset = function()
      NS.CM.Delete(skinContainer)
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
    "test_optionssetup",
    "test_realpages",
    "test_settings_containers",
    "test_settings_bandsets",
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
