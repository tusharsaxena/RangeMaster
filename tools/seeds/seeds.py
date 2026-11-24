#!/usr/bin/env python3
"""tools/seeds/seeds.py — re-validate Range Master's spell seeds against one wago.tools build.

WHAT THIS IS
    The contract `/dev-copilot:validate-seeds RangeMaster <flavor>` runs (docs/validate-seeds.md).
    Range Master ships one seed file that mirrors the client's own DB2 data:

    defaults/SpellSeeds.lua   NS.SpellSeeds[client][classFile] = { chips, ladder, anchors =
                              { melee, ranged, friendly } } (druid melee keyed by form: cat, bear).
                              HAND-CURATED, not derived: a short list per class. So a run proposes no
                              new ids. It checks every shipped id against the client's own DB2 and
                              against what the addon's code assumes of that id's RANGE.

    The checks, per shipped id (a flag, key `shipped:<kind>:<CLASS>.<list>:<id>`, ruled keep or remove):
        unnamed      the build's SpellName has no row for it
        renamed      a comment in the flavor's block names the id ("Wing Clip 2974") and the build
                     names it otherwise
        class        its SpellClassOptions family is another class's and no SkillLineAbility row
                     lets this class learn it (ClassMask)
        rank         (forever) not rank 1: its rank text is "Rank N" with N > 1, a learnable
                     same-family row of the same name is "Rank 1", or it supersedes a same-name spell
        no-range     SpellMisc's RangeIndex reaches 0 yd (self only, or no row): no range question
                     can be asked of it
        ladder-min   a ladder seed with a min range: core/Compat.lua's spellRung never makes it a
                     rung (docs/common-tasks.md: "a melee or min-range spell belongs in chips")
        melee-reach  a melee anchor with a min range, or reaching past modules/Range.lua's
                     MELEE_REACH_YD (the resolver drops it, knownList)
        ranged-reach a ranged anchor that reaches no farther than MELEE_REACH_YD
    And per role (key `shipped:<kind>:<CLASS>.<role>:<id of the role's first anchor>`, ruled keep):
        band-reach   the role's longest reach (the anchor the resolver asks first, longerFirst) is
                     not the far edge of the band the class's default preset gives that role
                     (defaults/BandSetPresets.lua; friendly: the Healer preset). Past that reach the
                     anchor says false, so beyond reads OOR there whatever the band's yards say.
        gap-fit      the default preset has a dead-zone (gap) band and a ranged anchor's min range is
                     not that band's far edge, a melee anchor's reach is not its near edge, or no
                     ranged anchor has a min range at all (the gap can never hold, Range.Near)

    A ruling is keyed by class, list and id, never by build, and holds until the thing it ruled on
    stops being proposed. So a re-run on a later build shows only what is new since the last run.
    The hostile range (RangeMin_0, RangeMax_0) is read for every list but `friendly`, which reads
    the friendly one (RangeMin_1, RangeMax_1).

THE STEPS
    python3 tools/seeds/seeds.py status --flavor <flavor>
    python3 tools/seeds/seeds.py derive --flavor <flavor> --bundle docs/seed-research/<date>-<flavor> --date <date> [--build V] [--replay]
    python3 tools/seeds/seeds.py check  --flavor <flavor> --bundle docs/seed-research/<date>-<flavor>
    python3 tools/seeds/seeds.py rule   --flavor <flavor> --tsv <file> --bundle docs/seed-research/<date>-<flavor>
    python3 tools/seeds/seeds.py report --flavor <flavor> --bundle docs/seed-research/<date>-<flavor> --date <date>
    python3 tools/seeds/seeds.py apply  --flavor <flavor> --bundle docs/seed-research/<date>-<flavor> --date <date>

    `derive` pins one build (`--build`, else the flavor's newest live non-bgdl build from the builds
    API), fetches every table into the git-ignored tools/seeds/.cache/ (streamed, never read whole),
    freezes them gzipped into the bundle's raw/, and writes SOURCES.md, DIFF.md and candidates.json.
    `--replay` reads only the bundle's raw/ and needs no network. `rule` is the only writer of
    tools/seeds/<flavor>_rulings.json. `check` exits 1 while anything is unruled. `report` writes
    RULINGS.md. `apply` refuses while anything is unruled, removes every id ruled `remove` from its
    class's list in that flavor's block, keeps every other byte, and is idempotent. The date is
    always an argument; nothing here reads the clock.

    Patterns are copied from DPS Race's and Aura Master's seed tools, never imported across repos.
    Whether a shared helper should carry the build pin, the cache, the bundle and the rulings is
    LibKa0s#91.

Python 3.8+ and its standard library only.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import shutil
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
RESEARCH = REPO / "docs" / "seed-research"
CACHE_DIR = HERE / ".cache"
SEEDS_FILE = REPO / "defaults" / "SpellSeeds.lua"
PRESETS_FILE = REPO / "defaults" / "BandSetPresets.lua"
RANGE_FILE = REPO / "modules" / "Range.lua"

BUILDS_URL = "https://wago.tools/api/builds"
CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}"
# wago.tools answers HTTP 403 to urllib's default User-Agent; this says who is asking (clients-§10).
USER_AGENT = "RangeMaster-seed-check"
DOWNLOAD_CHUNK = 1 << 20  # Retail's SpellMisc is ~46 MB: always streamed, never read into one string

# The client a flavor validates and its own wago product (clients-§10).
FLAVORS = {
    "retail": {"product": "wow", "title": "Retail"},
    "forever": {"product": "wowf", "title": "WoW Forever"},
}

# The fetch list IS the list SOURCES.md records, so a bundle never claims a table it did not read.
COMMON_TABLES = (
    ("SpellName", "every shipped id's name: the unnamed and renamed flags"),
    ("SpellMisc", "RangeIndex (DifficultyID 0): which SpellRange row an id uses"),
    ("SpellRange", "RangeMin_0/RangeMax_0 (hostile) and RangeMin_1/RangeMax_1 (friendly)"),
    ("SpellClassOptions", "SpellClassSet: the spell's class family, for the class flag"),
    ("ChrClasses", "Filename -> ID and SpellClassSet: the class a seed is keyed by"),
    ("SkillLineAbility", "ClassMask: who can learn it; SupercedesSpell: the rank chain (forever)"),
)
FOREVER_TABLES = (
    ("Spell", "NameSubtext_lang: the rank text, for the rank flag"),
)

LIST_NAMES = ("chips", "ladder", "melee", "melee.cat", "melee.bear", "ranged", "friendly")
ID_KINDS = ("unnamed", "renamed", "class", "rank", "no-range", "ladder-min", "melee-reach", "ranged-reach")
ROLE_KINDS = ("band-reach", "gap-fit")
ID_RULINGS = ("keep", "remove")
ROLE_RULINGS = ("keep",)
KEY = re.compile(r"^shipped:(?P<kind>[a-z-]+):(?P<cls>[A-Z]+)\.(?P<list>[a-z.]+):(?P<id>\d+)$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
RANK_RE = re.compile(r"^Rank (\d+)$")

# Ids the game, not this tool's output, says every build must answer, with the range the code's
# reading of DB2 rests on: a run whose tables come up thin stops instead of flagging every seed.
SENTINELS = {116: "Frostbolt", 133: "Fireball", 5176: "Wrath"}
COMBAT_RANGE = (2, 5.0)  # SpellRange 2, "Combat Range", reaches 5 yd on both clients

FLAVOR_OPEN = re.compile(r"^    (retail|forever) = \{\s*$")
CLASS_OPEN = re.compile(r"^\s+([A-Z]+)\s*=\s*\{")
FLAT_LIST = re.compile(r"\b(chips|ladder|melee|ranged|friendly|cat|bear)\s*=\s*\{([\d,\s]*)\}")
COMMENT_NAME = re.compile(r"((?:[A-Z][\w':-]*)(?: (?:of|the|[A-Z][\w':-]*))*) (\d{3,7})\b")
BAND_CALL = re.compile(r'band\((\d+),\s*(nil|\d+),\s*L\["([^"]+)"\],\s*\w+'
                       r'(?:,\s*(?:spell\("(\w+)"\)|(gap)\(\)|(beyond)\(\)))?\)')


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Files: CRLF in this repo (.gitattributes `* text=auto eol=crlf`; *.py is LF)
# ---------------------------------------------------------------------------

def write_repo_text(path: Path, text: str) -> None:
    """Write a tracked text file with CRLF terminators, as bytes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))


