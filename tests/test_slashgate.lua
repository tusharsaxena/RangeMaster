local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- settings/Slash.lua: /rm enable, /rm disable and the disabled gate, the list of verbs that still
-- answer while the addon is off (slash-commands-§2).
--
-- The helpers below are repeated rather than exported, because a suite file returns nothing the
-- runner reads.

-- Same capture seam as test_slash.lua: Slash.lua bound `local print = NS.Print` at load, so the
-- only interceptable point is the chat frame's AddMessage sink.
local function capture(fn)
  local out = {}
  local cf = T.mocks.DEFAULT_CHAT_FRAME
  local old = rawget(cf, "AddMessage")
  cf.AddMessage = function(_, msg) out[#out + 1] = msg end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err) end
  return out
end

local function stripColor(s)
  return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Run a slash line and return its plain-text output lines.
local function slash(line)
  local out = capture(function() NS.Slash:OnSlash(line) end)
  local plain = {}
  for i, l in ipairs(out) do plain[i] = stripColor(l) end
  return plain
end

local function joined(lines) return table.concat(lines, "\n") end

local function contains(lines, needle)
  return joined(lines):find(needle, 1, true) ~= nil
end

-- Leave the DB on the Default profile whatever a test did.
local function backToDefault()
  if NS.db and NS.db.SetProfile then NS.db:SetProfile("Default") end
  T.mocks.__fireTimers()
end

-- Make sure `name` is a stored profile without leaving it active. AceDB's SetProfile creates a
-- missing profile, which is exactly what the verb itself must never do, so the setup does it here.
local function ensureProfile(name)
  NS.db:SetProfile(name)
  backToDefault()
end

-- ── /rm enable | /rm disable (slash-commands-§2) ────────────────────────────────────

test("/rm enable and /rm disable write the Enable row's OWN path, through the one seam", function()
  -- THE RESERVED PAIR, and they are ALIASES rather than a second switch. The failure this case
  -- exists to prevent is not "the verb does nothing" — it is a verb that keeps its own flag beside
  -- the checkbox, so the panel says on and the addon is off (or the other way round) and neither
  -- surface is wrong about itself.
  --
  -- Asserted at the SEAM, not at the value: a handler that wrote `db.profile.enabled` directly
  -- would leave `enabled` reading the same and silently skip the row's onChange — NS.SyncEnabledHold
  -- (settings/General.lua) — so the addon would never stand down after `/rm disable`.
  --
  -- red under: a second stored key; a session flag; a handler that writes the profile itself; a
  -- verb renamed or re-used for enabling a module or a unit (that is `/rm toggle`'s job).
  local real, seen = NS.SetByPath, {}
  NS.SetByPath = function(path, value)
    seen[#seen + 1] = { path = path, value = value }
    return real(path, value)
  end
  local ok, err = pcall(function()
    slash("disable")
    slash("enable")
  end)
  NS.SetByPath = real
  assertTrue(ok, tostring(err))

  assertEqual(#seen, 2, "one write per verb, no more")
  assertEqual(seen[1].path, "enabled", "/rm disable writes the Enable row's own path")
  assertEqual(seen[1].value, false)
  assertEqual(seen[2].path, "enabled", "/rm enable writes the same path")
  assertEqual(seen[2].value, true)
  assertTrue(NS.GetSetting("enabled"), "and the addon is back on")
end)

test("/rm disable echoes the stored value in the set shape, and /rm enable undoes it", function()
  -- slash-commands-§5's single-line `path = value` form, read back from the STORE rather than from
  -- the argument, so a coerced or refused write is what the player is told about.
  local out = slash("disable")
  assertFalse(NS.GetSetting("enabled"), "the addon is off")
  assertTrue(contains(out, "enabled = false"), joined(out))

  out = slash("enable")
  assertTrue(NS.GetSetting("enabled"), "and on again")
  assertTrue(contains(out, "enabled = true"), joined(out))
end)

test("the pair is never one-way: the dispatcher still answers while the addon is disabled", function()
  -- slash-commands-§2 makes this a MUST, and the reason is blunt: an addon that unregisters its
  -- chat command or drops its COMMANDS table when disabled has built a switch that only goes one
  -- way — the player turns it off, and the verb that turns it back on no longer exists.
  --
  -- The dispatcher and the settings registration are SETUP, not features: they come up on load in
  -- either state. In this addon `enabled` moves the stand-down latch's `disabled` hold, and
  -- StandDown takes down only the features — the unit-event frames, the AceEvent registrations and
  -- the bus — never the dispatcher, which is what makes that true here.
  --
  -- red under: a `return` guard on `enabled` anywhere in Sl:OnSlash or the COMMANDS handlers; an
  -- OnInitialize that registers the chat command conditionally; an `enable` verb that needs the
  -- panel, which is the one place the player was trying not to go.
  slash("disable")
  assertFalse(NS.GetSetting("enabled"), "precondition: the addon is off")

  -- A bare /rm is the `config` verb (slash-commands-\194\1674), and it has to keep being that with
  -- the addon off: it is the route to the checkbox the verbs alias.
  local real, opened = NS.OpenOptionsPanel, 0
  NS.OpenOptionsPanel = function() opened = opened + 1 end
  local ok, err = pcall(slash, "")
  NS.OpenOptionsPanel = real
  assertTrue(ok, "a bare /rm raised while disabled: " .. tostring(err))
  assertEqual(opened, 1, "a bare /rm still opens the settings panel while disabled")

  local help = slash("help")
  assertTrue(contains(help, "/rm enable"), "`/rm help` still lists the way back: " .. joined(help))
  assertTrue(contains(help, "/rm config"), joined(help))

  assertTrue(contains(slash("version"), "v"), "`/rm version` still answers")

  local out = slash("enable")
  assertTrue(NS.GetSetting("enabled"), "and `/rm enable` itself works from the off state")
  assertTrue(contains(out, "enabled = true"), joined(out))
end)

test("enable and disable hold no state of their own", function()
  -- The other direction of the alias rule: writing the path by any OTHER route must move what the
  -- verbs report, because there is only one record. Written here through the row's long name, which
  -- slash-commands-§2 says an addon MAY accept as the same write.
  slash("set enabled false")
  assertFalse(NS.GetSetting("enabled"))
  assertTrue(contains(slash("get enabled"), "enabled = false"))

  NS.Helpers.RestoreDefaults("general")
  assertTrue(NS.GetSetting("enabled"), "a page Defaults press moves the same one record")

  slash("enable")
end)


-- ── the disabled gate (slash-commands-§2) ──────────────────────────────────────────────────────
--
-- A disabled addon answers a feature verb instead of acting on it, on ONE tagged line that names
-- `/rm enable`. The suite above pins the other half of §2 — that the dispatcher SURVIVES the
-- disabled state — and these two rules pull against each other, which is why the live set is
-- asserted as hard as the refusal: read literally, "refuse while disabled" takes the whole command
-- surface down with it, `enable` included, and the pair becomes one-way again.


-- The collection's one refusal line, not this addon's: LibKa0s-Slash-1.0 owns the wording
-- (`lib.DISABLED_LINE_FORMAT`) so eleven addons cannot each spell it differently. Matched on the
-- brand and the shape rather than character-for-character, which is what lets the library re-word
-- the sentence around them without eleven suites going red over a comma.
local REFUSAL = NS.Constants.BRAND .. " is disabled"

--- Run one verb with the addon off, with the panel-open call stubbed (a live `config` would
--- otherwise reach the real Settings API mid-suite). Re-disables first, because two of the live
--- verbs — `enable` and `resetall` — turn the addon back on as their whole job.
local function slashWhileDisabled(verb)
  NS.SetByPath("enabled", false)
  local real = NS.OpenOptionsPanel
  NS.OpenOptionsPanel = function() end
  local out = slash(verb)
  NS.OpenOptionsPanel = real
  return out
end

test("a refused `unlock` leaves the lock exactly where it was", function()
  -- `lock` / `unlock` drive the addon's PREVIEW — the unlocked view is this addon's test mode
  -- (options-ui-§15's exemption) — so they are feature verbs, and the launcher menu's Locked entry
  -- runs these same handlers. Asserted at the SEAM as well as the value: the refusal must not reach
  -- NS.SetByPath at all, or the row's onChange would fire its APPEARANCE and REPAINT for a write
  -- that was refused.
  NS.SetByPath("locked", true)
  local real, seen = NS.SetByPath, 0
  NS.SetByPath = function(path, value)
    if path == "locked" then seen = seen + 1 end
    return real(path, value)
  end
  local out = slashWhileDisabled("unlock")
  NS.SetByPath = real

  assertTrue(contains(out, REFUSAL), joined(out))
  assertEqual(seen, 0, "a refused verb must not reach the write seam")
  assertTrue(NS.GetSetting("locked"), "the displays are still locked")

  NS.SetByPath("enabled", true)
end)

test("a refused `update` publishes nothing on the bus", function()
  -- `update` exists to force a repaint, so "did not act" is exactly "did not publish".
  --
  -- The spy goes on AFTER the addon is disabled: writing `enabled` is itself a publish (the row's
  -- onChange moves the latch, whose StandDown publishes VISIBILITY), and catching the setup would
  -- read as the verb acting.
  NS.SetByPath("enabled", false)
  local real, sent = NS.bus.SendMessage, {}
  NS.bus.SendMessage = function(self, msg, ...)
    sent[#sent + 1] = msg
    return real(self, msg, ...)
  end
  local out = slash("update")
  NS.bus.SendMessage = real

  assertTrue(contains(out, REFUSAL), joined(out))
  assertEqual(#sent, 0, "a refused verb published: " .. table.concat(sent, ", "))

  NS.SetByPath("enabled", true)
end)

test("/rm profile <name> switches while the addon is disabled", function()
  -- `profile` is on this addon's liveVerbs (settings/Slash.lua), so the bare-name form answers with
  -- the addon off: the player who disabled it to get out from under a profile can switch away.
  -- red under: `profile` dropped from liveVerbs, which answers the refusal line instead.
  ensureProfile("Alt")
  local out = slashWhileDisabled("profile Alt")
  local current = NS.db:GetCurrentProfile()
  backToDefault()
  NS.SetByPath("enabled", true)
  assertFalse(contains(out, REFUSAL), joined(out))
  assertEqual(current, "Alt", joined(out))
  assertTrue(contains(out, "Switched to profile 'Alt'."), joined(out))
end)
