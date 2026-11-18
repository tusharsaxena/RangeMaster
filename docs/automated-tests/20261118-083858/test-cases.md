# Test Cases

The full inventory of every headless test case in this repo, grouped by the suite file it
lives in. The `## Totals` table below counts the cases that run: its **Total** is the
authoritative pass count, and the README test badge and any count quoted in the docs must equal
it. A declared skip is listed by name in its group and counted on the `Skipped` row, never in
Total.

**Generated — do not hand-edit.** Regenerate with `lua tests/run.lua --list > docs/test-cases.md`.

### test_loadorder.lua (16)

- loadorder: tocFiles returns every addon lua file, in TOC order
- loadorder: core/MediaSetup.lua loads before core/Constants.lua
- loadorder: the settings seams load before every file-load reader, annotated
- loadorder: tocFiles skips libs, directives and comments
- loadorder: tocFiles converts backslashes to forward slashes
- loadorder: every derived path exists on disk
- loadorder: the runner loaded exactly the TOC's files, in the TOC's order
- loadorder: tests/perf.lua derives its list from the TOC too
- loadorder: xmlFiles returns every LibKa0s script the vendored XML lists, in its order
- loadorder: the runner loaded exactly the vendored XML's library files, in its order
- loadorder: the runner loads LibRangeCheck-3.0 as the TOC does, and it registers whole
- loadorder: the loaded library registered — NS.Perf is the lib, not the degradation stub
- loadorder: tests/perf.lua derives its library half from the vendored XML too
- loadorder: LibStub raises for a missing major without the silent flag
- loadorder: LibStub returns nil for a missing major with the silent flag
- loadorder: LibStub keeps the higher minor when a major registers twice

### test_schema.lua (36)

- FormatSchemaValue formats by type
- ValidateSchema resolves every real path against defaults (0 errors, 0 missing)
- ValidateSchema reports a planted path that does not resolve against defaults
- ValidateSchema flags an invalid page/type as a shape error
- ValidateSchema prints through NS.Print, resolved at call time, with no hand-typed tag
- every schema row carries a label and a tooltip description
- every schema path is unique
- every schema row declares a default
- every row's default matches the value in defaults.profile
- every persisted profile default is reachable from a schema row
- every number row declares a usable min/max range
- every string row supplies a values source
- every row on every page carries a `group`
- no color row carries `disabledIf`, and every pair declares whose class it means
- `disabledIf` names a real sibling setting
- every schema row lands on a page the panel actually builds
- the schema runtime is LibKa0s-Schema-1.0's, over the live schema array
- the minimap row survives a sweep, and a named reset still resets it
- SetByPath refuses a path with no schema row, and stores nothing
- ResolvePath walks a dotted path
- ResolvePath returns nil for a missing branch instead of raising
- ResolvePath still handles a flat key
- SetPath writes through a dotted path and creates intermediate tables
- ValidateSchema resolves nested paths against defaults.profile
- each unit's row set for a page is the same size
- FormatSchemaValue resolves the Slash major at load, never per call
- a build without LibKa0s-Slash-1.0 falls back to a minimal FormatSchemaValue
- degraded Schema stub: SetMany refuses the whole batch on one invalid entry
- degraded Schema stub: SetMany refuses an unknown path with its index
- degraded Schema stub: a valid SetMany stores both, reacts once each, announces per write
- degraded Schema stub: SetMany announces once through announceBatch when given
- degraded Schema stub: a writeThrough path with no row stores raw and announces a synthetic row
- degraded Schema stub: a row-less path outside writeThrough is still refused
- degraded Schema stub: row.normalize's answer is stored, and a nil answer refuses
- degraded Schema stub: Get forwards the instance id to a row's own get
- degraded Schema stub: ApplyDefault forwards the instance id to Set

### test_database.lua (14)

- database: the account-wide schemaVersion default is 0 (savedvariables-§1)
- database: v0.1.0 ships the first data shape, so the ladder is empty and the target is 0
- database: RunMigrations is a safe no-op when the DB is absent
- database: the runner climbs every step, stamps each, and is idempotent
- database: a step that raises leaves the stamp unmoved and says so once in chat
- database: InitDB produced a profile carrying every default key
- database: Backfill fills only missing keys, deep-copied, and keeps a stored false
- database: the session-only state is in no defaults tree
- database: a profile reset re-reads the latch and traces once
- database: test_template_fill_missing_keys — a stored container gains what a later build added
- database: the load pass repairs a container whose band set ids name no stored set
- database: test_first_run_seeds_presets — a fresh profile gets the four sets, class default first
- database: the load pass normalizes a stored band set and repairs its counter and order
- database: the active profile was prepared at load

### test_bandsets.lua (21)

- bandsets: test_resolve_by_max — (20, 25) in Melee / Ranged lands in MID 20-30
- bandsets: test_resolve_by_min — matchBy min reads the near bound
- bandsets: test_resolve_open_ended — (40, nil) is out of range under either matchBy
- bandsets: test_resolve_unknown — unknown state reads the unknown band
- bandsets: test_resolve_none_nil — no unit resolves to nil
- bandsets: test_bandset_normalize — overlaps, gaps and order are repaired
- bandsets: normalize swaps a reversed band, closes a gap and drops a swallowed one
- bandsets: normalize gives an open-ended band in the middle the next band's edge
- bandsets: normalize turns an empty set into one band over everything
- bandsets: normalize fills a band's colors and repairs matchBy and the unknown band
- bandsets: Create, Rename, Duplicate and List keep the order and announce each change
- bandsets: names stay unique: Create, Duplicate and Rename suffix a taken name, in any case
- bandsets: test_bandset_delete_reassigns — containers on a deleted set move to the default
- bandsets: Delete honors reassignTo, refuses the last set and an unknown id
- bandsets: deleting the default set makes the next one the default
- bandsets: test_for_unit_friendly_override — a friendly unit reads bandSetFriendly when set
- bandsets: test_hunter_preset_per_client — Forever has the 5-8 dead zone, Retail does not
- bandsets: the four presets have the spec's shape, every one well formed
- bandsets: DefaultFor picks a class's preset, and an unknown class gets Melee / Ranged
- bandsets: SetBandSound writes one band's sound, announces, and refuses a bad set or band
- bandsets: a restore never rewinds the id counter, so a later Create mints an id never used