def write_json(path: Path, doc) -> None:
    write_repo_text(path, json.dumps(doc, indent=1, sort_keys=True, ensure_ascii=False) + "\n")


def split_lines(text: str):
    """`(lines, newline)`: the file's lines without terminators, and the terminator it uses."""
    newline = "\r\n" if "\r\n" in text else "\n"
    return text.replace("\r\n", "\n").split("\n"), newline


def read_text(path: Path) -> str:
    return path.read_bytes().decode("utf-8").replace("\r\n", "\n")


# ---------------------------------------------------------------------------
# wago.tools
# ---------------------------------------------------------------------------

def http_get(url: str, accept: str = "*/*"):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    try:
        return urllib.request.urlopen(req, timeout=300)
    except urllib.error.HTTPError as err:  # 400: no such table on this build; 403: the User-Agent
        raise SystemExit("HTTP %s fetching %s: %s" % (err.code, url, err.reason))
    except urllib.error.URLError as err:
        raise SystemExit("Could not reach %s: %s (a new run needs network access)" % (url, err.reason))


def newest_live(builds: list) -> str:
    """The first (newest) build that is not a background download, from one product's list."""
    for build in builds:
        if not build.get("is_bgdl"):
            return build["version"]
    raise SystemExit("The builds API lists no live (non-bgdl) build; pass --build.")


def live_build(product: str) -> str:
    data = json.load(http_get(BUILDS_URL, accept="application/json"))
    return newest_live(data.get(product) or [])


def tables_for(flavor: str) -> tuple:
    return COMMON_TABLES + (FOREVER_TABLES if flavor == "forever" else ())


