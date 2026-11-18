# Midnight quirks — Ka0s Range Master

This file has two parts: the collection's client-quirks catalog, vendored whole from the Ka0s WoW Addon Standard between the markers below and never edited here, and then this addon's own quirks under `## RangeMaster-specific quirks

The client behaviors this addon's code works around and the vendored catalog above does not carry.
None has been measured in a client by this addon yet: each is read from the reference addons, the
vendored LibRangeCheck-3.0 or Blizzard's generated API docs (the design's research,
`docs/superpowers/research/2026-11-18-range-research.md`), and each is a smoke check
(`docs/smoke-tests.md`) until a client run confirms it. A secret `UnitGUID` and forbidden frames are
the catalog's (sections 2 and 4) and are not restated here.

- **Item and interact range checks are refused in combat on a unit the player cannot attack.**
  `C_Item.IsItemInRange` and `CheckInteractDistance` are blocked for insecure code in combat on a
  friendly or other unattackable unit (the 10.2 rule); hostile units are fine. *Measured:* not
  measured; Blizzard's generated docs for Retail 12.1.5 (build 70783) and LibRangeCheck-3.0's
  `InCombatLockdownRestriction`. *Client:* Retail, and WoW Forever by the same client code. *Cost:*
  an `ADDON_ACTION_BLOCKED` per check. *Do:* in combat on a unit `UnitCanAttack` says no, ask spell
  checks only (`modules/Range.lua`'s ladder walk; LibRangeCheck does the same with its `*InCombat`
  lists). *Source:* the research, *API facts*.
- **WoW Forever's item checks are reliable only at 20, 30 and 35 yards.** Other item yards answer
  wrongly or not at all. *Measured:* not measured here; AppelSwingsForever `Bands.lua`, on Forever
  1.60.1. *Client:* Forever. *Cost:* a bracket edge at a yard the client does not honor. *Do:* keep
  Forever's item rungs at those three yards (`core/Compat.lua`, `FOREVER_ITEMS`). *Source:* the
  research, *WoW Forever*.
- **A spell can report "in range" from any distance.** On WoW Forever a melee spell whose range is
  0 to 0 does; on both clients a known spell that is unusable in the current form or stance can.
  *Measured:* not measured here; RangeLens and AppelSwingsForever. *Client:* Forever (the 0 to 0
  case), both (the form case). *Cost:* a container, a chip or a ladder rung that reads in range
  everywhere. *Do:* trust `C_Spell.IsSpellInRange` only for a spell that is known and usable, ask
  usability on every check (a shapeshift fires no `SPELLS_CHANGED`), and take a ladder rung only from
  a spell with a max range above 0 and no min range (`modules/Range.lua`, `core/Compat.lua`).
  *Source:* the research, *Lessons* 9.
- **`NAME_PLATE_UNIT_ADDED` can fire before the plate is populated.** *Measured:* not measured here;
  RangeLens's `OnPlateAdded` re-runs a frame later for it. *Client:* Forever. *Cost:* a container
  drawn at the screen's corner, or on no plate, until the next event. *Do:* re-check every added
  token one frame later (`modules/Anchors_Nameplate.lua`); the re-check runs on both clients, so no
  client branch sits outside the Compat layer. *Source:* the research, *WoW Forever*.
- **The token still resolves while `NAME_PLATE_UNIT_REMOVED` dispatches.** Inside the handler the
  removed `nameplateN` still answers, and `"target"` still answers the dying plate. *Measured:* not
  measured; read from the event order the anchors are built to. *Client:* both. *Cost:* a re-read
  sees the plate as live, and an own-plate container is put straight back on a plate that is going.
  *Do:* send `"none"` for the token outright (`NS.Ticker.Removed`), hide an own-plate container by
  comparing plate frames, and look again a frame later (`modules/Anchors_Nameplate.lua`).
  *Source:* `core/RangeMaster.lua`'s `OnNamePlateChanged`.
- **LibRangeCheck-3.0 caches per unit token when the GUID is a secret.** Its answer is kept 0.1 s,
  keyed by the token. *Measured:* read from LibRangeCheck-3.0 MINOR 39's source. *Client:* both.
  *Cost:* a retarget or a recycled `nameplateN` inside that window reads back the previous unit's
  bracket, and a 20 Hz ticker sees fresh data only every other tick. *Do:* call
  `GetRange(unit, true, nil, 0)` (a max cache age of 0) and keep this addon's own per-tick memo as
  the only cache (`modules/Range.lua`). *Source:* `modules/Range.lua`'s header.
