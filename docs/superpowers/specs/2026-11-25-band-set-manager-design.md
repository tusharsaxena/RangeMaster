# Band set manager (RangeMaster#21)

The owner asked for this on 2026-11-25, from in-game screenshots of the Band sets page. Their asks, in their words:

- "There is no option to delete a band set - add it".
- "Add band and remove band should be next to each other".
- "I want to be able to see all the class specific band sets - default can be current class - but can we list all here?"
- "There needs to be a way to setup a new band set using one of the shipped prebuilt band sets".
- "If i modify a class specific, can i restore it to the class specific one somehow?"
- "There needs to be a way to copy a bandset from another".

The owner approved the mockup ("Looks good - build it now please"): https://claude.ai/artifact/XRY4HrJGeU4KMMDjnHMkcv.
The owner also accepted both of the lead's picks:
- **Presets are listed read-only.** They are not seeded into the profile.
- **A read-only preset needs an explicit "Use this preset…"** before it can be edited. A first edit never silently makes
  a copy.

## What exists today (checked 2026-11-25 at master cf7f35e)

- `modules/BandSets.lua` is the only writer of `profile.bandSets`, `bandSetOrder` and `nextBandSetId`. It provides Create
  (from a preset key, a bands array or nil), Delete (never the last set), Duplicate, Rename, UniqueName, List, Get,
  DefaultId, SetField, SetBand, SetBandRule, SetBandSound, AddBand, RemoveBand, Snapshot and RestoreSnapshot.
- `defaults/BandSetPresets.lua` has `CLASS_KEYS` (every class preset this client has, in class order), `ORDER` (the
  generic keys) and `DefaultFor`. A preset is copied into the profile and never referenced. A stored set does not remember
  its preset.
- The first-run seed puts the class default first (that's what "(default)" means), then the generic sets.
- `settings/BandSets.lua` lays the page out like this:
  - the picker and **New band set**, then the General and Bands tabs;
  - **Duplicate** and **Delete…** at the bottom of the General tab;
  - **Add band** below the rail, and **Remove band** inside the band's controls.

## Design

### Model (`modules/BandSets.lua`, `defaults/BandSetPresets.lua`)

1. **`set.origin`.** This is a preset key (for example `"paladin"` or `"melee_ranged"`), or nil.
   - Create from a preset key stores it.
   - Duplicate copies it.
   - A blank set or a set copied from one of yours has none.
   - Copy bands from a preset sets it to that preset. Copying from one of your sets copies that set's origin.
2. **Migration.** A new schema step fills in `origin` on stored sets whose name matches a preset's localized name on this
   client, case-insensitively, when only one preset matches. Sets that are seeded later get it from Create.
3. **New members:**
   - `BandSets.PresetKeys()` returns `{ classes = {...CLASS_KEYS}, general = {...ORDER minus "hunter" if it is a class
     key duplicate} }`. The builder checks how `"hunter"` sits in both lists and lists each preset once.
   - `BandSets.Diff(id)` returns the differences from its origin preset as a list of
     `{ band = i|nil, field, mine, preset }`. It answers nil when the set has no origin or the preset is gone, and an empty
     list when the two are identical. A difference in band count is one entry.
   - `BandSets.IsModified(id)` returns true when `Diff` has at least one entry.
   - `BandSets.RestorePreset(id, keepSounds)` replaces the bands, `matchBy` and `unknown` with a fresh copy of its origin
     preset (keeping each band's sound when `keepSounds` is set and the band count matches; otherwise keeping sounds by
     index where the band exists). It keeps the name, id and containers, normalizes the result, and announces.
   - `BandSets.CopyFrom(id, source, opts)`. `source` is a set id or `{ preset = key }`, and `opts` is
     `{ sounds = bool, general = bool }`. It replaces the bands (taking the sounds too when `sounds` is set, otherwise
     keeping existing sounds by index), and `matchBy` and `unknown` when `general` is set. It never copies into itself,
     sets `origin` as described in 1, normalizes and announces.
   - `Create(name, presetKey)` already exists. The New dialog's "copy of one of my sets" uses Duplicate followed by Rename.
4. **Undo.** Before RestorePreset and CopyFrom, the settings layer takes `BandSets.Snapshot()`. The chat line says
   "Restored 'Paladin' to the Paladin preset. Undo" (or "Copied bands into…"), with a clickable Undo that calls
   RestoreSnapshot. Use whatever chat-link or Undo pattern the addon or LibKa0s already has; if there's none, add a
   `/rm undo` verb.

### Settings page (`settings/BandSets.lua`), laid out as the mockup

1. **Header row.** The picker, then **New… · Duplicate · Copy bands from… · Delete…**. These are removed from the General
   tab. Delete is disabled for the last set.
2. **Picker groups.** The groups are headers in the dropdown, and rows under a header are not selectable as headers.
   - **Your band sets**: the default first, tagged "(default)"; a modified set tagged "modified".
   - **Shipped presets · Classes**: every key in `CLASS_KEYS`, with names in class colours and your class tagged "your
     class".
   - **Shipped presets · General**.

   Use the widget set's dropdown, with value keys such as `preset:<key>` for presets. If the dropdown can't draw headers,
   use disabled separator rows.
3. **Origin banner.** For your set with an origin, under the picker: "From the <Preset> preset", plus "· modified (<short
   diff summary>)" when it has been modified, and a **Restore <Preset> preset…** button. The button is enabled only when
   the set is modified.