### test_container_manager.lua (15)

- cm: test_create_defaults_unit_target — a bare Create is a target container on the default set
- cm: Create seeds the spell list from the client's class seeds and takes a unit and opts
- cm: test_unique_name_suffix — a taken name gets the next free number
- cm: Rename trims, keeps names unique and refuses a blank name or an unknown id
- cm: SetField stores elements.order only as an arrangement of the four elements, each once
- cm: test_delete_removes_from_order — the member and its order slot both go
- cm: test_duplicate_deep_copy — a duplicate is its own tables, after its source
- cm: CopySettings copies the named sections deep, and never identity or placement
- cm: Snapshot and RestoreSnapshot put the registry back exactly, ids included
- cm: test_apply_coalesced_once_per_frame — many writes in one frame announce once
- cm: test_apply_deferred_in_combat — a flush in combat waits for PLAYER_REGEN_ENABLED
- cm: a stood-down addon arms no apply timer, and the stand-up announces once
- cm: a restore never rewinds the id counter, so a later Create mints an id never used
- cm: Create keeps its positional unit; opts.unit cannot smuggle in an unwatched one
- cm: a profile switch announces CONTAINERS_CHANGED once, on the next frame

### test_presets.lua (11)

- presets: test_simple_four_free_containers — target, focus, pet, mouseover free on screen
- presets: test_intermediate_shape — unit frames, cursor mouseover, friendly sets, hidden with no unit
- presets: Intermediate creates the Healer set when the profile has none, and reuses one it has
- presets: test_advanced_shape — six containers with plates, spell chips, a sound and rules
- presets: Advanced keeps a sound the player already put on the out-of-range band
- presets: test_preset_undo_restores — Undo puts back the containers and band sets from before
- presets: an unknown key applies nothing and keeps the Undo slot
- presets: Describe answers each preset's name, container count and bullet items
- presets: an apply announces CONTAINERS_CHANGED once, on the next frame
- presets: a profile switch, copy or reset drops the Undo slot, so no other profile is overwritten
- presets: Advanced puts the OOR sound on through the band-set writer, which announces it

### test_number_format.lua (5)

- number: the six formats on the bracket (20, 25)
- number: an open-ended bracket reads 40+ in every format, never an invented far bound
- number: an unknown range reads the band set's unknown label in every format
- number: no unit reads nothing, and an unknown format reads as range
- number: a known state with no far bound and no near bound reads unknown, not 0

### test_container_render.lua (32)

- render: an enabled container gets one pooled instance, watching its unit, drawn at once
- render: Release returns the frame to the pool cleanly, and the next Acquire reuses it
- render: a deleted or disabled container's instance goes back to the pool on the next apply
- render: a nameplates container gets no single instance (the plate anchors own those)
- render: the stand-down parks every instance, and the stand-up draws them again
- render: test_text_set_only_on_change — two identical renders set the text once
- render: test_recolor_only_on_band_change — a new bracket in the same band paints no color
- render: test_color_modes — band, fixed and class, for the number, the border and the fill
- render: an unknown range reads the set's gray ? on every element, never a band
- render: an open-ended bracket reads 40+ and the out-of-range band
- render: no unit hides a container that hides with no unit, and shows one that does not
- render: test_hidden_elements_not_created — only the enabled elements are built
- render: an element turned off after it was built is hidden and laid out of the row
- render: test_element_order_row_and_column — elements.order, in a row and in a column
- render: the layout's scale and alpha reach the root frame
- render: the indicator shapes draw this addon's textures, recolored by band
- render: the bar indicator is LibKa0s-Widgets' data bar, fuller the nearer the band
- render: spell chips are colored by each spell's own answer, and only when it changes
- render: test_friendly_uses_friendly_set — a friendly unit reads the friendly override
- render: a band set edit repaints every instance on it
- render: RANGE_UPDATED reaches every instance on that unit, and only those
- render: the bar indicator repaints its fill in each new band's indicator color
- render: a target swap at the same bracket re-resolves the band set through the event path
- render: a reaction change on the same unit (UNIT_FACTION) re-resolves the band set
- render: a target swap at the same bracket asks every spell chip again
- render: a spell chip's answer moving inside one bracket is drawn on the next tick
- render: colorMode class reads the TRACKED unit's class, and follows a target swap
- render: a skin change in combat re-applies nothing until combat ends
- render: an element font naming a LibSharedMedia key draws that face at the stored size
- render: an element's shadow turns the font string's shadow offset on and off
- render: a LibSharedMedia border draws on a backdrop of its own, band-colored, its tiling tracked
- render: every indicator shape ships as a white 64x64 uncompressed 32-bit TGA

### test_anchors_screen.lua (8)

- anchors: a screen container sits at its stored point on UIParent
- anchors: a stored point the client does not know falls back to CENTER
- anchors: a locked screen container shows no drag strip; unlocking shows it, locking hides it
- anchors: test_screen_drag_saves_point — a drag on the strip saves point and offsets through NS.CM
- anchors: a drag is refused in combat, and nothing is saved
- anchors: a non-screen container shows no drag strip, unlocked or not
- anchors: Reset position puts every screen container back at its default point
- anchors: switching a container's mode detaches the old anchor