def fetch_table(table: str, build: str, cache_dir: Path) -> Path:
    """One table's CSV for `build`, from the cache or streamed into it (renamed only when whole)."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    dest = cache_dir / ("%s-%s.csv" % (table, build))
    if dest.exists():
        log("  %-18s cached (%.1f MB)" % (table, dest.stat().st_size / 1e6))
        return dest
    url = CSV_URL.format(table=table, build=build)
    tmp = dest.with_suffix(".csv.part")
    log("  %-18s fetching %s" % (table, url))
    with http_get(url, accept="text/csv") as response, tmp.open("wb") as handle:
        shutil.copyfileobj(response, handle, DOWNLOAD_CHUNK)
    tmp.replace(dest)
    return dest


def freeze_tables(bundle: Path, flavor: str, build: str, cache_dir: Path, replay: bool) -> dict:
    """`{table: raw member}`: every table in the bundle's raw/, gzipped from the cache unless
    `replay`, where the bundle must already hold each one."""
    raw = bundle / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    out = {}
    for table, _why in tables_for(flavor):
        member = raw / ("%s.csv.gz" % table)
        if replay:
            if not member.exists():
                raise SystemExit("--replay: %s is missing raw/%s.csv.gz; a bundle that cannot hand "
                                 "back every table it read cannot reproduce its numbers." % (bundle, table))
        else:
            source = fetch_table(table, build, cache_dir)
            # mtime=0 and no file name in the header: the same CSV always freezes to the same bytes.
            with source.open("rb") as src, member.open("wb") as raw_out, \
                    gzip.GzipFile(filename="", mode="wb", compresslevel=9, fileobj=raw_out, mtime=0) as dst:
                shutil.copyfileobj(src, dst, DOWNLOAD_CHUNK)
        out[table] = member
    return out


def iter_csv(path: Path):
    """Each row as a dict, one at a time; a `.gz` member is decompressed on the fly. Columns are
    addressed by header name, never by position (clients-§10)."""
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            yield row


def _int(value) -> int:
    try:
        return int(value or 0)
    except ValueError:
        return 0


def _num(value) -> float:
    try:
        return float(value or 0)
    except ValueError:
        return 0.0


# ---------------------------------------------------------------------------
# The repo's own files: the seeds, the presets, the melee reach
# ---------------------------------------------------------------------------

def read_seeds(path: Path) -> dict:
    """`{flavor: {"classes": {CLASS: {list: [ids]}}, "names": {id: comment name}}}` from
    defaults/SpellSeeds.lua. A list a class does not carry is absent. Comments name ids for the
    renamed flag; code never sits on a comment line in this file."""
    lines = read_text(path).split("\n")
    out, flavor, cls = {}, None, None
    for line in lines:
        match = FLAVOR_OPEN.match(line)
        if match:
            flavor, cls = match.group(1), None
            out[flavor] = {"classes": {}, "names": {}}
            continue
        if flavor is None:
            continue
        code, _, comment = line.partition("--")
        for name, sid in COMMENT_NAME.findall(comment):
            out[flavor]["names"][int(sid)] = name
        match = CLASS_OPEN.match(code)
        if match:
            cls = match.group(1)
            out[flavor]["classes"][cls] = {}
        if cls is None:
            continue
        for key, body in FLAT_LIST.findall(code):
            lst = "melee." + key if key in ("cat", "bear") else key
            out[flavor]["classes"][cls][lst] = [int(i) for i in re.findall(r"\d+", body)]
    for flavor_name in FLAVORS:
        if not out.get(flavor_name, {}).get("classes"):
            raise SystemExit("%s: no `%s = {` block with class seeds." % (path, flavor_name))
    return out


def _bands(text: str) -> list:
    out = []
    for frm, to, label, role, gap, beyond in BAND_CALL.findall(text):
        rule = ("spell:" + role) if role else ("gap" if gap else ("beyond" if beyond else None))
        out.append({"from": int(frm), "to": None if to == "nil" else int(to), "label": label, "rule": rule})
    return out


def _block(lines: list, opener: re.Pattern) -> str:
    """The text from the line `opener` matches to its closing line at the same indent."""
    for i, line in enumerate(lines):
        match = opener.match(line)
        if match:
            indent = len(line) - len(line.lstrip())
            for j in range(i + 1, len(lines)):
                if lines[j].strip().startswith("}") and len(lines[j]) - len(lines[j].lstrip()) == indent:
                    return "\n".join(lines[i:j + 1])
    raise SystemExit("%s: no block matching %s." % (PRESETS_FILE.name, opener.pattern))


def read_presets(path: Path) -> dict:
    """`{"presets": {key: [band]}, "default": {CLASS: key}}` from defaults/BandSetPresets.lua: the
    four preset keys (hunter per client, as `hunter.forever` and `hunter.retail`) and CLASS_DEFAULT
    (a class it does not name gets melee_ranged, Presets.DefaultFor)."""
    lines = read_text(path).split("\n")
    presets = {}
    for key in ("melee_ranged", "caster40", "healer"):
        presets[key] = _bands(_block(lines, re.compile(r"^Presets\.%s = \{" % key)))
    hunters = _block(lines, re.compile(r"^local HUNTER_BY_CLIENT = \{")).split("\n")
    for client in FLAVORS:
        presets["hunter." + client] = _bands(_block(hunters, re.compile(r"^    %s = \{" % client)))
    defaults = {}
    for cls, key in re.findall(r"\b([A-Z]+) = \"(\w+)\"", _block(lines, re.compile(r"^local CLASS_DEFAULT = \{"))):
        defaults[cls] = key
    for key, bands in presets.items():
        if not bands:
            raise SystemExit("%s: preset %s parsed no band(...) rows." % (path, key))
    return {"presets": presets, "default": defaults}


def read_melee_reach(path: Path) -> int:
    match = re.search(r"^local MELEE_REACH_YD = (\d+)", read_text(path), re.M)
    if not match:
        raise SystemExit("%s: no `local MELEE_REACH_YD = <yd>`." % path)
    return int(match.group(1))


def preset_for(presets: dict, flavor: str, cls: str) -> str:
    key = presets["default"].get(cls, "melee_ranged")
    return "hunter." + flavor if key == "hunter" else key


def role_band(bands: list, role: str):
    for band in bands:
        if band["rule"] == "spell:" + role:
            return band
    return None


def band_label(bands: list, yd: float) -> str:
    """The label of the band whose yards hold `yd` as a far reach: from < yd <= to."""
    for band in bands:
        if yd > band["from"] and (band["to"] is None or yd <= band["to"]):
            return band["label"]
    return bands[0]["label"] if bands else ""


# ---------------------------------------------------------------------------
# The build's facts
# ---------------------------------------------------------------------------

class Facts:
    """What the checks read off one build's tables."""

    def __init__(self, tables: dict):
        self.names = {_int(r["ID"]): r["Name_lang"] for r in iter_csv(tables["SpellName"])}
        self.range_index = {}
        for r in iter_csv(tables["SpellMisc"]):
            spell = _int(r["SpellID"])
            if r["DifficultyID"] == "0" and spell not in self.range_index:
                self.range_index[spell] = _int(r["RangeIndex"])
        self.ranges = {_int(r["ID"]): {"name": r["DisplayName_lang"],
                                       "hostile": (_num(r["RangeMin_0"]), _num(r["RangeMax_0"])),
                                       "friendly": (_num(r["RangeMin_1"]), _num(r["RangeMax_1"]))}
                       for r in iter_csv(tables["SpellRange"])}
        self.family = {}
        for r in iter_csv(tables["SpellClassOptions"]):
            self.family.setdefault(_int(r["SpellID"]), _int(r["SpellClassSet"]))
        self.classes = {r["Filename"]: (_int(r["ID"]), _int(r["SpellClassSet"])) for r in iter_csv(tables["ChrClasses"])}
        self.sla = {}
        for r in iter_csv(tables["SkillLineAbility"]):
            self.sla.setdefault(_int(r["Spell"]), []).append((_int(r["ClassMask"]), _int(r["SupercedesSpell"])))
        self.rank = {}
        if "Spell" in tables:
            self.rank = {_int(r["ID"]): r["NameSubtext_lang"] for r in iter_csv(tables["Spell"])}
        self.by_name = {}
        if self.rank:
            for spell, name in self.names.items():
                self.by_name.setdefault(name, []).append(spell)
        self._sentinels()

    def _sentinels(self) -> None:
        missing = ["%d %s" % (s, n) for s, n in sorted(SENTINELS.items())
                   if self.names.get(s) != n or self.range_of(s, "hostile") is None]
        index, reach = COMBAT_RANGE
        if self.ranges.get(index, {}).get("hostile", (0, 0))[1] != reach:
            missing.append("SpellRange %d (Combat Range, %g yd)" % (index, reach))
        if missing:
            raise SystemExit("Seed sentinel gate FAILED: %s not answered. The tables moved; fix the "
                             "reader before ruling." % ", ".join(missing))

    def range_of(self, spell: int, side: str):
        """`(index, name, min, max)` for `spell` on `side` ("hostile" | "friendly"), or None."""
        index = self.range_index.get(spell)
        row = self.ranges.get(index) if index is not None else None
        if row is None:
            return None
        lo, hi = row[side]
        return index, row["name"], lo, hi

    def class_verdict(self, spell: int, cls: str) -> str:
        """"ok", "mismatch" or "unknown": SkillLineAbility's ClassMask first, then the family."""
        info = self.classes.get(cls)
        if not info:
            return "unknown"
        bit = 1 << (info[0] - 1)
        rows = self.sla.get(spell, [])
        if any(mask & bit for mask, _sup in rows):
            return "ok"
        fam = self.family.get(spell, 0)
        if fam and fam == info[1]:
            return "ok"
        if fam and fam != info[1]:
            return "mismatch"
        return "unknown"

    def rank_issue(self, spell: int):
        """A reason the Forever id is not rank 1, or None."""
        text = self.rank.get(spell, "")
        match = RANK_RE.match(text)
        if match and int(match.group(1)) > 1:
            return "its rank text is %r" % text
        name, fam = self.names.get(spell), self.family.get(spell, 0)
        if not match and fam:
            # Only a row a player can learn (a SkillLineAbility row) is a rank: 410156, a "Rank 1"
            # Stormstrike on 1.60.1.71091, is the talent's extra-attack proc, never in a spellbook.
            firsts = sorted(o for o in self.by_name.get(name, ()) if o != spell and o in self.sla
                            and self.family.get(o, 0) == fam and self.rank.get(o) == "Rank 1")
            if firsts:
                return "a same-family %r row is Rank 1: %s" % (name, ", ".join(str(o) for o in firsts))
        for _mask, sup in self.sla.get(spell, []):
            if sup and self.names.get(sup) == name:
                return "it supersedes %d, also named %r" % (sup, name)
        return None


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

