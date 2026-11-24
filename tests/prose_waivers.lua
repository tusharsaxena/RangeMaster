-- tests/prose_waivers.lua — what the kit's US-English gate MUST NOT correct here.
--
-- Read by `tests/_kit/test_prose.lua` (localization-5). Per FILE and per WORD, never per file
-- alone: a whole-file waiver hides every OTHER British spelling in a file this repo edits often.
-- Every entry carries its reason.

return {
    waived = {
        -- GAME DATA, not prose. The seed bundle's DIFF.md (written by tools/seeds/seeds.py, frozen)
        -- quotes WoW Forever's own SpellName row for spell 20271, which the vanilla client spells
        -- with the British "e". The id is what is shipped; the name is the client's, quoted as is
        -- (localization-5: match game data on the token the game uses). A later Forever bundle that
        -- quotes it again gets its own entry here.
        ["docs/seed-research/2026-11-25-forever/DIFF.md"] = { ["judge" .. "ment"] = true },
    },
}