### test_anchors_frame.lua (16)

- frames: the providers name Blizzard's and EllesmereUI's frames per unit, and nothing for mouseover
- frames: Resolve answers the live global frame, and nil for a missing, forbidden or non-frame one
- frames: test_frame_blizzard_target — a target container anchors to TargetFrame
- frames: an EllesmereUI container anchors to EllesmereUI's frame for its unit
- frames: a new frame container sits on its frame at the frame default point, whatever its id
- frames: a screen position does not carry onto the unit frame when the mode changes
- frames: test_frame_missing_then_loaded — hidden with one debug line, anchored on ADDON_LOADED
- frames: a frame that appears by PLAYER_ENTERING_WORLD is found there too
- frames: test_frame_anchor_deferred_in_combat — no anchor write in combat, done on the leave edge
- frames: test_mouseover_frame_falls_back_to_cursor — a mouseover container on a unit frame follows the cursor
- frames: a mouseover container on a named custom frame stays on that frame
- frames: a frame that will not take the anchor hides the container instead of raising
- picker: NamedAncestor walks to the nearest named ancestor, skipping UIParent and forbidden frames
- picker: a left click on a named frame calls back with its name and ends the pick
- picker: refused in combat with one gray line, and combat during a pick cancels it
- picker: a right click cancels

### test_anchors_nameplate.lua (14)

- plates: test_nameplate_own_plate_follows_target_change — the target container moves to the new target's plate
- plates: a target with no plate hides the container, and its plate coming into view shows it
- plates: a removed plate is told apart by its frame — another plate going leaves the target where it is
- plates: a pet container on its own nameplate is hidden (a pet has no plate in practice)
- plates: test_nameplates_instance_per_hostile_plate — one instance per hostile plate, each on it
- plates: plates already shown when a nameplates container is created get instances on its apply
- plates: test_nameplates_friendly_toggle — includeFriendly gives friendly plates an instance too
- plates: a reaction change (UNIT_FACTION) moves a plate in or out
- plates: test_nameplate_recycle — REMOVED releases the plate's instance, and the stale token errs nowhere
- plates: a plate not populated at ADDED is picked up by the next frame's re-check
- plates: test_forbidden_plate_skipped — a forbidden plate gets no instance and no anchor
- plates: ForEachHostile walks the hostile plates, and every plate with includeFriendly
- plates: deleting the nameplates container releases every plate instance
- plates: the stand-down releases every plate instance and leaves no re-check armed; the stand-up rescans

### test_anchors_cursor.lua (7)

- cursor: test_cursor_single_onupdate — three cursor containers, one OnUpdate script
- cursor: the follow places each shown container at the cursor over UIParent's scale, plus its offset
- cursor: a container drawn at another scale is placed in its own units
- cursor: the follow runs only while a cursor container is shown
- cursor: a container leaving the cursor mode, or deleted, drops out of the follow
- cursor: the stand-down leaves the follow disarmed, and the stand-up arms it again
- cursor: a new cursor container sits at the cursor default offset, whatever its id or screen point

### test_visibility.lua (11)

- visibility: test_visibility_matrix — combat any/in/out x reaction any/hostile/friendly x hideNoUnit
- visibility: with no state given, the unit's existence is asked
- visibility: an unreadable reaction never passes a hostile or friendly rule
- visibility: test_ooc_alpha — oocAlpha applies out of combat only, inside the Master opacity
- visibility: the General visibility dropdown wraps every container's own rules
- visibility: the combat edge flag counts as combat before the lockdown answers it
- visibility: an in-combat container shows on the combat edge and hides on the leave edge
- visibility: a hostile-only container follows the unit's reaction
- visibility: the frame's opacity is the layout's times oocAlpha out of combat
- visibility: writing General visibility or Master opacity re-evaluates every container
- visibility: Master scale multiplies each container's own scale on the next apply

### test_sounds.lua (12)

- sounds: test_settle_200ms — a band's sound waits out the settle, then plays once
- sounds: a band left inside the settle never plays, and coming back to the settled one is quiet
- sounds: test_gap_1s — a second band settling inside the gap is silent
- sounds: test_silent_first_band — the first band after a unit change is silent
- sounds: test_no_sound_for_nameplates — a nameplates container never sounds
- sounds: test_gap_1s — the gap holds across a unit change (the gap is the container's, not the unit's)
- sounds: test_no_sound_for_nameplates — the Test mode stand-in of a nameplates container is silent
- sounds: a container with sounds off, or a band with no sound, plays nothing
- sounds: a key LibSharedMedia does not know plays nothing, and a raising client is contained
- sounds: through the render path, a band change plays after the next steady read
- sounds: a hidden container plays nothing
- sounds: the out-of-range key the Advanced preset uses is built in

### test_compat.lua (6)

- compat: the client answer follows the kit profile this run uses
- compat: ForClient serves nil and both everywhere, this client's token, and raises on a typo
- compat: every wired member is the library's on a full load
- compat: the guards follow the client's issecretvalue
- compat: the degraded load answers Retail and keeps the guards' one-rung bodies
- compat: no file outside the library reads a WOW_PROJECT global or an interface number

### test_range.lua (22)