def _side(lst: str) -> str:
    return "friendly" if lst == "friendly" else "hostile"


def _yd(value: float):
    return int(value) if float(value).is_integer() else value


def verdict(facts: Facts, flavor: str, cls: str, lst: str, spell: int, comment_names: dict,
            bands: list, reach: int) -> dict:
    """One shipped id's facts and the id-kind flags it raises."""
    name = facts.names.get(spell)
    rng = facts.range_of(spell, _side(lst))
    lo, hi = (rng[2], rng[3]) if rng else (0.0, 0.0)
    v = {"class": cls, "list": lst, "id": spell, "name": name or "", "rank": facts.rank.get(spell, ""),
         "rangeIndex": rng[0] if rng else None, "rangeName": rng[1] if rng else "",
         "min": _yd(lo), "max": _yd(hi), "classCheck": facts.class_verdict(spell, cls),
         "band": band_label(bands, hi) if hi > 0 else "", "flags": []}
    flags = v["flags"]

    def flag(kind, why):
        flags.append({"kind": kind, "why": why})

    if not name:
        flag("unnamed", "no SpellName row")
        return v
    said = comment_names.get(spell)
    if said and said.lower() != name.lower():
        flag("renamed", "the file's comment says %r, the build says %r" % (said, name))
    if v["classCheck"] == "mismatch":
        flag("class", "family %d is not %s's, and no SkillLineAbility row lets %s learn it"
             % (facts.family.get(spell, 0), cls, cls))
    if flavor == "forever":
        issue = facts.rank_issue(spell)
        if issue:
            flag("rank", issue)
    if hi <= 0:
        flag("no-range", "RangeIndex %s reaches 0 yd: no range question can be asked of it"
             % (rng[0] if rng else "(no SpellMisc row)"))
        return v
    if lst == "ladder" and lo > 0:
        flag("ladder-min", "%g-%g yd: a min range, so spellRung never makes it a rung" % (lo, hi))
    if lst.startswith("melee") and (lo > 0 or hi > reach):
        flag("melee-reach", "%g-%g yd: a melee anchor must reach 0 to %d yd" % (lo, hi, reach))
    if lst == "ranged" and hi <= reach:
        flag("ranged-reach", "%g yd: a ranged anchor must reach past %d yd" % (hi, reach))
    return v


