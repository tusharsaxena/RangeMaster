local _, NS = ...
-- defaults/SpellSeeds.lua — the per-client, per-class spell seeds (clients-§5; design spec 5.1).
--
--   NS.SpellSeeds[client][classFile] = { chips = { spellID, ... }, ladder = { spellID, ... },
--                                        anchors = { melee = {...}, ranged = {...}, friendly = {...} } }
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
--   anchors  the spells a band's spell rule asks "in range?" (dynamic-bands plan D1; research doc
--            docs/superpowers/specs/2026-11-19-dynamic-bands-research.md section 6, with part 2's
--            corrections). One ordered fallback list per ROLE: the first one the player knows is
--            the role's anchor, resolved to its current rank and override (NS.Compat.CurrentSpellID)
--            and asked per tick (NS.Compat.AnchorInRange). A role a class has no list for is
--            unresolved, and its band falls back to its yards. Three roles:
--              melee     a 0-5 yd strike. Casters have none: their first band stays a yard band.
--                        Druid melee is keyed by form instead, { cat = {...}, bear = {...} }: a
--                        form's strike answers only in that form.
--              ranged    the class's attack or cast range (Forever hunter: Auto Shot's 8-35).
--              friendly  a heal or buff, for a friendly unit's set.
--            No reactive spell (Mongoose Bite answers only after a dodge) and no long-range role
--            (the owner ruled no Hunter's Mark band).
--
-- Forever is a vanilla world: no Death Knight, Monk, Demon Hunter or Evoker, and vanilla spell IDs
-- (rank 1, which is what the spellbook range check reads). The IDs are the classic, long-stable
-- ones; docs/smoke-tests.md carries the in-game check that each one resolves on both clients.

NS.SpellSeeds = {
    retail = {
        WARRIOR     = { chips = { 100, 57755, 355 },          ladder = { 57755, 355 },
                        anchors = { melee = { 1464, 6552 }, ranged = { 57755, 355, 100 } } },
        PALADIN     = { chips = { 20271, 62124, 19750 },      ladder = { 20271, 19750 },
                        anchors = { melee = { 35395, 96231 }, ranged = { 20271, 31935 },
                                    friendly = { 19750 } } },
        HUNTER      = { chips = { 185358, 56641, 147362 },    ladder = { 185358, 147362 },
                        anchors = { melee = { 186270, 195645, 187707 },
                                    ranged = { 185358, 56641, 75, 193455 } } },
        ROGUE       = { chips = { 185565, 36554, 1766 },      ladder = { 185565, 36554 },
                        anchors = { melee = { 193315, 1766 }, ranged = { 185763, 114014, 185565 } } },
        PRIEST      = { chips = { 585, 589, 2061 },           ladder = { 585, 2061 },
                        anchors = { ranged = { 585, 589, 8092, 47540 }, friendly = { 2061 } } },
        DEATHKNIGHT = { chips = { 49576, 47541, 47528 },      ladder = { 49576, 47528 },
                        anchors = { melee = { 49998, 206930 }, ranged = { 47541, 49184, 49576 } } },
        SHAMAN      = { chips = { 188196, 57994, 8004 },      ladder = { 188196, 57994 },
                        anchors = { melee = { 73899, 17364, 60103 }, ranged = { 188196, 188389, 57994 },
                                    friendly = { 8004 } } },
        MAGE        = { chips = { 116, 118, 2139 },           ladder = { 116, 118 },
                        anchors = { ranged = { 116, 133, 30451, 108853 } } },
        WARLOCK     = { chips = { 686, 5782, 172 },           ladder = { 686, 5782 },
                        anchors = { ranged = { 686, 172, 980, 29722 } } },
        MONK        = { chips = { 115546, 117952, 116670 },   ladder = { 115546, 117952 },
                        anchors = { melee = { 100780, 116705 }, ranged = { 117952, 115546 },
                                    friendly = { 116670 } } },
        DRUID       = { chips = { 5176, 8921, 8936 },         ladder = { 5176, 8936 },
                        anchors = { melee = { cat = { 5221, 1822 }, bear = { 33917, 6807 } },
                                    ranged = { 5176, 190984, 8921 }, friendly = { 8936 } } },
        -- Disrupt 183752 is Combat Range 0-5 in 12.1.5, not the 20 yd LibRangeCheck still labels
        -- it: a melee anchor and a chip, never a ladder rung.
        DEMONHUNTER = { chips = { 185123, 185245, 183752 },   ladder = { 185123, 185245 },
                        anchors = { melee = { 162243, 162794, 183752 }, ranged = { 185123, 185245 } } },
        EVOKER      = { chips = { 362969, 361469, 351338 },   ladder = { 362969, 351338 },
                        anchors = { ranged = { 362969, 361469, 356995 }, friendly = { 361469 } } },
    },
    forever = {
        WARRIOR = { chips = { 100, 2764, 20252 },  ladder = { 2764 },
                    anchors = { melee = { 78, 772, 1715 }, ranged = { 100, 20252, 2764, 2480, 7918 } } },
        -- No baseline melee strike: the seal-and-judge spell 20271 is 0-10 yd, too far for a melee band.
        PALADIN = { chips = { 20271, 853, 635 },   ladder = { 20271, 635 },
                    anchors = { ranged = { 879, 24275 }, friendly = { 635, 19750 } } },
        HUNTER  = { chips = { 75, 3044, 1130 },    ladder = { 1130 },
                    anchors = { melee = { 2973, 2974 }, ranged = { 75, 3044, 1978 } } },
        ROGUE   = { chips = { 2764, 1766, 1752 },  ladder = { 2764 },
                    anchors = { melee = { 1752, 1776, 1766 }, ranged = { 2764, 2480, 7918, 1725 } } },
        PRIEST  = { chips = { 585, 589, 2050 },    ladder = { 585, 2050 },
                    anchors = { ranged = { 585, 8092, 589 }, friendly = { 2050, 2061 } } },
        SHAMAN  = { chips = { 403, 8042, 331 },    ladder = { 403, 8042 },
                    anchors = { melee = { 17364 }, ranged = { 403, 370, 421 }, friendly = { 331 } } },
        MAGE    = { chips = { 133, 116, 2136 },    ladder = { 133, 116, 2136 },
                    anchors = { ranged = { 133, 116, 5143 }, friendly = { 1459 } } },
        WARLOCK = { chips = { 686, 172, 5782 },    ladder = { 686, 5782 },
                    anchors = { ranged = { 686, 172, 348 } } },
        DRUID   = { chips = { 5176, 8921, 5185 },  ladder = { 5176, 5185 },
                    anchors = { melee = { cat = { 1082, 5221 }, bear = { 6807, 6795, 5211 } },
                                ranged = { 5176, 8921, 339 }, friendly = { 5185 } } },
    },
}