- range: test_known_bracket — a 20 to 25 yd answer reads known 20, 25
- range: the library is asked with no cache of its own (maxCacheAge 0)
- range: test_open_ended — a min with no max reads known and open-ended
- range: test_secret_is_unknown — a secret bound reads unknown, never out of range
- range: test_error_is_unknown — the library raising reads unknown, and nothing escapes
- range: test_no_unit_is_none — a unit that does not exist reads none, and is never queried
- range: test_memo_one_query_per_tick — three reads of one unit in a tick are one query
- range: test_range_unit_vanishes — a unit gone after BeginTick reads none, no error
- range: the memo is keyed by unit token, nameplate tokens included
- range: test_spell_unknown_spell_nil — a spell the player does not know answers nil
- range: a known spell that is unusable right now is not trusted (research lesson 9)
- range: a secret or raising usability answer is not trusted
- range: InSpellRange answers nil for a secret, an error or a missing unit
- range: test_forever_ladder — Forever's ladder holds only the reliable yards
- range: the interact rungs are race-adjusted
- range: a known seed spell is a rung at its own max range; unknown, min-range and secret are not
- range: on Forever an empty library answer falls back to the ladder
- range: the ladder walk is open-ended past its last rung
- range: the Forever walk trusts a spell rung only while the spell is usable
- range: friendly in combat, the ladder asks spells only (items and interact are blocked)
- range: Rebuild is debounced to one rebuild after the last call
- range: every class seed table is well-formed on both clients

### test_ticker.lua (13)

- ticker: test_rate_idle_10hz — out of combat one ticker runs at 10 Hz and re-arms
- ticker: test_rate_combat_20hz — combat restarts the one ticker at 20 Hz, and back
- ticker: test_stops_when_nothing_watched — the last unwatch cancels the ticker
- ticker: it also stops when every watched unit is gone, and an event restarts it
- ticker: test_update_only_on_change — RANGE_UPDATED fires on a change and never on a repeat
- ticker: test_mouseover_revalidated_each_tick — mouseover leaving with no event reads none
- ticker: N watches of one unit cost one range query per tick
- ticker: the unit events refresh their unit; UNIT_PET only for the player
- ticker: Changed sends an unmoved triple again (a new unit behind the token); Refresh does not
- ticker: NAME_PLATE_UNIT_REMOVED sends none for its token at once
- ticker: a range read inside a tick is recorded within ticker.tick, a forced one at top level
- ticker: PLAYER_FOCUS_CHANGED registers only where the client knows it
- ticker: a stand-down cancels the ticker and a stand-up rebuilds it from the watch list

### test_envsetup.lua (6)

- EnvSetup: NS.Meta asks about THIS addon's folder, not its title or its frame prefix
- EnvSetup: NS.Meta degrades to nil when the client exposes no manifest reader
- EnvSetup: NS.Version prefers the TOC over this addon's own constant
- EnvSetup: NS.Version falls back to this addon's own constant
- EnvSetup degraded: an install with no LibKa0s still reads its own TOC
- EnvSetup degraded: a legacy-only surface yields nil, and the dead global is never called

### test_coresetup.lua (8)

- core: the secret seam is the library's, not a private copy
- core: NS.SECRET is the library's sentinel, live and degraded
- core: the perf descriptor names the folder and leaves the close control to the library
- core: NS.Print carries the [RM] tag and survives a secret arg
- core: NS.Print and NS.Util.print are the same object after the AceConsole reclaim
- core: the addon still prints, tagged, with LibKa0s absent
- core: NS.Printf formats its parts into one tagged line, live and degraded
- core: the degraded SafeRegisterEvent isolates a raise and lists the name once

### test_mediasetup.lua (10)

- MediaSetup: NS.Icon answers the vendored path, extensionless
- MediaSetup: an icon the library does not ship answers nil
- MediaSetup: NS.MediaFont answers the vendored face, and an unknown face answers nil
- MediaSetup: the font this addon names is the face the library registers
- MediaSetup: FONT_MONO resolves into the payload, not into this addon's own media/
- MediaSetup: every mark this addon's windows draw is one the library ships
- MediaSetup: every icon CLAUDE.md declares has a file in the vendored copy
- MediaSetup: the seam is handed the FOLDER name, never a frame prefix or a literal
- MediaSetup: the LSM registration happens at file load, not at OnInitialize
- MediaSetup: with no library there is no art, and that is not an error

### test_debuglog.lua (14)

- the console's font resolves through the Media seam to the LibKa0s payload
- the descriptor tells the library the FOLDER name, not just the frame name
- and it takes that folder name from the vararg, not from a hand-typed literal
- the debug flag the library reads and writes is NS.State.debug
- the library-absent stub's SetEnabled acks the new state in one whole sentence
- the library-absent stub's RunDiagnostics prints the one absent line and writes nothing
- NS.Debug is published and reaches the console buffer
- our title and our font reach the descriptor
- the console checkbox the General page renders is wired to this addon
- /rm debug on enables session state
- /rm debug off disables session state
- /rm debug (no arg) toggles the window, not the state
- /rm debug on writes an [Init] summary naming our version, schema and profile
- the console checkbox label the library renders is prose, not its own STRINGS key

### test_slash.lua (18)

- NS.Print survives AceConsole's embed and stays the [RM]-prefixed printer
- bare /rm opens the settings panel through the config verb, not the help index
- /rm help prints the help index: header + one row per command
- unknown verb prints 'unknown command' then the help index
- /rm version prints the addon version (slash-commands-§3)
- /rm list uses the mandated color scheme (slash-commands-§5)
- /rm options is aliased to /rm config (no unknown-command error)
- /rm config in combat refuses with a gray notice (options-ui-§2)
- OpenOptionsPanel logs [Cfg] refused in combat
- the schema CLI's list header the library renders is prose, not its own STRINGS key
- slash verbs: the stub's split agrees with the live dispatcher's over a corpus
- slash: test_new_unit_arg — /rm new takes a unit, defaults to target, and refuses one it does not watch
- slash: test_select_by_name — /rm select takes a number or a name in any case
- slash: /rm delete takes a number or a name and selects the neighbor
- slash: test_preset_verb — /rm preset confirms, applies, undoes and refuses an unknown key
- slash: /rm bands lists the band sets with the selection marked, and selects one
- slash: a name two band sets or containers share is ambiguous, and selects neither
- slash: /rm pick starts the frame picker for the selected container, whose pick attaches it