def role_flags(facts: Facts, cls: str, lists: dict, preset_key: str, bands: list, healer: list) -> list:
    """The per-role flags: band-reach (ranged against the default preset, friendly against Healer)
    and gap-fit (the default preset's dead zone)."""
    out = []
    for role, role_bands, where in (("ranged", bands, preset_key), ("friendly", healer, "healer")):
        ids = [s for s in lists.get(role, []) if facts.range_of(s, _side(role))]
        band = role_band(role_bands, role)
        if not ids or not band or band["to"] is None:
            continue
        top = max(ids, key=lambda s: facts.range_of(s, _side(role))[3])  # ties: the first (seed order)
        hi = facts.range_of(top, _side(role))[3]
        if hi != band["to"]:
            out.append({"key": "shipped:band-reach:%s.%s:%d" % (cls, role, top), "kind": "band-reach",
                        "class": cls, "list": role, "id": top, "name": facts.names.get(top, ""),
                        "why": "the longest %s reach is %g yd (%d); preset %s's %s band ends at %d yd"
                               % (role, hi, top, where, band["label"], band["to"])})
    gaps = [b for b in bands if b["rule"] == "gap"]
    if gaps:
        gap = gaps[0]
        ranged = [s for s in lists.get("ranged", []) if facts.range_of(s, "hostile")]
        mins = {s: facts.range_of(s, "hostile")[2] for s in ranged}
        why = []
        if not any(m > 0 for m in mins.values()):
            why.append("no ranged anchor has a min range, so the gap can never hold")
        why += ["ranged %d's min range is %g yd, not the gap's far edge %d" % (s, m, gap["to"])
                for s, m in mins.items() if m > 0 and m != gap["to"]]
        melee = [s for k, v in lists.items() if k.startswith("melee") for s in v if facts.range_of(s, "hostile")]
        why += ["melee %d reaches %g yd, not the gap's near edge %d" % (s, facts.range_of(s, "hostile")[3], gap["from"])
                for s in melee if facts.range_of(s, "hostile")[3] != gap["from"]]
        if why:
            first = (ranged or [0])[0]
            out.append({"key": "shipped:gap-fit:%s.ranged:%d" % (cls, first), "kind": "gap-fit", "class": cls,
                        "list": "ranged", "id": first, "name": facts.names.get(first, ""), "why": "; ".join(why)})
    return out


def derive_doc(tables: dict, flavor: str, build: str, date: str, seeds_path: Path, presets_path: Path,
               range_path: Path) -> dict:
    facts = Facts(tables)
    seeds = read_seeds(seeds_path)[flavor]
    presets = read_presets(presets_path)
    reach = read_melee_reach(range_path)
    healer = presets["presets"]["healer"]
    verdicts, flags, preset_of = [], [], {}
    for cls in sorted(seeds["classes"]):
        lists = seeds["classes"][cls]
        key = preset_for(presets, flavor, cls)
        preset_of[cls] = key
        bands = presets["presets"][key]
        for lst in LIST_NAMES:
            for spell in lists.get(lst, []):
                v = verdict(facts, flavor, cls, lst, spell, seeds["names"], healer if lst == "friendly" else bands, reach)
                verdicts.append(v)
                for f in v["flags"]:
                    flags.append({"key": "shipped:%s:%s.%s:%d" % (f["kind"], cls, lst, spell), "kind": f["kind"],
                                  "class": cls, "list": lst, "id": spell, "name": v["name"], "why": f["why"]})
        flags += role_flags(facts, cls, lists, key, bands, healer)
    mentioned = [{"id": s, "comment": n, "name": facts.names.get(s, "")} for s, n in sorted(seeds["names"].items())]
    return {
        "client": flavor, "product": FLAVORS[flavor]["product"], "build": build, "date": date,
        "tool": "tools/seeds/seeds.py derive", "meleeReachYd": reach, "presetOf": preset_of,
        "shipped": {"classes": len(seeds["classes"]), "ids": len(verdicts)},
        "verdicts": verdicts, "commentNames": mentioned, "candidates": [], "flags": flags,
    }


# ---------------------------------------------------------------------------
# Bundles
# ---------------------------------------------------------------------------

def bundles(root: Path, flavor: str) -> list:
    """Every bundle of `flavor` under `root` that holds a candidates.json, oldest first."""
    return sorted(p for p in root.glob("*-" + flavor) if (p / "candidates.json").exists())


def bundle_build(bundle: Path) -> str:
    return json.loads((bundle / "candidates.json").read_text(encoding="utf-8"))["build"]


def status_line(live: str, found: list) -> str:
    """`CURRENT <build> (<bundle>)`, or `NEW <build> ...`; the first word is what the command reads."""
    if not found:
        return "NEW %s (no bundle yet)" % live
    built = bundle_build(found[-1])
    if built == live:
        return "CURRENT %s (%s)" % (live, found[-1].name)
    return "NEW %s (last ruled %s, %s)" % (live, built, found[-1].name)


