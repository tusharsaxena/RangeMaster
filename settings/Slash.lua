local _, NS = ...
-- settings/Slash.lua — NS.COMMANDS and the LibKa0s-Slash-1.0 descriptor (slash-commands).
--
-- The dispatcher, the help renderer, the key/value formatters, the list builder and the type-aware
-- value parser are the library's. What stays here is what is genuinely ours: the ordered verb table
-- and the host verbs that reach into this addon's own state.
--
-- NS.COMMANDS is passed INTO the library rather than owned by it: the landing page renders the same
-- table (settings/About.lua), and a library that owned it would force the options library to consume
-- this one. Entries are positional triples {name, desc, fn}; a table of named fields is invisible to
-- the library and every verb becomes unknown.
NS.Slash = NS.Slash or {}
local Sl = NS.Slash

local L = NS.L
local print = NS.Print
-- The formatting printer, captured the same way: this file loads after core/RangeMaster.lua has
-- reclaimed both from AceConsole. A whole sentence goes in as one L[...] key with %s slots.
local printf = NS.Printf

local SlashLib = LibStub and LibStub("LibKa0s-Slash-1.0", true)
-- The refusal line's format, byte for byte the library's DISABLED_LINE_FORMAT (slash-commands-§7), for
-- the library-absent stub. Published in BOTH builds so tests/test_surface_parity.lua compares it
-- against the live major with Kit.assertLibraryConstant: the copy that could drift is falsifiable.
local STUB_DISABLED_LINE_FORMAT = "%s is disabled \226\128\148 enable it with |cFFFFFF00%s|r"
Sl.__STUB_DISABLED_LINE_FORMAT = STUB_DISABLED_LINE_FORMAT
-- Built at the bottom, once NS.COMMANDS exists; every handler reaches it at CALL time.
local cli

local runEnabled, runResetAll, runResetPosition, runLock, runTest, runSim, runDebug, runPerf

NS.COMMANDS = {
    {"help",          L["List available commands"],
        function() cli:PrintHelp() end},
    {"config",        L["Open the settings panel"],
        function() NS.OpenOptionsPanel() end},
    -- The reserved skin verb (skinning-§3): a feature verb, refused while disabled.
    {"skin",          L["Choose a skin: open the skin picker"],
        function() NS.RunSkinVerb() end},
    {"enable",        L["Turn Range Master on"],
        function() runEnabled(true) end},
    {"disable",       L["Turn Range Master off \226\128\148 /rm enable turns it back on"],
        function() runEnabled(false) end},
    {"list",          L["List every setting and its current value"],
        function() cli:CliList() end},
    {"get",           L["Print a setting's current value \226\128\148 /rm get path"],
        function(rest) cli:CliGet(rest) end},
    {"set",           L["Set a setting \226\128\148 /rm set path value (try /rm list)"],
        function(rest) cli:CliSet(rest) end},
    {"reset",         L["Reset one setting to its default \226\128\148 /rm reset path"],
        function(rest) cli:CliReset(rest) end},
    {"resetall",      L["Reset every setting to defaults"],
        function() runResetAll() end},
    -- The library's verb (LibKa0s-Slash minor 17): bare lists the profiles, a name switches to an
    -- EXISTING one, an unknown name is refused with the list and never created.
    {"profile",       L["List profiles, or switch to one: profile <name>"],
        function(rest) cli:CliProfile(rest) end},
    {"lock",          L["Lock every range display in place"],
        function() runLock(true) end},
    {"unlock",        L["Unlock the range displays so they can be dragged"],
        function() runLock(false) end},
    {"resetposition", L["Move every range display back to its default position"],
        function() runResetPosition() end},
    {"test",          L["Toggle Test mode: placeholder ranges on every display \226\128\148 /rm test [on|off]"],
        function(rest) runTest(rest) end},
    {"sim",           L["Toggle Sim mode: a simulated target walks through your range bands \226\128\148 /rm sim [on|off]"],
        function(rest) runSim(rest) end},
    {"debug",         L["Toggle the debug console \226\128\148 on/off enable/disable logging"],
        function(rest) runDebug(rest) end},
    {"diagnostics",   L["Write a diagnostics report to the debug console"],
        function() NS.DebugLog:RunDiagnostics() end},
    {"perf",          L["Measure performance \226\128\148 try /rm perf for the workflow"],
        function(rest) runPerf(rest) end},
    {"version",       L["Print the addon version"],
        function() printf("v%s", NS.Version()) end},
}

