# Dependencies — Ka0s Range Master

What you need installed to build, run, test or release this addon. Commands are for
**WSL2 / Ubuntu** (the collection's development environment). How to *verify* the addon once
you are set up is `docs/testing.md`; this file only covers *what to install* (documentation-§7).

Every entry says what needs it and how that is known. Anything only plausibly required is
marked as such rather than listed as a requirement.

| Group | Who needs it | Short answer |
|---|---|---|
| Runtime (in-game) | Players | World of Warcraft, Retail (patch 12.1.5) or WoW Forever. Nothing else. |
| Development | Contributors | Lua **5.1** (+ `luac`), `luacheck`, `lizard`, `git`, `bash`, `~/.claude/dev-copilot/bin/ka0s-bounded` (the dev-copilot plugin), `python3` with `pytest` (the seed tool's suite), and a POSIX shell with `ls` and `grep`. |
| Release / assets | Whoever regenerates the logo | Pillow, by hand, only when the logo art changes. Not needed to build, run or test. |

## Runtime (in-game) — what a player needs

- **World of Warcraft, Retail or WoW Forever.** `RangeMaster.toc` declares one interface line for
  both clients, `## Interface: 120105, 16001`, Retail's number first (toc-file-§3). The client is
  asked only through `NS.Compat` (`core/Compat.lua`, clients-§3).
- **Nothing else.** The TOC declares no `## Dependencies`. Every library it loads — LibStub,
  CallbackHandler-1.0, the Ace3 modules, LibDataBroker-1.1, LibDBIcon-1.0, LibKa0s,
  LibRangeCheck-3.0 and LibSharedMedia-3.0 — is vendored under `libs/` and listed in the TOC's
  `# Libraries` block. `## OptionalDeps:` names the vendored libraries for load ordering, not as
  things to download (library-stack).
- **EllesmereUI, optional.** A separate addon, never vendored and never required. It is named in
  `## OptionalDeps:` only so it loads first when the player has it: `core/SkinSetup.lua` registers
  the skin owner at file load, and the vendored `LibKa0s-Skin-1.0` provider offers it to EllesmereUI
  and paints through it only while General → Skin's source is EllesmereUI. Without it the source is
  the Ka0s skins alone. Its unit frames are also an attach target: the `ellesmere` frame provider
  (`modules/FrameProviders.lua`) looks its target, focus and pet frames up by global name, and the
  addon never reads `EllesmereUIDB`.

### Vendored libraries and where each came from

| Library | Source | Version | Used for |
|---|---|---|---|
| LibKa0s (`libs/LibKa0s/`) and its test kit (`tests/_kit/`) | the `LibKa0s` repo, tag `v1.113.0`, by `git archive` | v1.113.0, the tag root `CLAUDE.md`'s Bundles line names | every shared subsystem: printer, console, options, slash, launcher, perf, skins, schema, bus, lifecycle, compat; `media/icons/` pruned to `CLAUDE.md`'s `LibKa0s icons:` line, `media/sounds/` pruned to none |
| LibRangeCheck-3.0 (`libs/LibRangeCheck-3.0/`) | <https://github.com/WeakAuras/LibRangeCheck-3.0>, branch `main`, commit `3f9e454971a011d08fc1b5c73c0a0ad4168c2f44` (2026-11-07, "Check for secret values in Forever as well") | MINOR 39 (`MINOR_VERSION` in `libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua`) | the range estimate (`GetRange`) the range engine wraps; `LibRangeCheck-3.0.lua` and its MIT `LICENSE`, byte-identical to that commit |
| Ace3, CallbackHandler-1.0, LibStub, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0 | copied from the sibling Ka0s addon AuraMaster's `libs/` (library-stack-§3), so versions match the collection | as vendored there | the addon substrate, the launcher and shared media |

## Development — the contributor toolchain

| Tool | Version | Needed for | Evidence |
|---|---|---|---|
| `lua5.1` (+ `luac`) | **5.1 exactly** | the headless suite `lua tests/run.lua`, the offline perf runner `lua tests/perf.lua`, the complexity suite's sighted shadow | `tests/_kit/loader.lua` calls `setfenv` and `loadstring` |
| `luacheck` | any recent | `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .`, the other half of the green gate | `.luacheckrc` at the repo root |
| `ka0s-bounded` | the dev-copilot plugin | the bounded runner lint goes through, because `luacheck` loads no kit and cannot bound itself (testing-§15) | installed with the dev-copilot Claude Code plugin |
| `lizard` | any recent | the `complexity` suite of `tests/_kit/run-automated-tests.sh` (automated-tests-§3) | the runner probes `command -v lizard` |
| `git` | any recent | the vendored-payload gate, the line-ending gate, the layout-cap gate, the lint-config gate and the runner's manifest | `tests/_kit/vendor_sync.lua`, `tests/_kit/test_eol.lua`, `tests/_kit/test_layout_cap.lua`, `tests/test_lintconfig.lua` all shell out to `git` |
| `bash` | any recent | running the vendored automated-test runner and the text tools it pipes through (`sed`, `grep`, `awk`, `date`, `find`, `wc`, `sort`, `head`, `tail`, `tr`) | `tests/_kit/run-automated-tests.sh` is `#!/usr/bin/env bash` |
| POSIX shell with `ls` and `grep` | any | suites that list or scan source files by shelling out | `tests/test_locale.lua` (`ls -1`), `tests/_kit/framework.lua` (`ls -A`) |
| `python3` (3.8+) with `pytest` | any recent | the seed tool `tools/seeds/seeds.py` and its suite `python3 -m pytest -q -p no:cacheprovider tools/seeds`, part of the commit gate; the tool itself is standard library only | `docs/validate-seeds.md`, `## Gate` |

**Lua 5.1 is a requirement, not a preference.** The harness sandboxes each source file with
`setfenv`, which was removed in 5.2. WoW's own client is Lua 5.1 too, which is why the harness can
run the addon source unmodified.

```sh
# Lua 5.1 (luac arrives in the same package) and luacheck
sudo apt-get update
sudo apt-get install -y lua5.1 luarocks
sudo luarocks install luacheck

# lizard — via pipx, NOT pip. Ubuntu 24.04 marks its Python EXTERNALLY-MANAGED (PEP 668),
# so `pip install lizard` fails; pipx installs it into its own venv and puts it on PATH.
sudo apt-get install -y pipx
pipx ensurepath          # then open a new shell, or: source ~/.bashrc
pipx install lizard

# git (bash, ls, grep and the runner's text utilities ship with Ubuntu already)
sudo apt-get install -y git

# verify — each of these must print a version
lua5.1 -v                # Lua 5.1.5 …   (if `lua` is not 5.1, use lua5.1 explicitly)
luac5.1 -v               # Lua 5.1.5 …
luacheck --version       # Luacheck: 1.x
lizard --version         # 1.x
git --version            # git version 2.x

# the seed tool's suite (docs/validate-seeds.md)
sudo apt-get install -y python3-pytest
python3 -m pytest --version
```

Versions are pinned only where a version matters: `lua5.1` is hard, `luacheck` and `lizard` are
"any recent" and pinning them would be false precision.

### Optional: a sibling `../LibKa0s` checkout

`tests/test_vendor_sync.lua` hands the comparison to the vendored `tests/_kit/vendor_sync.lua`, which
reads the tag on root `CLAUDE.md`'s Bundles line out of a checkout at `../LibKa0s` and compares
`libs/LibKa0s/` and `tests/_kit/` against it. Without that checkout the case records a **skip with
its reason**, not a pass and not a failure (testing-§11).

```sh
git clone https://github.com/tusharsaxena/LibKa0s.git ../LibKa0s
git -C ../LibKa0s rev-parse --short v1.113.0   # verify: prints a commit
```

## Release / assets

**One entry: Pillow**, and only for **regenerating** the logos and the indicator art.
`media/logos/rangemaster.logo.128.tga` (the icon) and `media/logos/rangemaster.logo.tga` (the landing
page's 300×300 logo) are committed, uncompressed 32-bit, beside their 2000×2000 `rangemaster.logo.png`
source, and layout-§4's recipe is run by hand when the art changes. The indicator tiles
(`media/textures/indicators/<shape>_<style>.tga`) are committed too and redrawn by
`python3 tools/indicator_art.py` from the repo root (deterministic; `--sheet <png>` also writes a
contact sheet). Nothing is generated at package time. **None of this group is
required to build, run or test the addon.**

```sh
sudo apt-get install -y python3-pil
python3 -c "import PIL; print(PIL.__version__)"   # verify
```

## Am I set up correctly?

```sh
lua tests/run.lua                                     # the suite — must be green
KA0S_KIT_CLIENT=forever lua tests/run.lua             # the same, as WoW Forever — must be green
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .     # must be 0 warnings / 0 errors
python3 -m pytest -q -p no:cacheprovider tools/seeds  # the seed tool's suite — must pass
~/.claude/dev-copilot/bin/ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle
                                                      # the sighted complexity report (release-time); never raw
                                                      # `lizard`, which is blind in Lua (automated-tests-§3)
```

See `docs/testing.md` for what those commands mean and when each is run.