def sources_md(flavor: str, build: str, date: str, replay: bool) -> str:
    info = FLAVORS[flavor]
    lines = ["# Sources — seed validation, %s (%s)" % (date, flavor), "",
             "Generated by `tools/seeds/seeds.py derive`. Frozen: this directory is never edited after",
             "the run, apart from the hand-written `ANALYSIS.md`.", "",
             "| Field | Value |", "| --- | --- |",
             "| Client | `%s` (%s, wago product `%s`) |" % (flavor, info["title"], info["product"]),
             "| Build | `%s` (the newest live, non-bgdl `%s` build) |" % (build, info["product"]),
             "| Fetched | %s%s |" % (date, " (replayed from raw/)" if replay else ""),
             "| User-Agent | `%s` |" % USER_AGENT,
             "| Builds API | <%s> |" % BUILDS_URL, "", "## Tables", "",
             "| Table | Why | URL |", "| --- | --- | --- |"]
    lines += ["| `%s` | %s | <%s> |" % (t, why, CSV_URL.format(table=t, build=build)) for t, why in tables_for(flavor)]
    lines += ["", "## Repo files read", "",
              "- `defaults/SpellSeeds.lua`: the shipped ids, and the names its comments give them.",
              "- `defaults/BandSetPresets.lua`: each class's default preset, its bands and their rules.",
              "- `modules/Range.lua`: `MELEE_REACH_YD`.", "",
              "The gzipped exports are in `raw/`. Re-derive offline with `--replay`; a new run needs",
              "network access to wago.tools.", ""]
    return "\n".join(lines)


def _cell(text) -> str:
    return str("" if text is None else text).replace("|", "\\|")


def _range(v: dict) -> str:
    if v["rangeIndex"] is None:
        return "(none)"
    return "%s-%s (%d %s)" % (v["min"], v["max"], v["rangeIndex"], v["rangeName"])


def diff_md(doc: dict) -> str:
    lines = ["# Diff — shipped seeds against DB2, %s (%s, build %s)" % (doc["date"], doc["client"], doc["build"]), "",
             "Generated by `tools/seeds/seeds.py derive`. One row per shipped id and list; a list is what",
             "the code asks of the id (`docs/validate-seeds.md`, *What is checked*). Range is the hostile",
             "range (the friendly one for `friendly`), in yards; Band is where the max reach falls in the",
             "class's default preset (Healer for `friendly`). `MELEE_REACH_YD` is %d." % doc["meleeReachYd"], "",
             "Shipped: %d classes, %d ids across their lists. Flags: %d." % (
                 doc["shipped"]["classes"], doc["shipped"]["ids"], len(doc["flags"])), ""]
    by_class = {}
    for v in doc["verdicts"]:
        by_class.setdefault(v["class"], []).append(v)
    for cls in sorted(by_class):
        lines += ["## %s (default preset `%s`)" % (cls, doc["presetOf"][cls]), "",
                  "| List | Id | Name | Rank | Range | Band | Class | Flags |",
                  "| --- | --- | --- | --- | --- | --- | --- | --- |"]
        for v in by_class[cls]:
            lines.append("| %s | `%d` | %s | %s | %s | %s | %s | %s |" % (
                v["list"], v["id"], _cell(v["name"]) or "(no row)", _cell(v["rank"]) or "-", _cell(_range(v)),
                _cell(v["band"]) or "-", v["classCheck"], ", ".join(f["kind"] for f in v["flags"]) or "-"))
        lines.append("")
    lines += ["## Flags", ""] + (["- `%s` %s: %s" % (f["key"], _cell(f["name"]) or "(no row)", f["why"])
                                  for f in doc["flags"]] or ["None."])
    lines += ["", "## Ids the comments name", ""] + (
        ["- `%d` comment %s, build %s" % (c["id"], c["comment"], c["name"] or "(no row)") for c in doc["commentNames"]]
        or ["None."])
    return "\n".join(lines + [""])


def load_doc(bundle: Path) -> dict:
    path = bundle / "candidates.json"
    if not path.exists():
        raise SystemExit("%s has no candidates.json: run seeds.py derive first." % bundle)
    return json.loads(path.read_text(encoding="utf-8"))


def all_keys(doc: dict) -> list:
    return [c["key"] for c in doc["candidates"]] + [f["key"] for f in doc["flags"]]


def unruled_keys(doc: dict, rulings: dict) -> list:
    return [key for key in all_keys(doc) if key not in rulings]


# ---------------------------------------------------------------------------
# Rulings (data, keyed by class, list and id, never by build)
# ---------------------------------------------------------------------------

def rulings_path(flavor: str) -> Path:
    return HERE / ("%s_rulings.json" % flavor)