### test_slashgate.lua (7)

- /rm enable and /rm disable write the Enable row's OWN path, through the one seam
- /rm disable echoes the stored value in the set shape, and /rm enable undoes it
- the pair is never one-way: the dispatcher still answers while the addon is disabled
- enable and disable hold no state of their own
- a refused `unlock` leaves the lock exactly where it was
- a refused `update` publishes nothing on the bus
- /rm profile <name> switches while the addon is disabled

### test_perf.lua (17)

- debug: the flag still flips and acks with LibKa0s absent
- debug: /rm debug names the missing library instead of erroring
- debug: every member the addon reaches for answers with LibKa0s absent
- perf: the addon loads with LibKa0s absent
- perf: /rm perf explains itself instead of erroring with LibKa0s absent
- every perf step label the library renders is prose, not its own STRINGS key
- Perf: the descriptor hands the library the FOLDER name, not just the frame name
- perf: the addon holds a real LibKa0s-Perf instance, on this addon's latch
- perf: range.get declares its nesting within ticker.tick (performance-§3)
- perf: container.render declares its nesting within ticker.tick (performance-§3)
- perf: records identify this addon and land in its own global
- perf: the ring is reachable through its own global and nowhere in AceDB
- perf: brackets record nothing while capture is off
- perf: every declared bucket is reached by a real bracket
- perf: suspend unregisters the lifecycle events, and resume restores them
- perf: the suspended state is session-only, never persisted
- perf: the slash verb dispatches into the lib

### test_bus.lua (8)

- a receiver on its own target hears a message, then is silent after unregister
- two receivers of one message both fire (no (message,target) clobber)
- a message payload reaches the receiver after the message name
- sending a message with no subscribers is a harmless no-op
- the bus record is LibKa0s-Bus-1.0's, built under the folder name
- the catalog is strict: an undeclared key raises at the call site
- the catalog is exactly the four declared messages, each one prefixed for this addon
- with LibKa0s absent, receivers still get a private working target

### test_layers.lua (3)

- LAYERS names the HUD strata and an ordered level ladder
- no strata literal and no absolute level at any call site
- a range container's root sits in the HUD strata, its fill, border and overlay offset over it

### test_launcher.lua (30)

- launcher: Register builds ONE broker object and hands that same object to LibDBIcon
- launcher: LibDBIcon is handed db.global.minimap ITSELF, not a copy
- launcher: Register is idempotent
- launcher: the broker label is the BRAND NAME in plain text
- launcher: the label is not WIRED to the TOC Title, even though both read the same today
- launcher: LEFT-click opens the settings panel, and writes nothing
- launcher menu: each entry reads its state on every open
- launcher menu: Enabled runs the /rm enable and /rm disable handlers themselves
- launcher menu: Locked runs the /rm lock and /rm unlock handlers themselves
- launcher menu: Test mode runs the /rm test handler itself
- launcher menu: Sim mode runs the /rm sim handler itself
- launcher: with no client menu API, right-click falls back to the settings panel
- launcher tooltip: the version is the TOC's, and absent it the title is the label alone
- launcher tooltip: Locked follows the lock on every show, green Yes and red No
- launcher tooltip: disabled, it still draws, says No, and the hints do not change
- launcher: the icon file is the one the TOC names, and is a format the client can load
- launcher: the Minimap button row is stored, global, and says SHOWN
- launcher: the row's get/set invert onto `hide`, and the button follows immediately
- launcher: Reset all settings cannot un-hide the button
- launcher: the General page's Defaults button cannot un-hide the button either
- launcher: /rm get global.minimap.shown reads the row's sense off the stored hide
- launcher: /rm set global.minimap.shown false stores hide = true and hides the button
- launcher: the old CLI spelling global.minimap.hide answers unknown setting
- launcher: the renamed path is not reported missing from the defaults
- launcher: a legacy store keeps its hidden button, and its angle, across the rename
- launcher: with BOTH broker libraries absent, Register reports absent and does not raise
- launcher: Register's state lines wait for logging to be turned on, then land once
- launcher: with logging already on, Register's state line is written at once, and once
- launcher: with LibDataBroker but no LibDBIcon, the plugin exists and the button does not
- launcher: with LibKa0s absent the seam still answers, and still remembers the choice

### test_launcher_skin_entry.lua (1)

- launcher descriptor passes openSkinPicker, which runs the skin verb

### test_modes.lua (18)

- modes: each writer sets its mode, announces once on a change, and a repeat is silent
- modes: test_refuse_in_combat — a start is refused in combat with one gray line, and nothing changes
- modes: test_combat_ends_modes — entering combat ends both modes
- modes: neither mode is ever written to SavedVariables
- modes: /rm test and /rm sim toggle, take on and off, and refuse another word
- modes: the Master controls carry Test mode, then Sim mode, as session rows on the one writer
- modes: test_launcher_and_slash_same_handler — the launcher menu is Enabled, Locked, Test mode, Sim mode, each the verb's handler
- modes: test_test_mode_placeholders_all_containers — every enabled container shows a placeholder
- modes: test_test_strip_on_late_instances — a container or plate that appears during Test mode wears the strip
- modes: test_strip_clears_drag_handle — a strip built while locked docks beyond the handle an unlock builds
- modes: test_sim_strip_and_pinned_panel — Sim mode wears the cyan strip, and its step panel cannot be closed
- modes: Test mode keeps the ticker reading the placeholder while it is on
- modes: test_sim_sweeps_bands — Sim mode walks 0 to 50 to 0 yd through every band, with sounds
- modes: the sweep's run plays on its own timers, and Sim mode off stops it
- modes: Sim mode wins over Test mode, and Test mode is refused while a sim runs
- modes: entering combat stops the sim session and puts the live range back
- modes: /rm sim passes any other word to the simulator's own verbs
- modes: the simulator's seam leaves no Compat member unwrapped

