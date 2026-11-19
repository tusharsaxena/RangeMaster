-- tests/test_container_manager.lua — the container registry's one runtime writer
-- (modules/ContainerManager.lua, NS.CM): create, delete, duplicate, rename, unique names, copy
-- settings, the snapshot pair, and the coalesced, combat-deferred apply. The v0.1.0 plan, Task 4;
-- design spec sections 5.2 and 5.3.
--
-- Every case runs on a FRESH profile (the db swapped for a bare { profile, global } pair the load
-- pass prepares, as a first login would) with the apply queue emptied before and after, and the real
-- db, the combat read and the class put back whether or not the case raised.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local CM = NS.CM

--- Run `body(profile)` on a freshly prepared profile with an empty apply queue.
local function withFreshProfile(body, classToken)
  local savedDb, savedClass, savedCombat = NS.db, M.__context.classToken, M.InCombatLockdown
  if classToken then M.__context.classToken = classToken end
  local p = {}
  NS.db = { profile = p, global = savedDb.global }
  CM.__reset()
  local ok, err = pcall(function()
    NS.Database.PrepareProfile(p)
    body(p)
  end)
  CM.__reset()
  NS.db = savedDb
  M.__context.classToken = savedClass
  M.InCombatLockdown = savedCombat
  if not ok then error(err, 0) end
end

--- Count CONTAINERS_CHANGED sends while `fn` runs.
local function countChanged(fn)
  local target, n = NS.NewBusTarget(), 0
  target:RegisterMessage(NS.MSG.CONTAINERS_CHANGED, function() n = n + 1 end)
  local ok, err = pcall(fn)
  target:UnregisterMessage(NS.MSG.CONTAINERS_CHANGED)
  if not ok then error(err, 0) end
  return n
end

--- Run the queued coalescing timer, as the next frame would. Answers whether one was queued.
local function nextFrame()
  local t = CM.__flushTimer()
  if not t then return false end
  t.fn()
  return true
end

--- Where the kit's timer queue ends now, so queuedFlushes can count what is armed after it.
local function timerMark() return #M.__timers end

--- How many timers armed since `mark` are still live: every one of them, not only the handle the
--- registry holds, so a write that arms a second timer and drops the first is counted.
local function queuedFlushes(mark)
  local live, n = {}, 0
  for _, handle in ipairs(M.__timers()) do live[handle] = true end
  for i = mark + 1, #M.__timers do
    if live[M.__timers[i]] then n = n + 1 end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- CRUD
-- ---------------------------------------------------------------------------