-- ---------------------------------------------------------------------------
-- The disabled gate (slash-commands-§2, §7)
-- ---------------------------------------------------------------------------
--
-- THE GATE IS THE LIBRARY'S; the host's share is three descriptor fields at the bottom: `isEnabled`,
-- `brandName` and `liveVerbs`. Everything in the library's LIVE_VERBS keeps answering while the addon
-- is off (help, config, version, enable, disable, debug, perf and the schema CLI, and the bare /rm,
-- which opens the panel), plus `diagnostics` and `profile` below. This addon's own feature verbs are
-- refused on one line, the library's DisabledLine(). The refusal is not the stand-down: the addon
-- being genuinely inert is core/LifecycleSetup.lua's.

--- The verbs that keep answering: the library's reserved set, named rather than copied, plus
--- `diagnostics` (a diagnostic, most wanted when something misbehaves) and `profile` (a switch is how
--- a disabled player reaches a profile where the addon is on).
local function liveVerbs()
    local out = { "diagnostics", "profile" }
    for _, verb in ipairs((SlashLib and SlashLib.LIVE_VERBS) or {
        "help", "config", "version", "enable", "disable", "debug", "perf",
        "get", "set", "list", "reset", "resetall",
    }) do
        out[#out + 1] = verb
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Host verbs
-- ---------------------------------------------------------------------------

local function firstWord(rest)
    return ((rest or ""):match("^%s*(%S*)") or ""):lower()
end

--- Confirm a host verb's write the way `/rm set` confirms one (slash-commands-§5): the stored value
--- read back through the library's own CliGet. The degraded stub has no formatter, so there the
--- verb's own sentence (`prose`) is the confirmation.
local function echo(path, prose)
    if NS.RefreshOptionsPanel then NS.RefreshOptionsPanel() end
    if SlashLib and SlashLib.FormatKV then return cli:CliGet(path) end
    print(prose)
end

-- The master switch, through the same seam as General → Master controls' "Enable Range Master" and
-- `/rm set enabled`. The latch is synced HERE as well as in the row's onChange: idempotent on the live
-- path, and required without LibKa0s, where the path is a writeThrough one with no row.
function runEnabled(on)
    local ok, err = NS.SetByPath("enabled", on)
    if ok == false then return print(err) end
    NS.SyncEnabledHold()
    echo("enabled", on and L["Range Master enabled"] or L["Range Master disabled \226\128\148 /rm enable turns it back on"])
end

function runResetAll()
    -- The acknowledgment lives INSIDE the guard: on a load where settings/OptionsSetup.lua never ran
    -- there is nothing to delegate to, and printing it anyway would claim work that did not happen.
    if NS.Helpers and NS.Helpers.RestoreAllDefaults then
        NS.Helpers.RestoreAllDefaults()
        print(L["All settings reset to defaults."])
    else
        print(L["Cannot reset settings \226\128\148 the settings helpers failed to load."])
    end
end

function runResetPosition()
    local n = NS.ResetPositions()
    printf(L["%s range display position(s) reset"], n)
end

function runLock(locked)
    local ok, err = NS.SetByPath("locked", locked)
    if ok == false then return print(err) end
    echo("locked", locked and L["Range displays locked"] or L["Range displays unlocked \226\128\148 drag one by its handle"])
end

local ON_OFF = { on = true, off = false }

--- Read `[on|off]`: the wanted state, or the toggle of `current` for a bare verb, or nil plus the
--- usage line for any other word.
local function readOnOff(rest, current, usage)
    local word = firstWord(rest)
    local want = ON_OFF[word]
    if want ~= nil then return want end
    if word ~= "" then print(usage) return nil end
    return not current
end

-- `/rm test` toggles; `on` / `off` set. Through NS.SetTestMode, the one writer the Master controls
-- checkbox, the launcher and the skin picker's eye use, which refuses a start in combat.
function runTest(rest)
    local want = readOnOff(rest, NS.IsTestMode(), L["Usage: /rm test [on|off]"])
    if want == nil then return end
    if NS.SetTestMode(want, "/rm test") then
        print(want and L["Test mode on \226\128\148 every range display shows placeholder ranges"] or L["Test mode off"])
    end
end

-- `/rm sim` toggles; `on` / `off` set. Through NS.SetSimMode, the one writer of the mode. Any other
-- word is the simulator's own verb (`step`, `pause`, `resume`, `restart`, `stop`, `status`, `panel`,
-- `start sweep`; modules/Sim.lua), so the commands its step panel shows are the ones typed here.
function runSim(rest)
    local word = firstWord(rest)
    if word ~= "" and ON_OFF[word] == nil then return NS.Sim.RunVerb(rest) end
    local want = readOnOff(rest, NS.IsSimMode(), L["Usage: /rm sim [on|off]"])
    if want == nil then return end
    if NS.SetSimMode(want, "/rm sim") then
        print(want and L["Sim mode on \226\128\148 a simulated target walks through your range bands"] or L["Sim mode off"])
    end