### test_optionssetup.lua (16)

- the live and degraded builds veto exactly the same rows from Reset All
- Reset All resets a sessionOnly row and fires its onChange once, on both builds
- the degraded Reset All with no AceDB writes the session row and logs nothing
- the degraded stub publishes LSMValues, the one member reached at file load
- the degraded stub publishes the five composers, hollow
- the degraded stub answers LibKa0s v1.77.0's four members inert
- the degraded stub answers LibKa0s v1.78.0's and v1.79.0's skin members inert
- the degraded stub answers OptionsCompose minor 11's ResetAllTooltip with the tail alone
- the degraded stub answers OptionsCompose minor 15's PositionBlock with no rows and an inert hook
- the degraded stub keeps no private copy of the library's layout constants
- PARENT_TITLE reaches the library through the descriptor, not the namespace
- the Profiles page SHOWS the container AceConfigDialog fills, even a pooled (hidden) one
- General's Reset all settings tooltip says it is the same act as Profiles -> Reset Profile
- the Options descriptor tells the library the FOLDER name
- and the Options descriptor takes that name from the first vararg, not a literal
- the id-list help mark ships: v1.85.0 owes info on every consumer's line

### test_realpages.lua (7)

- the Profiles page self-skips when AceDBOptions is unavailable
- the main page's About content renders on its first OnShow
- re-rendering the About page replaces its body rather than stacking a second copy
- the General page registered a real Blizzard subcategory at build time
- first OnShow builds the General Defaults button, with the collection's reset tooltip
- the General page draws Master controls first, then Presets, and the Skin tab last
- the General page is covered in combat on the sidebar path, and the window stays open (options-ui-§2)

### test_settings_containers.lua (16)

- settings: surface parity — every Containers and Band sets row answers /rm get and /rm set, through its registry's writer
- settings: surface parity — every Containers row is drawn on its rail entry's tab
- settings: test_container_paths_get_set — /rm set container.unit focus changes the selected container
- settings: a band-set reference reads 0 for none, and 0 writes nil back
- settings: with no container, a container. write is refused with how to make one
- settings: no selection reads the first container, and the selection never outlives its container
- settings: deleting the selected container selects its neighbor, not the first
- settings: test_sounds_section_hidden_for_nameplates — the rail lists no Sounds for a nameplates container
- settings: the Containers page draws the banner with New container, and New selects what it made
- settings: Delete container… confirms first, and the confirm deletes the one it named
- settings: the Containers Defaults button restores the entry on screen, for the selected container only
- settings: test_open_in_combat_refused — opening a page in combat is refused with the gray line, and a shown page is covered
- settings: every rail entry is one page key, and every Containers row names a template field
- settings: test_element_order_paths_get_set — /rm get|set container.elements.order reads and moves the selected container's elements
- settings: the Display entry's Layout tab draws the element order as a drag list, and a drop writes through the writer
- settings: the element order list is canceled before the next render draws anything (options-ui-§18)

### test_settings_bandsets.lua (6)

- bandsets: test_bandset_paths_get_set — /rm set bandSet.matchBy changes the selected band set
- bandsets: SetBand moves an edge and the next band follows; an edge that would leave no width is refused
- bandsets: AddBand splits the open-ended band, RemoveBand closes the gap, and the last band stays
- bandsets: SetField refuses what is not a band-set field, and the name is Rename's
- bandsets: deleting the selected band set selects its neighbor and moves its containers to the default
- bandsets: the Band sets page draws General and Bands, and the editor's controls reach the writers

### test_settings_presets.lua (7)

- presets: test_preset_apply_confirms — Apply asks first when there is something to replace, and Undo puts it back
- presets: an empty profile applies at once, with nothing to confirm
- presets: test_first_run_picker_once — the picker shows once per profile, marks it seen as it shows, and waits out combat
- presets: taking the picker down offers no skin picker; the player's close does
- presets: a profile change while the picker is up shows only the new profile's preset picker
- presets: the picker's Choose a preset opens the General page on its Presets tab
- presets: the Presets tab draws the three cards with Apply and the Undo button

### test_skinsetup.lua (12)

- Skin seam: the owner is the folder name, and NS.Skin is its facade
- Skin seam: the read answers the client's default skin before the profile store exists
- Skin seam: the skin row's values are every registered skin, in the library's order
- Skin seam: /rm set refuses a skin that is not registered and applies one that is
- Skin seam: another addon's copy to every Ka0s addon repaints RangeMaster once
- Skin seam: a whole apply carries the stored exceptions and overrides with the skin
- Skin seam: the outline row offers the library's three modes, in its order
- Skin seam: the write seam stores media.outline, and leaves it alone when it is nil
- Skin seam: /rm set skin.outline applies the mode live and refuses an unknown one
- Skin seam: /rm set reaches an exception and an override, each only its own half
- Skin seam: a profile switch applies the new profile's skin, and back
- Skin seam: a profile switch applies the new profile's Font outline, and back

### test_skin_picker.lua (16)

