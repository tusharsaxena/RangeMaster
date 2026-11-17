# Common tasks — Ka0s Range Master

Recipes for the changes made most often here. Each names the real files; run the green gate
(`docs/testing.md`) after each.

## Add a setting

- Add its default to `defaults/Profile.lua` (`NS.defaults.profile`, or `global` for an
  installation-wide value).
- Register its schema row in the page file that draws it (`settings/General.lua` today) with
  `NS.RegisterSchemaRows`: `path`, `page`, `group` (the tab), `type`, `label`, `desc`, `default`, and an
  `onChange` (a declared no-op where nothing reacts). A color row carries its class-color companion
  next (options-ui-§17).
- Wrap `label` and `desc` in `L[...]` and regenerate `locales/enUS.lua`'s key block (every `L["…"]`
  subscript in the source, grouped by first file, in TOC order); `tests/test_locale.lua` fails on a
  key missing or unused.
- `tests/test_schema.lua` checks the row resolves against the defaults and carries a group; add a case
  for the row's own behavior.

## Add a slash verb

- Add a positional triple `{name, L[desc], fn}` to `NS.COMMANDS` in `settings/Slash.lua`, its handler
  a host function in the same file.
- Decide whether it is live while disabled: a diagnostic or read-only verb joins `liveVerbs()`; a
  feature verb is refused by the dispatcher on its own.
- Add the row to `docs/slash-dispatch.md` and, where it changes what a player can do,
  `docs/smoke-tests.md`. `tests/test_disabled.lua` step 7 walks every verb.

## Add a bus message

- Declare it once in `core/Bus.lua`'s `NS.MSG` catalog with its sender and payload in a comment, and
  add its row to `docs/ARCHITECTURE.md` → Message Bus. Publish with
  `NS.bus:SendMessage(NS.MSG.X, ...)`; subscribe on a fresh `NS.NewBusTarget()` per receiver.
- `tests/test_bus.lua`'s catalog case lists every message; update it in the same change.

## Add a game event

- Add `{ "EVENT", "Handler" }` to `LIFECYCLE_EVENTS` in `core/RangeMaster.lua` and the handler as an
  `addon:` method. The stand-down and stand-up read the same list, so nothing else changes.
- An event one client lacks is gated with `NS.Compat.ForClient` at registration (clients-§4); an
  event a client may simply not know (`PLAYER_FOCUS_CHANGED` on Forever) carries `ifValid = true`,
  which asks `NS.Compat.IsEventValid` first.
- A range-engine event refreshes its unit through `NS.Ticker.Refresh(unit)` and does nothing else.

## Add a seed spell or a ladder rung

- A class's chip or ladder spell: add the ID to `defaults/SpellSeeds.lua` under the client it exists
  on (`retail` or `forever`) and the class token. A ladder spell becomes a rung only when the player
  knows it and it has a max range with no min range, so a melee or min-range spell belongs in
  `chips`, not `ladder`. Add a RANGE-5 run for it in `docs/smoke-tests.md`.
- A Forever item or interact rung: add it to `FOREVER_ITEMS` or `FOREVER_INTERACT` in
  `core/Compat.lua`, only at a yard Forever answers reliably, and update the table in
  `docs/compat-layer.md`. `tests/test_range.lua`'s `test_forever_ladder` holds the yards.

## Add a locale string

- Use `L["The English sentence."]` at the call site, one whole sentence per key with `%s` slots, and
  regenerate the key block in `locales/enUS.lua`.

## Draw a new icon

- Declare the catalog name on `CLAUDE.md`'s `LibKa0s icons:` line, copy the file from the vendored tag's
  `LibKa0s/media/icons/`, and read it with `NS.Icon(name)`. `tests/test_mediasetup.lua` holds the line
  to the draw set and the vendored folder.