end

-- /rm debug             toggles the console WINDOW (the logging flag is untouched).
-- /rm debug on|off      enables or disables session logging through the one SetEnabled seam.
-- /rm debug diagnostics writes the report, the same as /rm diagnostics; tested FIRST, so it never falls
--                       through to the toggle. There is no `diag` alias (debug-logging-§14).
function runDebug(rest)
    if not NS.DebugLog:DebugVerb(rest) then NS.DebugLog:Toggle() end
end

-- `perf` is a reserved verb the ADDON registers (performance-§4); the harness returns lines and this
-- prints them with the addon's own tag.
function runPerf(rest)
    for _, line in ipairs(NS.Perf.OnCommand(rest or "")) do print(line) end
end

-- ---------------------------------------------------------------------------
-- The degradation stub
-- ---------------------------------------------------------------------------
--
-- Degrade, never error: `/rm` is registered unconditionally, so something must answer it. The host
-- verbs keep working; the schema verbs name the missing library instead of going quiet. A help row
-- prints plainly as "/rm verb  desc": the stub MUST NOT copy the library's FormatRow, parser or
-- `key = value` shape (slash-commands-§1).
if not SlashLib then
    SlashLib = {}

    function SlashLib.New(_, d)
        local stub = { SetRowAnnotator = function() end }
        local function absent(verb)
            return function() printf(L["%s is unavailable: the LibKa0s library did not load."], "/rm " .. verb) end
        end
        for _, verb in ipairs({ "List", "Get", "Set", "Reset", "ResetAll", "Profile" }) do
            stub["Cli" .. verb] = absent(verb:lower())
        end
        local profileAbsent = absent("profile")
        stub.ProfileSwitch = function() profileAbsent(); return false end
        stub.LandingRows = function()
            local out = {}
            for _, e in ipairs(d.commands) do
                out[#out + 1] = "/rm " .. e[1] .. "  " .. e[2]
            end
            return out
        end
        stub.PrintHelp = function()
            printf(L["v%s \226\128\148 slash commands"], d.version())
            for _, row in ipairs(stub.LandingRows()) do printf("  %s", row) end
        end
        local function verb(name)
            for _, e in ipairs(d.commands) do
                if e[1] == name then return e end
            end
        end
        local live = {}
        for _, name in ipairs(d.liveVerbs or {}) do live[name] = true end
        stub.DisabledLine = function()
            return STUB_DISABLED_LINE_FORMAT:format(tostring(d.brandName or d.slash), d.slash .. " enable")
        end
        stub.OnSlash = function(_, msg)
            local raw = (msg or ""):match("^%s*(.-)%s*$") or ""
            -- The bare command opens the panel in EITHER state: it is where the addon is switched
            -- back on from.
            if raw == "" then
                local config = verb("config")
                if config then return config[3]("") end
                return stub.PrintHelp()
            end
            local cmd, rest = raw:match("^(%S+)%s*(.*)$")
            cmd = (cmd or ""):lower()
            cmd = (d.aliases or {})[cmd] or cmd
            local e = verb(cmd)
            local down = type(d.isEnabled) == "function" and not d.isEnabled()
            if down and e and not live[cmd] then return print(stub.DisabledLine()) end
            if e then return e[3](rest or "") end
            printf(L["Unknown command '%s'"], cmd)
            stub.PrintHelp()
        end
        return stub
    end
end

-- ---------------------------------------------------------------------------
-- The dispatcher
-- ---------------------------------------------------------------------------

cli = SlashLib:New({
    slash        = "/rm",
    slashAliases = { "/rangemaster" },
    commands     = NS.COMMANDS,
    aliases      = { options = "config" },

    -- The disabled gate. core/LifecycleSetup.lua's one enabled predicate, asked at DISPATCH time.
    isEnabled    = NS.EnabledStored,
    -- The brand in plain text, the same string the launcher's `label` carries (launcher-§1).
    brandName    = NS.Constants.BRAND,
    liveVerbs    = liveVerbs(),
    -- The profile store the `profile` verb reads, asked at CALL time (NS.db is built later).
    profiles     = function() return NS.db end,

    print   = function(line) print(line) end,
    version = function() return NS.Version() end,
    -- The gated sink (debug-logging-§4): every refusal the dispatcher decides writes its own `[Cmd]`
    -- line through it (Slash minor 18); no verb here logs a second one.
    debug   = function(tag, message) NS.Debug(tag, "%s", message) end,

    -- The schema seams: SetByPath, so a CLI change takes the path a panel change takes.
    get          = function(path) return NS.GetSetting(path) end,
    set          = function(path, v)
        local ok, err, why = NS.SetByPath(path, v)
        if NS.RefreshOptionsPanel then NS.RefreshOptionsPanel() end
        return ok, err, why
    end,
    findRow      = function(path) return NS.FindSchemaRow(path) end,
    applyDefault = function(row)
        local ok = NS.ApplyDefault(row)
        if NS.RefreshOptionsPanel then NS.RefreshOptionsPanel() end
        return ok
    end,
    allRows      = function() return NS.Schema end,
    groupKey     = function(row) return row.page end,
    -- The bulk pair (Slash minor 8): CliResetAll writes muted and logs one `[Set] reset all: N rows`.
    bulkBegin    = function(...) NS.Bulk.Begin(...) end,
    bulkEnd      = function(...) NS.Bulk.End(...) end,
})

-- Published for introspection (read by tests/run.lua and tests/test_surface_parity.lua).
Sl.__cli = cli

--- The one refusal line, built by the library from `brandName` and `slash`.
function Sl:DisabledLine() return cli:DisabledLine() end

--- The command list the landing page renders: the same rows `/rm help` prints, without the indent.
function Sl:LandingRows() return cli:LandingRows() end

function Sl:OnSlash(msg) cli:OnSlash(msg) end

-- THE LAUNCHER MENU'S AND THE MASTER CONTROLS BOXES' HANDLERS (launcher-§2): each is the verb's OWN
-- handler, so the menu and the box confirm, refuse and print exactly as the slash command does.
function Sl.ToggleTestMode() runTest("") end
function Sl.ToggleSimMode() runSim("") end

function Sl:Register()
    NS.addon:RegisterChatCommand("rm", function(msg) Sl:OnSlash(msg) end)
    NS.addon:RegisterChatCommand("rangemaster", function(msg) Sl:OnSlash(msg) end)
end
