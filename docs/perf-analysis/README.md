# Perf analysis — the in-game capture store

**In-game captures only.** A person runs `/rm perf` in a live client and copies the result out; no
script can produce one (performance-§8). Offline scenario runs of `tests/perf.lua` are a different
measurement: the vendored runner writes them into that run's bundle under
[`../automated-tests/`](../automated-tests/README.md) (automated-tests-§7). An offline figure says
nothing about frame time and an in-game capture says nothing about allocation, so never read one as
the other.

The store is standing and cumulative, not tied to one investigation, so captures compare across
addon versions. How to read the numbers: [`../performance.md`](../performance.md).

## Bundle naming

```
docs/perf-analysis/<YYYYMMDD-HHMMSS>/
```

One directory per capture, stamped in **local time from the record's own timestamp** — when the
capture happened, not when it was written up. Bundles are **frozen once written** and never pruned;
this README is the one file in the store that is rewritten.

## The three artifacts

| File | What it is |
|---|---|
| `report.md` | What the client printed: the `/rm perf report` summary and the run's lifecycle lines |
| `dump.json` | The record, **byte for byte as the client emitted it** — one line, never pretty-printed or edited |
| `ANALYSIS.md` | The write-up, following the uniform prompt in the standards repo's `PERF_ANALYSIS.md` playbook, every claim citing a file in the same bundle |

## Schema summary

The record shape belongs to `LibKa0s-Perf-1.0`, versioned in the library; the record carries its own
`schema` field and the canonical field-by-field contract lives in the LibKa0s repo
([docs/record-schema.md](https://github.com/tusharsaxena/LibKa0s/blob/master/docs/record-schema.md)).
In outline: the emitting addon (`RangeMaster`) and its version, the client interface, a timestamp and
label, a `context` block (character, class, spec, level, zone, group), a `buckets` map — per bucket
`calls`, `totalMs`, `maxMs`, the declared `within` and, where a call site passed one, the observed
parent — and an `fps` block with the active arm, the suspended arm and their per-frame delta.

This addon's buckets (`core/PerfSetup.lua`, in report order) are `combatEdge`, `ticker.tick`,
`range.get` (within `ticker.tick`), `container.render` (within `ticker.tick`) and `cursor.follow`;
`docs/performance.md` says what each brackets. Never sum a parent and its children; a bucket that
never fired is absent, not zero.

## Taking a capture

```
/rm perf                    status, and the step panel
/rm perf start [label]      out of combat: begins the run, records character, spec, zone, group
/rm perf measure a          arm A — addon active; pull, the arm records while combat lasts
/rm perf measure b          arm B — addon suspended for you; reset and pull again
/rm perf finish             end the run and save it to the ring (prints nothing)
/rm perf report             print the summary and the JSON line
```

Then use the debug console's **Copy** button to lift the report and the JSON out. The same record is
on disk after a `/reload`, in the capture ring `RangeMasterPerfDB` inside
`WTF/Account/ACCOUNT/SavedVariables/RangeMaster.lua`. The ring is a separate top-level global from
`RangeMasterDB`, so a profile copy, reset or switch never touches it (performance-§5). Record a
capture with `/dev-copilot:wow-perf-analysis`, which writes the bundle and this index's row.

## Capture index

No capture has been taken yet. Nobody has played v0.1.0 in a client, and a capture assembled from
the offline scenarios or the source would be a fabrication; the first real capture is
a later, separate run of `/dev-copilot:wow-perf-analysis` on a client paste.

| Stamp | Addon version | Label | What it measured | Bundle |
|---|---|---|---|---|
