"""tools/seeds/test_seeds.py — the seed tool's own suite (docs/validate-seeds.md, ## Gate).

Runs with `python3 -m pytest -q -p no:cacheprovider tools/seeds`. No network: the tables are tiny
invented CSVs written per test, with ids from 900000 up; only the sentinels (116, 133, 5176) and
SpellRange 2 carry the game's own ids, because the gate is about exactly those. The repo's own Lua
files are read for real, so a reshaped seed or preset file turns this suite red.
"""

import csv
import gzip
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import seeds  # noqa: E402

# Invented ids. W = a warrior-family spell, M = a mage-family one.
W_STRIKE, W_THROW, W_TAUNT, W_SELF, W_FAR_MELEE = 900001, 900002, 900003, 900004, 900005
M_BOLT, M_BOLT_R2, M_BUFF, M_GHOST = 900011, 900012, 900013, 900014
OTHER_CLASS, MASKED = 900021, 900022


def write_csv(path, header, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        out = csv.writer(handle)
        out.writerow(header)
        out.writerows(rows)
    return path


def fixture_tables(tmp_path, forever=True, thin=False):
    """`{table: path}` for an invented build. `thin` drops the sentinels' names."""
    names = [(W_STRIKE, "Test Strike"), (W_THROW, "Test Throw"), (W_TAUNT, "Test Taunt"), (W_SELF, "Test Shout"),
             (W_FAR_MELEE, "Test Lunge"), (M_BOLT, "Test Bolt"), (M_BOLT_R2, "Test Bolt"), (M_BUFF, "Test Brilliance"),
             (M_GHOST, "Test Bolt"), (OTHER_CLASS, "Test Prayer"), (MASKED, "Test Sling")]
    if not thin:
        names += [(116, "Frostbolt"), (133, "Fireball"), (5176, "Wrath")]
    t = {"SpellName": write_csv(tmp_path / "SpellName.csv", ["ID", "Name_lang"], names)}
    misc = [(W_STRIKE, 2), (W_THROW, 74), (W_TAUNT, 4), (W_SELF, 1), (W_FAR_MELEE, 3), (M_BOLT, 35), (M_BOLT_R2, 35),
            (M_BUFF, 4), (M_GHOST, 1), (OTHER_CLASS, 4), (MASKED, 74), (116, 4), (133, 35), (5176, 4)]
    t["SpellMisc"] = write_csv(tmp_path / "SpellMisc.csv", ["ID", "DifficultyID", "RangeIndex", "SpellID"],
                               # A difficulty-1 row comes first: only DifficultyID 0 rows may set a spell's range.
                               [(99, 1, 6, W_STRIKE)] + [(i + 1, 0, r, s) for i, (s, r) in enumerate(misc)])
    t["SpellRange"] = write_csv(tmp_path / "SpellRange.csv",
                                ["ID", "DisplayName_lang", "RangeMin_0", "RangeMin_1", "RangeMax_0", "RangeMax_1"],
                                [(1, "Self Only", 0, 0, 0, 0), (2, "Combat Range", 0, 0, 5, 5), (3, "Short Range", 0, 0, 20, 20),
                                 (4, "Medium Range", 0, 0, 30, 30), (6, "Vision Range", 0, 0, 100, 100),
                                 (35, "Medium-Long Range", 0, 0, 35, 35), (74, "Ranged Weapon", 8, 8, 30, 30)])
    t["SpellClassOptions"] = write_csv(tmp_path / "SpellClassOptions.csv", ["ID", "SpellID", "SpellClassSet"],
                                       [(1, W_STRIKE, 4), (2, W_THROW, 4), (3, W_TAUNT, 4), (4, W_SELF, 4),
                                        (5, W_FAR_MELEE, 4), (6, M_BOLT, 3), (7, M_BOLT_R2, 3), (8, M_BUFF, 3),
                                        (9, M_GHOST, 3), (10, OTHER_CLASS, 6), (11, MASKED, 8)])
    t["ChrClasses"] = write_csv(tmp_path / "ChrClasses.csv", ["Filename", "ID", "SpellClassSet"],
                                [("WARRIOR", 1, 4), ("MAGE", 8, 3), ("PRIEST", 5, 6), ("ROGUE", 4, 8)])
    # MASKED is the rogue family, but its learn row's ClassMask carries the warrior bit (1).
    t["SkillLineAbility"] = write_csv(tmp_path / "SkillLineAbility.csv", ["Spell", "ClassMask", "SupercedesSpell"],
                                      [(W_STRIKE, 1, 0), (M_BOLT, 128, 0), (M_BOLT_R2, 128, M_BOLT), (MASKED, 9, 0)])
    if forever:
        t["Spell"] = write_csv(tmp_path / "Spell.csv", ["ID", "NameSubtext_lang"],
                               [(M_BOLT, "Rank 1"), (M_BOLT_R2, "Rank 2"), (M_GHOST, "Rank 1"), (W_STRIKE, "Rank 1")])
    return t


PRESETS_LUA = """local Presets = {}
Presets.melee_ranged = {
    name = L["Melee / Ranged"], matchBy = "max",
    bands = {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 30, L["CLOSE"], LIME),
        band(30, 40, L["LONG"], ORANGE, spell("ranged")), band(40, nil, L["OOR"], RED, beyond()),
    },
}
Presets.caster40 = {
    bands = { band(0, 8, L["CLOSE"], ORANGE), band(8, 40, L["CAST"], GREEN, spell("ranged")),
              band(40, nil, L["OOR"], RED, beyond()) },
}
Presets.healer = {
    bands = { band(0, 30, L["NEAR"], GREEN), band(30, 40, L["FAR"], YELLOW, spell("friendly")),
              band(40, nil, L["OOR"], RED, beyond()) },
}
local HUNTER_BY_CLIENT = {
    forever = {
        bands = {
            band(0, 5, L["MELEE"], YELLOW, spell("melee")), band(5, 8, L["DEAD"], ORANGE, gap()),
            band(8, 35, L["RANGE"], GREEN, spell("ranged")), band(35, nil, L["OOR"], RED, beyond()),
        },
    },
    retail = {
        bands = { band(0, 5, L["MELEE"], LIME, spell("melee")), band(5, 40, L["RANGED"], GREEN, spell("ranged")),
                  band(40, nil, L["OOR"], RED, beyond()) },
    },
}
local CLASS_DEFAULT = {
    HUNTER = "hunter",
    MAGE = "caster40",
}
"""

SEEDS_LUA = """local _, NS = ...
-- Header: Test Strike 900001 is never read, this is above the blocks.
NS.SpellSeeds = {
    retail = {
        MAGE = { chips = { 116 }, ladder = { 116 }, anchors = { ranged = { 116 } } },
    },
    forever = {
        -- Test Lance 900005 is named wrongly on purpose.
        WARRIOR = { chips = { 900001, 900004 },  ladder = { 900002, 900003 },
                    anchors = { melee = { 900001, 900005 }, ranged = { 900002, 900003, 900022 } } },
        MAGE    = { chips = { 900011 },  ladder = { 900011 },
                    anchors = { ranged = { 900012, 900021 }, friendly = { 900013 } } },
        HUNTER  = { chips = {}, ladder = {},
                    anchors = { melee = { cat = { 900001 }, bear = { 900005 } }, ranged = { 900003 } } },
        PRIEST  = { chips = { 999999 }, ladder = {}, anchors = { ranged = { 900021 } } },
    },
}
"""


def write_repo(tmp_path):
    (tmp_path / "SpellSeeds.lua").write_bytes(SEEDS_LUA.replace("\n", "\r\n").encode("utf-8"))
    (tmp_path / "BandSetPresets.lua").write_text(PRESETS_LUA, encoding="utf-8")
    (tmp_path / "Range.lua").write_text("local X = 1\nlocal MELEE_REACH_YD = 8\n", encoding="utf-8")
    return tmp_path / "SpellSeeds.lua", tmp_path / "BandSetPresets.lua", tmp_path / "Range.lua"


def derive(tmp_path, flavor="forever"):
    tables = fixture_tables(tmp_path, forever=(flavor == "forever"))
    s, p, r = write_repo(tmp_path)
    return seeds.derive_doc(tables, flavor, "1.0.0.1", "2026-11-25", s, p, r)


def flag_keys(doc):
    return {f["key"] for f in doc["flags"]}


# ── the repo's own files, read for real ─────────────────────────────────────────────────

def test_real_seed_file_parses_both_flavors():
    parsed = seeds.read_seeds(seeds.SEEDS_FILE)
    assert len(parsed["retail"]["classes"]) == 13
    assert len(parsed["forever"]["classes"]) == 9
    assert "EVOKER" not in parsed["forever"]["classes"]
    fh = parsed["forever"]["classes"]["HUNTER"]
    assert fh["melee"] == [2974], "Wing Clip is the Forever hunter's melee anchor (the owner, 2026-11-24)"
    assert parsed["forever"]["classes"]["DRUID"]["melee.cat"] == [1082, 5221]
    assert parsed["forever"]["names"][2974] == "Wing Clip"
    assert 183752 in parsed["retail"]["names"]


def test_real_presets_and_reach():
    presets = seeds.read_presets(seeds.PRESETS_FILE)
    fh = presets["presets"]["hunter.forever"]
    assert [(b["from"], b["to"], b["rule"]) for b in fh] == [
        (0, 5, "spell:melee"), (5, 8, "gap"), (8, 35, "spell:ranged"), (35, None, "beyond")]
    assert presets["default"]["MAGE"] == "caster40"
    assert seeds.preset_for(presets, "forever", "HUNTER") == "hunter.forever"
    assert seeds.preset_for(presets, "retail", "WARRIOR") == "melee_ranged"
    assert seeds.role_band(presets["presets"]["healer"], "friendly")["to"] == 40
    assert seeds.read_melee_reach(seeds.RANGE_FILE) == 8


# ── the checks, on invented tables ──────────────────────────────────────────────────────

def test_sentinel_gate_stops_a_thin_build(tmp_path):
    with pytest.raises(SystemExit, match="sentinel gate FAILED"):
        seeds.Facts(fixture_tables(tmp_path, thin=True))


def test_id_flags(tmp_path):
    keys = flag_keys(derive(tmp_path))
    assert "shipped:ladder-min:WARRIOR.ladder:900002" in keys, "an 8-30 ladder seed is never a rung"
    assert "shipped:ladder-min:WARRIOR.ladder:900003" not in keys, "a 0-30 one is"
    assert "shipped:no-range:WARRIOR.chips:900004" in keys, "a self-only chip answers nothing"
    assert "shipped:melee-reach:WARRIOR.melee:900005" in keys, "a 20 yd melee anchor is dropped past 8 yd"
    assert "shipped:melee-reach:HUNTER.melee.bear:900005" in keys, "form-keyed melee lists are checked too"
    assert "shipped:renamed:WARRIOR.melee:900005" in keys, "the comment says Test Lance"
    assert "shipped:unnamed:PRIEST.chips:999999" in keys
    assert "shipped:class:MAGE.ranged:900021" in keys, "a priest-family spell under MAGE"
    assert not any(k.startswith("shipped:class:WARRIOR.ranged:900022") for k in keys), \
        "a rogue-family spell whose learn row's ClassMask carries the warrior bit is the warrior's"


def test_ranged_reach_flag(tmp_path):
    doc = derive(tmp_path)
    assert "shipped:ranged-reach:WARRIOR.ranged:900002" not in flag_keys(doc)
    tables = fixture_tables(tmp_path)
    facts = seeds.Facts(tables)
    v = seeds.verdict(facts, "forever", "WARRIOR", "ranged", W_STRIKE, {}, [], 8)
    assert [f["kind"] for f in v["flags"]] == ["ranged-reach"], "a 5 yd ranged anchor reaches no farther than melee"


def test_spellmisc_reads_difficulty_zero_only(tmp_path):
    facts = seeds.Facts(fixture_tables(tmp_path))
    v = seeds.verdict(facts, "forever", "WARRIOR", "melee", W_STRIKE, {}, [], 8)
    assert (v["rangeName"], v["min"], v["max"]) == ("Combat Range", 0, 5), \
        "a DifficultyID 1 SpellMisc row listed first must not set the spell's range"


def test_rank_flags(tmp_path):
    keys = flag_keys(derive(tmp_path))
    assert "shipped:rank:MAGE.ranged:900012" in keys, "Rank 2 is not rank 1"
    assert "shipped:rank:MAGE.chips:900011" not in keys
    facts = seeds.Facts(fixture_tables(tmp_path))
    assert facts.rank_issue(M_BUFF) is None
    # M_GHOST is a "Rank 1" Test Bolt with no learn row: it never makes a rank-less seed of that name wrong.
    facts.rank[M_BOLT] = ""
    assert facts.rank_issue(M_BOLT) is None
    facts.sla[M_GHOST] = [(128, 0)]
    assert "Rank 1" in facts.rank_issue(M_BOLT)


def test_rank_not_checked_on_retail(tmp_path):
    tables = fixture_tables(tmp_path, forever=False)
    facts = seeds.Facts(tables)
    v = seeds.verdict(facts, "retail", "MAGE", "ranged", M_BOLT_R2, {}, [], 8)
    assert v["flags"] == [] and v["rank"] == ""


def test_role_flags(tmp_path):
    doc = derive(tmp_path)
    keys = flag_keys(doc)
    assert "shipped:band-reach:WARRIOR.ranged:900002" in keys, "30 yd under a LONG band that ends at 40; a tie keys the first seed"
    assert "shipped:band-reach:MAGE.ranged:900012" in keys, "35 yd under caster40's CAST band (to 40)"
    assert "shipped:band-reach:MAGE.friendly:900013" in keys, "30 yd under the Healer FAR band"
    gap = [f for f in doc["flags"] if f["kind"] == "gap-fit"]
    assert [f["class"] for f in gap] == ["HUNTER"], "only the Forever hunter's preset has a gap"
    assert "no ranged anchor has a min range" in gap[0]["why"]
    assert "melee 900005 reaches 20 yd" in gap[0]["why"]


def test_role_flag_absent_when_reach_meets_the_edge(tmp_path):
    facts = seeds.Facts(fixture_tables(tmp_path))
    presets = seeds.read_presets(write_repo(tmp_path)[1])
    hunter = presets["presets"]["hunter.forever"]
    facts.ranges[74]["hostile"] = (8.0, 35.0)
    out = seeds.role_flags(facts, "HUNTER", {"melee": [W_STRIKE], "ranged": [W_THROW]}, "hunter.forever", hunter,
                           presets["presets"]["healer"])
    assert out == [], "8-35 ranged and 0-5 melee fit the 5-8 gap and the 35 yd edge"


def test_verdict_rows_carry_the_band(tmp_path):
    doc = derive(tmp_path)
    row = next(v for v in doc["verdicts"] if v["class"] == "WARRIOR" and v["list"] == "ladder" and v["id"] == W_TAUNT)
    assert (row["min"], row["max"], row["band"], row["classCheck"]) == (0, 30, "CLOSE", "ok")


# ── rulings, apply, status ──────────────────────────────────────────────────────────────

def test_set_ruling_validates():
    r = {}
    seeds.set_ruling(r, "shipped:ladder-min:WARRIOR.ladder:900002", "remove", "never a rung")
    assert r["shipped:ladder-min:WARRIOR.ladder:900002"]["ruling"] == "remove"
    with pytest.raises(SystemExit):
        seeds.set_ruling(r, "shipped:band-reach:WARRIOR.ranged:1", "remove", "x")
    with pytest.raises(SystemExit):
        seeds.set_ruling(r, "shipped:band-reach:WARRIOR.chips:1", "keep", "x")
    with pytest.raises(SystemExit):
        seeds.set_ruling(r, "shipped:nope:WARRIOR.chips:1", "keep", "x")
    with pytest.raises(SystemExit):
        seeds.set_ruling(r, "shipped:unnamed:WARRIOR.chips:1", "keep", "")


def test_apply_removes_ruled_ids_and_keeps_crlf(tmp_path):
    doc = derive(tmp_path)
    rulings = {k: {"ruling": "keep", "reason": "x"} for k in flag_keys(doc)}
    rulings["shipped:ladder-min:WARRIOR.ladder:900002"]["ruling"] = "remove"
    rulings["shipped:melee-reach:HUNTER.melee.bear:900005"]["ruling"] = "remove"
    path = tmp_path / "SpellSeeds.lua"
    before = path.read_bytes()
    assert seeds.apply_doc(doc, rulings, path) == ["forever WARRIOR.ladder: -900002", "forever HUNTER.melee.bear: -900005"]
    after = path.read_bytes()
    assert b"\r\n" in after and after.count(b"\n") == after.count(b"\r\n") == before.count(b"\r\n")
    text = after.decode("utf-8")
    assert "ladder = { 900003 }," in text and "bear = {} }" in text
    assert "chips = { 900001, 900004 }" in text, "the same id elsewhere is untouched"
    assert seeds.apply_doc(doc, rulings, path) == [], "a second apply changes nothing"


def test_apply_refuses_unruled(tmp_path):
    doc = derive(tmp_path)
    with pytest.raises(SystemExit, match="unruled"):
        seeds.apply_doc(doc, {}, tmp_path / "SpellSeeds.lua")


def test_apply_touches_only_its_flavor(tmp_path):
    s = write_repo(tmp_path)[0]
    assert seeds.apply_seeds(s, "retail", {("WARRIOR", "ladder"): {900002}}) == []
    assert seeds.apply_seeds(s, "retail", {("MAGE", "ladder"): {116}}) == ["retail MAGE.ladder: -116"]
    assert "MAGE    = { chips = { 900011 },  ladder = { 900011 }," in s.read_bytes().decode("utf-8")


def test_newest_live_skips_background_builds():
    builds = [{"version": "2.0", "is_bgdl": True}, {"version": "1.9", "is_bgdl": False}]
    assert seeds.newest_live(builds) == "1.9"
    with pytest.raises(SystemExit):
        seeds.newest_live([{"version": "2.0", "is_bgdl": True}])


def test_status_line(tmp_path):
    assert seeds.status_line("1.0", []).startswith("NEW 1.0")
    bundle = tmp_path / "2026-11-25-forever"
    bundle.mkdir()
    (bundle / "candidates.json").write_text('{"build": "1.0"}', encoding="utf-8")
    found = seeds.bundles(tmp_path, "forever")
    assert seeds.status_line("1.0", found).startswith("CURRENT 1.0")
    assert seeds.status_line("1.1", found).startswith("NEW 1.1 (last ruled 1.0")


def test_freeze_and_replay(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    tables = fixture_tables(src)
    cache = tmp_path / "cache"
    cache.mkdir()
    for table, path in tables.items():
        (cache / ("%s-1.0.0.1.csv" % table)).write_bytes(path.read_bytes())
    bundle = tmp_path / "2026-11-25-forever"
    out = seeds.freeze_tables(bundle, "forever", "1.0.0.1", cache, replay=False)
    assert set(out) == {t for t, _ in seeds.tables_for("forever")}
    first = out["SpellName"].read_bytes()
    assert gzip.decompress(first) == tables["SpellName"].read_bytes()
    seeds.freeze_tables(bundle, "forever", "1.0.0.1", cache, replay=False)
    assert out["SpellName"].read_bytes() == first, "the same CSV freezes to the same bytes"
    assert seeds.freeze_tables(bundle, "forever", "1.0.0.1", cache, replay=True)["SpellName"] == out["SpellName"]
    assert "Spell" not in {t for t, _ in seeds.tables_for("retail")}, "Retail reads no rank text"


def test_reports_render(tmp_path):
    doc = derive(tmp_path)
    diff = seeds.diff_md(doc)
    assert "## WARRIOR (default preset `melee_ranged`)" in diff and "ladder-min" in diff
    rulings = {k: {"ruling": "keep", "reason": "a | b"} for k in flag_keys(doc)}
    md = seeds.rulings_md(doc, rulings, "2026-11-25")
    assert "a \\| b" in md and "Unruled" not in md
    assert "Unruled" in seeds.rulings_md(doc, {}, "2026-11-25")
    assert "`wowf`" in seeds.sources_md("forever", "1.0.0.1", "2026-11-25", False)