- Skin picker: the spec names this owner, its seams, General's Skin tab, and the unlock eye
- Skin picker: an unseen profile shows it; a seen one does not
- Skin picker: it shows at login, from addon:OnEnable
- Skin picker: in combat a start waits for PLAYER_REGEN_ENABLED, once
- Skin picker: a held start is dropped by HideSkinPicker
- Skin picker: never while the addon is switched off
- Skin picker: a new profile and a reset profile show it again
- Skin picker: the title is Choose a skin, the name line names this addon, and the eye shows
- Skin picker: the player's close marks it seen; this addon's own hide does not
- Skin picker: a profile that has seen it takes a shown picker down, unmarked
- Skin picker: the stand-down takes the picker down, unseen
- Skin verb: the row sits right after config, with the library's help words
- Skin verb: /rm skin shows the picker on a profile that has closed it
- Skin verb: in combat every call prints the library's gray line and shows nothing
- Skin verb: refused while the addon is disabled, and no picker shows
- Skin verb: without the library's picker the verb prints the library-absent line

### test_skin_picker_preview.lua (9)

- Skin preview: the spec hands the picker spec.preview in test mode
- Skin preview: opened with Test mode off, Test mode turns on through the one writer
- Skin preview: the eye toggles Test mode
- Skin preview: closing by the close control turns off the Test mode it turned on
- Skin preview: closing by Escape turns off the Test mode it turned on
- Skin preview: closing by Apply turns off the Test mode it turned on
- Skin preview: closing by HideSkinPicker turns off the Test mode it turned on
- Skin preview: a Test mode already on is left alone by the close
- Skin preview: the eye in combat starts nothing, and the close undoes nothing

### test_glyphs.lua (1)

- glyphs: display strings use only characters every shipped skin face draws

### test_locale.lua (4)

- locale: every L[...] subscript in the source is defined in enUS.lua
- locale: every key enUS.lua defines is used somewhere in the source
- locale: no key is defined twice in enUS.lua
- locale: every enUS value is its own key, so the English build shows the source string

### test_docs.lua (5)

- README.md carries no angle-bracket argument placeholders
- README.md carries ## Reporting a bug with the standard's text, placed and pointed at
- README.md carries no numbered list
- every Tier 2 documentation-map row agrees with docs/
- docs/smoke-tests.md carries a non-English-client section

### test_prose.lua (15)

- prose: no authored file carries a British spelling from localization-§5's published list
- prose: the gate carries localization-§5's two lists whole, and nothing of its own
- prose self-test: the carve-out suppresses the named generated folder, and only it
- prose self-test: a path the carve-out does not name is not covered by one that looks like it
- prose self-test: a carve-out that is not a set of path strings is a failure, not a silence
- prose self-test: a TOC's file lines are read as paths, and its directives and comments are not
- prose self-test: a .pkgmeta's ignore block is read, and the keys around it are not
- prose self-test: an ignore entry covers a path exactly, by folder, and by wildcard
- prose self-test: the carve-out admits a generated dump and refuses a file the TOC loads
- prose self-test: a waiver-file exclusion meets the same two refusals as the carve-out
- prose self-test: each list is refused on the matching rule its own scan uses
- prose self-test: the scan and the refusals read the added exclusions through one reader
- prose self-test: a narrowing is refused by what it suppresses, not by how it is written
- prose self-test: the disclosure names what each entry suppressed, and says when it is bounded
- prose self-test: a malformed waived is a failure, not a silence

### test_surface_parity.lua (15)

- parity: the Core stub publishes everything core/CoreSetup.lua publishes live
- parity: the DebugLog stub carries the whole live surface
- parity: the Options stub carries every helper the degraded build can reach
- parity: the Slash stub carries every dispatcher member the addon calls
- parity: the Slash stub's DISABLED_LINE_FORMAT copy is the library's, byte for byte
- parity: the Launcher stub carries the whole live surface
- parity: the Bus stub carries the library's whole surface
- parity: the Schema stub carries the library's lib-level surface
- parity: the Schema stub's instance carries every member of a live instance
- parity: the Perf stub carries every Perf member the addon reaches
- parity: the Lifecycle stub carries the whole live surface
- parity: the Pool stub carries the library's whole surface
- parity: the degraded Skin facade answers every name the live facade carries
- parity: the Skin seam publishes the same NS members on both paths
- parity: the Compat seam carries the major's surface, less what it does not wire

### test_vendor_sync.lua (3)

- libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon bundles
- tests/_kit is the test kit that shipped with that release
- the automated-test runner is recorded executable (100755)

### test_lintconfig.lua (4)

- lintconfig: .luacheckrc sets no top-level ignore
- lintconfig: .luacheckrc switches no warning class off wholesale
- lintconfig: every files[...] ignore is narrowed to a file or a name
- lintconfig: no source file carries a bare inline luacheck ignore

### test_events.lua (3)

- events: the session rejected list exists and starts empty
- events: one unknown lifecycle name costs only itself, and is listed once
- events: the registered set is exactly the one lifecycle list

### test_disabled.lua (13)

- disabled 1: the enabled addon registers something to stand down from
- disabled 2: the hold follows the STORED path, read when the addon comes up
- disabled 3: writing the enable path leaves NOTHING registered
- disabled 4: no timer, ticker or OnUpdate is left armed, and both preview modes end
- disabled 5: a preview mode cannot be started while disabled, so nothing can be shown
- disabled 6: every baseline event, fired anyway, reaches its handler and writes, prints and shows nothing
- disabled 7: every reserved verb answers, and only a feature verb refuses
- disabled 7: a refused feature verb reaches no write seam
- disabled 8: the left click opens the panel; the menu grays the rest and still re-enables
- disabled 9: re-enabling restores the registration set, from the settings as they are NOW
- disabled 9: a bus subscription comes back once, and reaches its receiver once
- disabled 10: releasing one hold does not stand up an addon the other still holds down
- disabled 10: the perf hold is session-only and the disabled hold is the stored path

### test_diagnostics.lua (8)