def load_rulings(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save_rulings(path: Path, rulings: dict) -> None:
    write_repo_text(path, json.dumps(rulings, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def read_tsv(path: Path) -> list:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise SystemExit("%s: a ruling line is key<TAB>ruling<TAB>reason; got %r" % (path, line))
        out.append(tuple(p.strip() for p in parts))
    return out


def set_ruling(rulings: dict, key: str, ruling: str, reason: str) -> None:
    """Record one ruling; a malformed key, ruling or reason is a SystemExit naming it."""
    match = KEY.match(key)
    if not match:
        raise SystemExit("%r is not shipped:<kind>:<CLASS>.<list>:<id>." % key)
    kind, lst = match.group("kind"), match.group("list")
    if kind in ROLE_KINDS:
        allowed, lists = ROLE_RULINGS, ("ranged", "friendly")
    elif kind in ID_KINDS:
        allowed, lists = ID_RULINGS, LIST_NAMES
    else:
        raise SystemExit("%r: no flag kind %r." % (key, kind))
    if lst not in lists:
        raise SystemExit("%r: %s takes no list %r." % (key, kind, lst))
    if ruling not in allowed:
        raise SystemExit("the ruling for %s must be %s; got %r." % (key, " or ".join(allowed), ruling))
    reason = (reason or "").strip()
    if not reason or "\n" in reason:
        raise SystemExit("the reason for %s must be one non-empty line." % key)
    rulings[key] = {"ruling": ruling, "reason": reason}


# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

def _drop_ids(body: str, ids: set) -> str:
    kept = [i for i in re.findall(r"\d+", body) if int(i) not in ids]
    return "{ %s }" % ", ".join(kept) if kept else "{}"


def apply_seeds(path: Path, flavor: str, removals: dict) -> list:
    """Remove `removals` = {(CLASS, list): {ids}} from `flavor`'s block; returns the change log.
    Keeps the file's own newline and every other byte."""
    lines, newline = split_lines(path.read_bytes().decode("utf-8"))
    changes, current, cls = [], None, None
    for i, line in enumerate(lines):
        match = FLAVOR_OPEN.match(line)
        if match:
            current, cls = match.group(1), None
            continue
        if current != flavor:
            continue
        code, sep, comment = line.partition("--")
        match = CLASS_OPEN.match(code)
        if match:
            cls = match.group(1)
        if cls is None:
            continue

        def repl(m):
            key = m.group(1)
            lst = "melee." + key if key in ("cat", "bear") else key
            drop = removals.get((cls, lst), set())
            present = {int(x) for x in re.findall(r"\d+", m.group(2))}
            gone = sorted(present & drop)
            if not gone:
                return m.group(0)
            changes.extend("%s %s.%s: -%d" % (flavor, cls, lst, g) for g in gone)
            return "%s = %s" % (key, _drop_ids(m.group(2), drop))

        new_code = FLAT_LIST.sub(repl, code)
        if new_code != code:
            lines[i] = new_code + sep + comment
    if changes:
        path.write_bytes(newline.join(lines).encode("utf-8"))
    return changes


def apply_doc(doc: dict, rulings: dict, seeds_path: Path) -> list:
    unruled = unruled_keys(doc, rulings)
    if unruled:
        raise SystemExit("apply refused: %d key(s) unruled (seeds.py check lists them)." % len(unruled))
    removals = {}
    for f in doc["flags"]:
        if f["kind"] in ID_KINDS and rulings[f["key"]]["ruling"] == "remove":
            removals.setdefault((f["class"], f["list"]), set()).add(f["id"])
    return apply_seeds(seeds_path, doc["client"], removals)


# ---------------------------------------------------------------------------
# RULINGS.md
# ---------------------------------------------------------------------------

def rulings_md(doc: dict, rulings: dict, date: str) -> str:
    tally = {}
    for key in all_keys(doc):
        r = rulings.get(key, {}).get("ruling", "unruled")
        tally[r] = tally.get(r, 0) + 1
    unruled = unruled_keys(doc, rulings)
    lines = ["# Rulings — seed validation, %s (%s, build %s)" % (doc["date"], doc["client"], doc["build"]), "",
             "Generated by `tools/seeds/seeds.py report` on %s from this bundle's `candidates.json` and" % date,
             "`tools/seeds/%s_rulings.json`. Do not edit by hand." % doc["client"], "",
             "Shipped: %d ids across %d classes. %d candidates, %d flags: %s." % (
                 doc["shipped"]["ids"], doc["shipped"]["classes"], len(doc["candidates"]), len(doc["flags"]),
                 ", ".join("%d %s" % (n, r) for r, n in sorted(tally.items())) or "none"), ""]
    if unruled:
        lines += ["## Unruled — %d" % len(unruled), ""] + ["- `%s`" % k for k in unruled] + [""]
    lines += ["## Candidates", "", "None: the seeds are hand-curated, so a run proposes no new ids.", "",
              "## Shipped-id flags — %d" % len(doc["flags"]), ""]
    if doc["flags"]:
        lines += ["| Kind | Class | List | Id | Build name | Why | Ruling | Reason |",
                  "| --- | --- | --- | --- | --- | --- | --- | --- |"]
        for f in doc["flags"]:
            r = rulings.get(f["key"], {})
            lines.append("| %s | %s | %s | `%d` | %s | %s | %s | %s |" % (
                f["kind"], f["class"], f["list"], f["id"], _cell(f["name"]) or "(no row)", _cell(f["why"]),
                r.get("ruling", "**unruled**"), _cell(r.get("reason"))))
    else:
        lines.append("None.")
    return "\n".join(lines + [""])


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def _date(value: str) -> str:
    if not DATE_RE.match(value):
        raise argparse.ArgumentTypeError("a date is YYYY-MM-DD; got %r" % value)
    return value


def _rulings(args) -> Path:
    return args.rulings or rulings_path(args.flavor)


def cmd_status(args) -> int:
    print(status_line(live_build(FLAVORS[args.flavor]["product"]), bundles(args.root, args.flavor)))
    return 0


def cmd_derive(args) -> int:
    if not args.bundle.name.endswith("-" + args.flavor):
        raise SystemExit("--bundle %s: a %s bundle is named <date>-%s." % (args.bundle, args.flavor, args.flavor))
    if args.replay:
        build = args.build or (bundle_build(args.bundle) if (args.bundle / "candidates.json").exists() else None)
        if not build:
            raise SystemExit("--replay %s has no candidates.json to take its build from; pass --build." % args.bundle)
    else:
        build = args.build or live_build(FLAVORS[args.flavor]["product"])
    log("Build %s (%s)" % (build, args.flavor))
    tables = freeze_tables(args.bundle, args.flavor, build, args.cache_dir, args.replay)
    doc = derive_doc(tables, args.flavor, build, args.date, args.seeds, args.presets, args.range_file)
    write_json(args.bundle / "candidates.json", doc)
    write_repo_text(args.bundle / "SOURCES.md", sources_md(args.flavor, build, args.date, args.replay))
    write_repo_text(args.bundle / "DIFF.md", diff_md(doc))
    unruled = unruled_keys(doc, load_rulings(_rulings(args)))
    kinds = {}
    for f in doc["flags"]:
        kinds[f["kind"]] = kinds.get(f["kind"], 0) + 1
    log("%d ids over %d classes; flags: %s" % (doc["shipped"]["ids"], doc["shipped"]["classes"],
                                               ", ".join("%d %s" % (n, k) for k, n in sorted(kinds.items())) or "none"))
    log("0 candidates, %d flags, %d unruled" % (len(doc["flags"]), len(unruled)))
    return 0


def cmd_rule(args) -> int:
    todo = [(key, args.ruling, args.reason) for key in (args.key or ())]
    if args.tsv:
        todo += read_tsv(args.tsv)
    if not todo:
        raise SystemExit("rule needs --key (with --ruling and --reason) or --tsv.")
    known = set(all_keys(load_doc(args.bundle))) if args.bundle else None
    path = _rulings(args)
    rulings = load_rulings(path)
    for key, ruling, reason in todo:
        if known is not None and key not in known:
            raise SystemExit("%s is not a candidate or flag in %s/candidates.json." % (key, args.bundle))
        set_ruling(rulings, key, ruling, reason)
    save_rulings(path, rulings)
    log("Recorded %d ruling(s) in %s" % (len(todo), path))
    return 0


def cmd_check(args) -> int:
    doc = load_doc(args.bundle)
    unruled = unruled_keys(doc, load_rulings(_rulings(args)))
    if not unruled:
        print("OK: every candidate and flag in %s is ruled." % args.bundle.name)
        return 0
    rows = {f["key"]: f for f in doc["flags"]}
    print("%d unruled:" % len(unruled))
    for key in unruled:
        print("  %s  %s: %s" % (key, rows[key]["name"] or "(no row)", rows[key]["why"]))
    return 1


def cmd_report(args) -> int:
    write_repo_text(args.bundle / "RULINGS.md", rulings_md(load_doc(args.bundle), load_rulings(_rulings(args)), args.date))
    log("Wrote %s" % (args.bundle / "RULINGS.md"))
    return 0


def cmd_apply(args) -> int:
    doc = load_doc(args.bundle)
    if doc["client"] != args.flavor:
        raise SystemExit("%s is a %s bundle, not %s." % (args.bundle, doc["client"], args.flavor))
    changes = apply_doc(doc, load_rulings(_rulings(args)), args.seeds)
    for line in changes:
        log("  " + line)
    log("%d change(s)" % len(changes))
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Re-validate Range Master's spell seeds against a wago.tools build.",
                                     epilog="The contract: docs/validate-seeds.md.")
    parser.add_argument("--rulings", type=Path, default=None, help="default: tools/seeds/<flavor>_rulings.json")
    parser.add_argument("--seeds", type=Path, default=SEEDS_FILE)
    parser.add_argument("--presets", type=Path, default=PRESETS_FILE)
    parser.add_argument("--range-file", type=Path, default=RANGE_FILE)
    parser.add_argument("--cache-dir", type=Path, default=CACHE_DIR)
    sub = parser.add_subparsers(dest="command", required=True)
    status = sub.add_parser("status", help="is there a live build newer than the newest bundle?")
    status.add_argument("--flavor", choices=sorted(FLAVORS), required=True)
    status.add_argument("--root", type=Path, default=RESEARCH)
    derive = sub.add_parser("derive", help="freeze one build's tables; verdicts and flags into candidates.json")
    derive.add_argument("--flavor", choices=sorted(FLAVORS), required=True)
    derive.add_argument("--bundle", type=Path, required=True)
    derive.add_argument("--date", type=_date, required=True)
    derive.add_argument("--build", default=None, help="pin this build (default: the flavor's newest live build)")
    derive.add_argument("--replay", action="store_true", help="read only the bundle's raw/, no network")
    rule = sub.add_parser("rule", help="record rulings (the only writer of the rulings file)")
    rule.add_argument("--flavor", choices=sorted(FLAVORS), required=True)
    rule.add_argument("--key", action="append")
    rule.add_argument("--ruling")
    rule.add_argument("--reason")
    rule.add_argument("--tsv", type=Path, help="key<TAB>ruling<TAB>reason lines")
    rule.add_argument("--bundle", type=Path, help="refuse keys this bundle's candidates.json lacks")
    for name, helptext in (("check", "exit 1 while anything is unruled"),
                           ("report", "write the bundle's RULINGS.md"),
                           ("apply", "remove the ids ruled `remove` from the seed file")):
        cmd = sub.add_parser(name, help=helptext)
        cmd.add_argument("--flavor", choices=sorted(FLAVORS), required=True)
        cmd.add_argument("--bundle", type=Path, required=True)
        if name != "check":
            cmd.add_argument("--date", type=_date, required=True)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    return {"status": cmd_status, "derive": cmd_derive, "rule": cmd_rule, "check": cmd_check,
            "report": cmd_report, "apply": cmd_apply}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
