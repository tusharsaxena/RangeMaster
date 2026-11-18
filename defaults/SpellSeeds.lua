local _, NS = ...
-- defaults/SpellSeeds.lua — the per-client, per-class spell seeds (clients-§5; design spec 5.1).
--
--   NS.SpellSeeds[client][classFile] = { chips = { spellID, ... }, ladder = { spellID, ... } }
--
-- `client` is "retail" or "forever" (NS.Compat.ClientKey()), `classFile` the uppercase class token
-- UnitClass answers second. DATA ONLY: nothing here asks the client anything.
--
--   chips    the spells a container's spell-chip row offers first for this class (the Advanced
--            preset seeds its focus container from it, plan Task 4). Each chip is asked through
--            NS.Range.InSpellRange, so a spell the character has not learned shows no answer.
--   ladder   ranged spells core/Compat.lua's RangeLadder may add as rungs. A rung is added only
--            when the player knows the spell and the client reports a max range above 0 with no
--            min range (a min-range spell such as Charge cannot bound a bracket from one side),
--            at that max range. Retail's ladder is never walked (LibRangeCheck answers there);
--            Forever walks it only when LibRangeCheck has no answer (modules/Range.lua).
--
-- Forever is a vanilla world: no Death Knight, Monk, Demon Hunter or Evoker, and vanilla spell IDs
-- (rank 1, which is what the spellbook range check reads). The IDs are the classic, long-stable
-- ones; docs/smoke-tests.md carries the in-game check that each one resolves on both clients.

NS.SpellSeeds = {
    retail = {
        WARRIOR     = { chips = { 100, 57755, 355 },          ladder = { 57755, 355 } },
        PALADIN     = { chips = { 20271, 62124, 19750 },      ladder = { 20271, 19750 } },
        HUNTER      = { chips = { 185358, 56641, 147362 },    ladder = { 185358, 147362 } },
        ROGUE       = { chips = { 185565, 36554, 1766 },      ladder = { 185565, 36554 } },
        PRIEST      = { chips = { 585, 589, 2061 },           ladder = { 585, 2061 } },
        DEATHKNIGHT = { chips = { 49576, 47541, 47528 },      ladder = { 49576, 47528 } },
        SHAMAN      = { chips = { 188196, 57994, 8004 },      ladder = { 188196, 57994 } },
        MAGE        = { chips = { 116, 118, 2139 },           ladder = { 116, 118 } },
        WARLOCK     = { chips = { 686, 5782, 172 },           ladder = { 686, 5782 } },
        MONK        = { chips = { 115546, 117952, 116670 },   ladder = { 115546, 117952 } },
        DRUID       = { chips = { 5176, 8921, 8936 },         ladder = { 5176, 8936 } },
        DEMONHUNTER = { chips = { 185123, 185245, 183752 },   ladder = { 185123, 183752 } },
        EVOKER      = { chips = { 362969, 361469, 351338 },   ladder = { 362969, 351338 } },
    },
    forever = {
        WARRIOR = { chips = { 100, 2764, 20252 },  ladder = { 2764 } },
        PALADIN = { chips = { 20271, 853, 635 },   ladder = { 20271, 635 } },
        HUNTER  = { chips = { 75, 3044, 1130 },    ladder = { 1130 } },
        ROGUE   = { chips = { 2764, 1766, 1752 },  ladder = { 2764 } },
        PRIEST  = { chips = { 585, 589, 2050 },    ladder = { 585, 2050 } },
        SHAMAN  = { chips = { 403, 8042, 331 },    ladder = { 403, 8042 } },
        MAGE    = { chips = { 133, 116, 2136 },    ladder = { 133, 116, 2136 } },
        WARLOCK = { chips = { 686, 172, 5782 },    ladder = { 686, 5782 } },
        DRUID   = { chips = { 5176, 8921, 5185 },  ladder = { 5176, 5185 } },
    },
}