- diagnostics: the report carries every section's facts, and no section fails
- diagnostics: stood down, the events section says so rather than listing nothing
- diagnostics: the row sits straight after debug and its text is routed through NS.L
- diagnostics: the sections change nothing, and the run only turns logging on
- diagnostics: the session's rejected events are folded into the report
- diagnostics: an over-cap report ends in the truncated line, then the end marker
- diagnostics: the chat line is ours to localize and names the line count
- diagnostics: with the library absent both forms print the one absent line

### test_diagnostics_contract.lua (9)

- diagnostics contract: both forms run the report
- diagnostics contract: the debug word is matched in any case
- diagnostics contract: both markers carry the brand and the end counts the report
- diagnostics contract: the report appends after what the console already holds
- diagnostics contract: the report lands with logging off and turns it on for the session
- diagnostics contract: an addon that opts out lands the report and leaves logging off (skipped: this addon keeps the default (Kit.diagnostics.enablesLogging is not false), so its report turns logging on; the case above holds it)
- diagnostics contract: with logging already on, the report writes no second enable line
- diagnostics contract: both forms run while the addon is disabled
- diagnostics contract: no other name runs the report

### test_eol.lua (2)

- eol: every tracked file carries the terminator .gitattributes declares for it
- eol: .gitattributes is line-endings-§5's canonical body for this repo kind

### test_layout_cap.lua (13)

- layoutcap: every authored file over the 1500-line cap is named in the census
- layoutcap: no census row outlives the breach it records
- layoutcap: every over-cap census row carries one of layout-§1's three terminal states
- layoutcap: the census and the exempt set agree about which paths were exempted
- layoutcap: an empty census is written as a result rather than left standing empty
- layoutcap self-test: the parser reads the census nested under the register, and stops there
- layoutcap self-test: a census outside its register, or at the wrong level, is not read
- layoutcap self-test: an over-cap file missing from the census is reported, and an exempt one is not
- layoutcap self-test: a census row that outlives its breach is reported
- layoutcap self-test: an over-cap row that names no terminal state is reported
- layoutcap self-test: the census and the exempt set are held to naming the same paths
- layoutcap self-test: a census that states nothing is told apart from one that states none
- layoutcap self-test: the exempt set takes folders as well as paths

### test_lizard_sighted.lua (8)

- lizard sighted: every hazard lizard loses a function over is neutralized
- lizard sighted: fields, strings, comments and look-alike names come through unchanged
- lizard sighted: a method definition is rewritten to its dot form with self
- lizard sighted: no line is added or removed, CRLF included
- lizard sighted: countFunctions counts the keyword, not strings, comments or longer names
- lizard sighted: listedCounts reads the per-file table, once per file
- lizard sighted: parity names every file whose counts differ, and only those
- lizard sighted: lizard lists every function of a hazard fixture once it is sanitized

### test_skin_values.lua (3)

- skin values: every host row carries its file, substring, why and cause id
- skin values: no typed value outside the kit's categories and the host's rows
- skin values: the check is falsifiable, a planted value of each shape is reported

### test_skin_switch.lua (6)

- skin switch: the check is falsifiable, a surface that redraws a literal is reported
- skin switch: the debug console changes
- skin switch: the debug console changes with the Scope ignored
- skin switch: the perf panel changes
- skin switch: the perf panel changes with the Scope ignored
- skin switch: a range container's number changes

### test_client_globals.lua (3)

- client globals: no call of a global a client lacks
- client globals: every allowlist row has a reason and a finding to excuse
- client globals: the check is falsifiable, a planted bare call is flagged for both clients

## Totals

| Suite | Cases |
|-------|------:|
| test_loadorder.lua | 16 |
| test_schema.lua | 36 |
| test_database.lua | 14 |
| test_bandsets.lua | 21 |
| test_container_manager.lua | 15 |
| test_presets.lua | 11 |
| test_number_format.lua | 5 |
| test_container_render.lua | 32 |
| test_anchors_screen.lua | 8 |
| test_anchors_frame.lua | 16 |
| test_anchors_nameplate.lua | 14 |
| test_anchors_cursor.lua | 7 |
| test_visibility.lua | 11 |
| test_sounds.lua | 12 |
| test_compat.lua | 6 |
| test_range.lua | 22 |
| test_ticker.lua | 13 |
| test_envsetup.lua | 6 |
| test_coresetup.lua | 8 |
| test_mediasetup.lua | 10 |
| test_debuglog.lua | 14 |
| test_slash.lua | 18 |
| test_slashgate.lua | 7 |
| test_perf.lua | 17 |
| test_bus.lua | 8 |
| test_layers.lua | 3 |
| test_launcher.lua | 30 |
| test_launcher_skin_entry.lua | 1 |
| test_modes.lua | 18 |
| test_optionssetup.lua | 16 |
| test_realpages.lua | 7 |
| test_settings_containers.lua | 16 |
| test_settings_bandsets.lua | 6 |
| test_settings_presets.lua | 7 |
| test_skinsetup.lua | 12 |
| test_skin_picker.lua | 16 |
| test_skin_picker_preview.lua | 9 |
| test_glyphs.lua | 1 |
| test_locale.lua | 4 |
| test_docs.lua | 5 |
| test_prose.lua | 15 |
| test_surface_parity.lua | 15 |
| test_vendor_sync.lua | 3 |
| test_lintconfig.lua | 4 |
| test_events.lua | 3 |
| test_disabled.lua | 13 |
| test_diagnostics.lua | 8 |
| test_diagnostics_contract.lua | 8 |
| test_eol.lua | 2 |
| test_layout_cap.lua | 13 |
| test_lizard_sighted.lua | 8 |
| test_skin_values.lua | 3 |
| test_skin_switch.lua | 6 |
| test_client_globals.lua | 3 |
| Skipped | 1 |
| **Total** | **602** |