test("cm: test_create_defaults_unit_target — a bare Create is a target container on the default set", function()
  withFreshProfile(function(p)
    local id = CM.Create()
    assertEqual(type(id), "number")
    local c = CM.Get(id)
    assertEqual(c.unit, "target")
    assertEqual(c.name, "Target", "named after its unit")
    assertEqual(c.bandSet, NS.BandSets.DefaultId(), "on the default band set")
    assertNil(c.bandSetFriendly)
    assertEqual(c.anchor.mode, "screen")
    assertTrue(c.enabled)
    assertEqual(p.containerOrder[#p.containerOrder], id, "appended to the order")
    assertTrue(c ~= NS.CONTAINER_TEMPLATE and c.elements ~= NS.CONTAINER_TEMPLATE.elements,
      "deep-copied from the template")
    assertEqual(CM.List()[1], id)
  end)
end)

test("cm: Create stores no spell list (the chips resolve to the class seeds) and takes a unit and opts", function()
  withFreshProfile(function()
    local id = CM.Create("focus", { name = "My focus", anchor = { mode = "cursor" },
      elements = { number = { format = "max" } } })
    local c = CM.Get(id)
    assertEqual(c.unit, "focus")
    assertEqual(c.name, "My focus")
    assertEqual(c.anchor.mode, "cursor")
    assertEqual(c.anchor.point, "CENTER", "opts merge over the template, keeping what they do not name")
    assertEqual(c.elements.number.format, "max")
    assertTrue(c.elements.number.enabled, "a merged section keeps its other keys")
    local seeds = NS.SpellSeeds[NS.Compat.ClientKey()][NS.Compat.PlayerClass()]
    assertEqual(#c.elements.spells.list, 0, "no list is stored until the player chooses one")
    assertEqual(#CM.SpellChips(c), #seeds.chips, "the chips resolve to the class's seeds")
    assertEqual(CM.SpellChips(c)[1], seeds.chips[1])
    assertNil(CM.Create("raid1"), "a unit RangeMaster does not watch is refused")
  end, "MAGE")
end)

test("cm: test_unique_name_suffix — a taken name gets the next free number", function()
  withFreshProfile(function()
    local a, b = CM.Create("target"), CM.Create("target")
    assertEqual(CM.Get(a).name, "Target")
    assertEqual(CM.Get(b).name, "Target 2")
    assertEqual(CM.UniqueName("Target"), "Target 3")
    assertEqual(CM.UniqueName("target"), "target 3", "names that differ only in case are taken")
    assertEqual(CM.UniqueName("Focus"), "Focus", "a free name is kept")
    assertEqual(CM.UniqueName("  "), "Container", "a blank base reads Container")
  end)
end)

test("cm: Rename trims, keeps names unique and refuses a blank name or an unknown id", function()
  withFreshProfile(function()
    local a, b = CM.Create("target"), CM.Create("focus")
    assertTrue(CM.Rename(a, "  Main  "))
    assertEqual(CM.Get(a).name, "Main")
    assertTrue(CM.Rename(b, "main"))
    assertEqual(CM.Get(b).name, "main 2", "a rename onto a taken name gets a suffix")
    assertTrue(CM.Rename(a, "Main"), "renaming to its own name is not a clash")
    assertEqual(CM.Get(a).name, "Main")
    assertFalse(CM.Rename(a, "   "))
    assertFalse(CM.Rename(999, "x"))
  end)
end)

test("cm: SetField stores elements.order only as an arrangement of the four elements, each once", function()
  withFreshProfile(function()
    local id = CM.Create("target")
    local function order() return table.concat(CM.Get(id).elements.order, ",") end
    assertTrue(CM.SetField(id, "elements.order", { "number", "text", "spells", "indicator" }))
    assertEqual(order(), "number,text,spells,indicator", "a full arrangement is stored as given")
    assertFalse(CM.SetField(id, "elements.order", { "number", "number", "text", "spells" }),
      "a name twice is refused")
    assertFalse(CM.SetField(id, "elements.order", { "number", "text", "spells" }), "a missing element is refused")
    assertFalse(CM.SetField(id, "elements.order", { "number", "text", "spells", "bogus" }),
      "a name that is no element is refused")
    assertFalse(CM.SetField(id, "elements.order", { number = true }), "a map is refused")
    assertEqual(order(), "number,text,spells,indicator", "a refusal stores nothing")
  end)
end)

test("cm: test_delete_removes_from_order — the member and its order slot both go", function()
  withFreshProfile(function(p)
    local a, b, c = CM.Create("target"), CM.Create("focus"), CM.Create("pet")
    assertTrue(CM.Delete(b))
    assertNil(p.containers[b])
    assertEqual(#p.containerOrder, 2)
    assertEqual(p.containerOrder[1], a)
    assertEqual(p.containerOrder[2], c)
    assertFalse(CM.Delete(b), "an id already gone is refused")
    assertNil(CM.Get(b))
    local d = CM.Create("target")
    assertTrue(d > c, "ids are never reused")
  end)
end)

test("cm: test_duplicate_deep_copy — a duplicate is its own tables, after its source", function()
  withFreshProfile(function(p)
    local a, z = CM.Create("target"), CM.Create("pet")
    CM.Get(a).elements.text.enabled = true
    local d = CM.Duplicate(a)
    local src, dup = CM.Get(a), CM.Get(d)
    assertTrue(dup ~= src)
    assertTrue(dup.elements ~= src.elements and dup.elements.spells.list ~= src.elements.spells.list,
      "nested tables are copies")
    assertTrue(dup.elements.text.enabled, "settings travel")
    assertEqual(dup.name, "Target copy")
    assertEqual(dup.anchor.x, src.anchor.x + 20, "a screen duplicate is offset")
    assertEqual(p.containerOrder[2], d, "placed right after its source")
    assertEqual(p.containerOrder[3], z)
    dup.elements.text.enabled = false
    assertTrue(src.elements.text.enabled, "editing the copy leaves the source alone")
    assertEqual(CM.Get(CM.Duplicate(a)).name, "Target copy 2")
    assertNil(CM.Duplicate(999))
  end)
end)

test("cm: CopySettings copies the named sections deep, and never identity or placement", function()
  withFreshProfile(function()
    local a, b = CM.Create("target"), CM.Create("focus")
    local src = CM.Get(a)
    src.layout.direction, src.visibility.combat, src.anchor.mode = "column", "in", "cursor"
    src.label.enabled, src.label.position = true, "left"
    assertTrue(CM.CopySettings(a, b))
    local dst = CM.Get(b)
    assertEqual(dst.layout.direction, "column")
    assertTrue(dst.label.enabled and dst.label.position == "left", "the caption is copied (plan 2026-11-19 M7)")
    assertEqual(dst.visibility.combat, "in")
    assertTrue(dst.layout ~= src.layout, "deep-copied")
    assertEqual(dst.unit, "focus", "the unit is the container's own")
    assertEqual(dst.name, "Focus", "the name too")
    assertEqual(dst.anchor.mode, "screen", "placement is not a setting to copy")
    src.sounds.enabled = true
    src.layout.direction = "row"
    assertTrue(CM.CopySettings(a, b, { "sounds" }))
    assertTrue(dst.sounds.enabled, "a named section is copied")
    assertEqual(dst.layout.direction, "column", "an unnamed one is not")
    assertFalse(CM.CopySettings(a, a), "a container never copies itself")
    assertFalse(CM.CopySettings(a, 999))
    assertFalse(CM.CopySettings(a, b, { "name" }), "a section that is not copyable is refused")
  end)
end)

test("cm: Snapshot and RestoreSnapshot put the registry back exactly, ids included", function()
  withFreshProfile(function(p)
    local a = CM.Create("target")
    CM.Create("focus")
    local snap = CM.Snapshot()
    CM.Delete(a)
    CM.Create("pet")
    CM.Get(p.containerOrder[1]).name = "Changed"
    assertTrue(CM.RestoreSnapshot(snap))
    assertEqual(#p.containerOrder, 2)
    assertEqual(p.containerOrder[1], a, "the same ids")
    assertEqual(CM.Get(p.containerOrder[2]).name, "Focus")
    assertTrue(p.nextContainerId > snap.nextContainerId, "the id counter is never rewound")
    assertTrue(p.containers ~= snap.containers, "restored as copies, so the snapshot stays reusable")
    assertFalse(CM.RestoreSnapshot(nil))
  end)
end)

-- ---------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------

test("cm: test_apply_coalesced_once_per_frame — many writes in one frame announce once", function()
  withFreshProfile(function()
    local n = countChanged(function()
      local mark = timerMark()
      CM.Create("target")
      CM.Create("focus")
      CM.RequestApply()
      assertEqual(queuedFlushes(mark), 1, "one coalescing timer for the whole frame")
      assertTrue(nextFrame())
    end)
    assertEqual(n, 1, "one CONTAINERS_CHANGED")
    assertNil(CM.__flushTimer(), "the frame's flush is spent")
    assertEqual(countChanged(function() nextFrame() end), 0, "nothing pending, nothing sent")
    assertEqual(countChanged(function()
      CM.RequestApply()
      nextFrame()
    end), 1, "the next frame's request is its own")
  end)
end)

test("cm: test_apply_deferred_in_combat — a flush in combat waits for PLAYER_REGEN_ENABLED", function()
  withFreshProfile(function()
    local inCombat = true
    M.InCombatLockdown = function() return inCombat end
    local n = countChanged(function()
      CM.Create("target")
      nextFrame()
    end)
    assertEqual(n, 0, "held in combat")
    assertTrue(CM.__pending(), "still pending")
    assertEqual(countChanged(function() CM.RequestApply() nextFrame() end), 0, "a second write is held too")
    inCombat = false
    n = countChanged(function() NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED") end)
    assertEqual(n, 1, "combat's end applies once")
    assertFalse(CM.__pending())
    assertEqual(countChanged(function() NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED") end), 0,
      "a second leave edge has nothing to apply")
  end)
end)

test("cm: a stood-down addon arms no apply timer, and the stand-up announces once", function()
  withFreshProfile(function()
    NS.lifecycle:Hold("test-cm")
    local ok, err = pcall(function()
      CM.Create("target")
      assertNil(CM.__flushTimer(), "no timer while stood down")
    end)
    local n = countChanged(function()
      NS.lifecycle:Release("test-cm")
      nextFrame()
    end)
    if not ok then error(err, 0) end
    assertEqual(n, 1, "the stand-up re-applies everything once")
  end)
end)

test("cm: a restore never rewinds the id counter, so a later Create mints an id never used", function()
  withFreshProfile(function()
    local snap = CM.Snapshot()
    local used = {}
    for _, unit in ipairs({ "target", "focus", "pet" }) do used[CM.Create(unit)] = true end
    assertTrue(CM.RestoreSnapshot(snap))
    local id = CM.Create("mouseover")
    assertFalse(used[id] == true, "an id minted before the restore is not handed out again")
  end)
end)

test("cm: Create keeps its positional unit; opts.unit cannot smuggle in an unwatched one", function()
  withFreshProfile(function()
    local id = CM.Create("target", { unit = "raid1" })
    assertEqual(CM.Get(id).unit, "target")
    local f = CM.Create("focus", { unit = "pet", name = "Mine" })
    assertEqual(CM.Get(f).unit, "focus", "the positional unit wins over opts.unit")
    assertEqual(CM.Get(f).name, "Mine", "opts.name still names it")
  end)
end)

test("cm: a profile switch announces CONTAINERS_CHANGED once, on the next frame", function()
  withFreshProfile(function()
    CM.Create("target")
    nextFrame()
    local n = countChanged(function()
      NS.OnProfileChanged()
      assertTrue(nextFrame(), "the switch asked for an apply")
    end)
    assertEqual(n, 1, "the new profile's registry is announced")
    assertEqual(countChanged(function()
      NS.OnProfileCopied("Other")
      nextFrame()
    end), 1, "a copy is announced too")
    assertEqual(countChanged(function()
      NS.OnProfileReset()
      nextFrame()
    end), 1, "and a reset")
  end)
end)

test("cm: MarkSeeded is the first-run sentinel's one runtime writer", function()
  -- red under: profile.seeded written anywhere but modules/ContainerManager.lua (architecture-§5,
  -- anti-pattern #78: a registry with two writers), or MarkSeeded not setting it.
  withFreshProfile(function(p)
    assertEqual(p.seeded, false, "precondition: a fresh profile owes the picker")
    CM.MarkSeeded()
    assertEqual(p.seeded, true, "marked")
    CM.MarkSeeded()
    assertEqual(p.seeded, true, "and a repeat is harmless")
  end)
  for _, path in ipairs(T.loadedAddonFiles) do
    path = path:gsub("\\", "/")
    if path ~= "modules/ContainerManager.lua" and path ~= "core/Database.lua" then
      local f = io.open(path, "r")
      local src = f and f:read("*a") or ""
      if f then f:close() end
      assertNil(src:find("%.seeded%s*=[^=]"), path .. " writes profile.seeded around the registry's writer")
    end
  end
end)


test("cm: spell chips follow the character until a list is stored (a shared profile, two classes)", function()
  -- red under: CM.Create seeding elements.spells.list from the creating character's class (an alt of
  -- another class on the shared Default profile would see the first character's spells, gray).
  withFreshProfile(function()
    local id = CM.Create("focus")
    local c = CM.Get(id)
    local byClient = NS.SpellSeeds[NS.Compat.ClientKey()]
    M.__context.classToken = "PRIEST"
    assertEqual(CM.SpellChips(c)[1], byClient.PRIEST.chips[1], "a priest logging in reads the priest's chips")
    M.__context.classToken = "MAGE"
    assertEqual(CM.SpellChips(c)[1], byClient.MAGE.chips[1], "the mage reads the mage's")
    c.elements.spells.list = { 12345 }
    assertEqual(table.concat(CM.SpellChips(c), ","), "12345", "a stored list is the player's choice and wins")
  end, "MAGE")
end)