4. **Viewing a preset.** Choosing a preset selects a *view* of it. It is session state, not stored, and never a container's
   set.
   - The General and Bands tabs show the preset's values with every control disabled.
   - The banner reads "A shipped preset: read-only. Make it yours to use it on a container or to edit it."
   - It has **Use this preset…**, which opens the New dialog prefilled with that preset and its name, and **Copy into a
     set of mine…**, which opens Copy bands from with the preset as source and asks which of your sets to copy into.
   - Duplicate, Copy bands from and Delete are disabled. New… stays enabled.
   - `/rm` selection-relative rows refuse while a preset is viewed, with a clear message.
5. **The New dialog** (built with the addon's existing popup or dialog helpers):
   - a name, unique through UniqueName;
   - start from: (•) a shipped preset, with a dropdown of all presets defaulting to your class; ( ) a copy of one of my
     sets, with a dropdown; ( ) blank, which is one open-ended band, Melee / Ranged if a set can't be blank (the builder
     checks Create);
   - Create selects the new set.
6. **Copy bands from…:**
   - Into: the current set.
   - From: your other sets, then all presets.
   - Checkboxes: Bands (always on), Sounds on enter (on), Match rule and unknown label/color (off).
   - A one-line summary: "Paladin's 4 bands are replaced by X's 5. Its name and the containers using it stay."
   - Copy then shows the Undo line.
7. **Restore dialog:** a list of the differences (for example "Band 2 label: HOLY → JUDGE"), up to 8 lines and then "and N
   more", plus a **Keep my sounds** checkbox. Restore then shows the Undo line.
8. **Bands tab.** Add band and Remove band sit side by side under the rail, in a two-column row, with Remove band to the
   right of where Add band is now. Remove band leaves the band's controls. It is disabled when the set has one band.
9. **Defaults.** The top-right button keeps its current meaning: the General tab fields. Its tooltip now points to Restore
   for the bands.

### Docs, locales and tests

- **Docs:** README (the band sets section), `docs/settings-panel.md`, `docs/ARCHITECTURE.md` (the registry,
  `origin` and Known Limitations), `docs/schema.md` (the new field and migration step), `docs/test-cases.md` and
  `docs/smoke-tests.md` (new rows for each ask), and the settings page's own header comment.
- **Locales:** every new string goes in enUS.
- **Tests:** origin through Create, Duplicate, CopyFrom and the migration; Diff and IsModified; RestorePreset with and
  without keepSounds; CopyFrom options and the refusal to copy into itself; the preset view being read-only;
  the picker groups; the Delete and Remove guards; Undo round-trips. Run them on both kit profiles. The class preset
  count is 9 on Forever and 13 on Retail.

## Non-goals

- Editing presets in place.
- Syncing a set to its preset automatically after an addon update.
- Reordering sets by hand.
- Import/export strings.

## Smoke

Rows go in `docs/smoke-tests.md`, and the lead copies them into a new owner sheet,
`Documents/Ka0sPendingSmoke-2026-11-25-BAND-SETS.csv`.
