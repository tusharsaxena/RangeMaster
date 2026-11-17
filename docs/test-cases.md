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

### test_database.lua (9)

- database: the account-wide schemaVersion default is 0 (savedvariables-§1)
- database: v0.1.0 ships the first data shape, so the ladder is empty and the target is 0
- database: RunMigrations is a safe no-op when the DB is absent
- database: the runner climbs every step, stamps each, and is idempotent
- database: a step that raises leaves the stamp unmoved and says so once in chat
- database: InitDB produced a profile carrying every default key
- database: Backfill fills only missing keys, deep-copied, and keeps a stored false
- database: the session-only state is in no defaults tree
- database: a profile reset re-reads the latch and traces once

### test_compat.lua (6)

- compat: the client answer follows the kit profile this run uses
- compat: ForClient serves nil and both everywhere, this client's token, and raises on a typo
- compat: every wired member is the library's on a full load
- compat: the guards follow the client's issecretvalue
- compat: the degraded load answers Retail and keeps the guards' one-rung bodies
- compat: no file outside the library reads a WOW_PROJECT global or an interface number

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

### test_slash.lua (11)

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

### test_slashgate.lua (7)

- /rm enable and /rm disable write the Enable row's OWN path, through the one seam
- /rm disable echoes the stored value in the set shape, and /rm enable undoes it
- the pair is never one-way: the dispatcher still answers while the addon is disabled
- enable and disable hold no state of their own
- a refused `unlock` leaves the lock exactly where it was
- a refused `update` publishes nothing on the bus
- /rm profile <name> switches while the addon is disabled

### test_perf.lua (15)

- debug: the flag still flips and acks with LibKa0s absent
- debug: /rm debug names the missing library instead of erroring
- debug: every member the addon reaches for answers with LibKa0s absent
- perf: the addon loads with LibKa0s absent
- perf: /rm perf explains itself instead of erroring with LibKa0s absent
- every perf step label the library renders is prose, not its own STRINGS key
- Perf: the descriptor hands the library the FOLDER name, not just the frame name
- perf: the addon holds a real LibKa0s-Perf instance, on this addon's latch
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

### test_layers.lua (2)

- LAYERS names the HUD strata and an ordered level ladder
- no strata literal and no absolute level at any call site

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

### test_modes.lua (7)

- modes: each writer sets its mode, announces once on a change, and a repeat is silent
- modes: a start is refused in combat with one gray line, and nothing changes
- modes: entering combat ends both modes
- modes: neither mode is ever written to SavedVariables
- modes: /rm test and /rm sim toggle, take on and off, and refuse another word
- modes: the Master controls carry Test mode, then Sim mode, as session rows on the one writer
- modes: the launcher menu is Enabled, Locked, Test mode, Sim mode, each the verb's handler

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
- the General page draws Master controls first and the Skin tab last
- the General page is covered in combat on the sidebar path, and the window stays open (options-ui-§2)

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

### test_surface_parity.lua (14)

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

### test_skin_switch.lua (5)

- skin switch: the check is falsifiable, a surface that redraws a literal is reported
- skin switch: the debug console changes
- skin switch: the debug console changes with the Scope ignored
- skin switch: the perf panel changes
- skin switch: the perf panel changes with the Scope ignored

### test_client_globals.lua (3)

- client globals: no call of a global a client lacks
- client globals: every allowlist row has a reason and a finding to excuse
- client globals: the check is falsifiable, a planted bare call is flagged for both clients

## Totals

| Suite | Cases |
|-------|------:|
| test_loadorder.lua | 16 |
| test_schema.lua | 36 |
| test_database.lua | 9 |
| test_compat.lua | 6 |
| test_envsetup.lua | 6 |
| test_coresetup.lua | 8 |
| test_mediasetup.lua | 10 |
| test_debuglog.lua | 14 |
| test_slash.lua | 11 |
| test_slashgate.lua | 7 |
| test_perf.lua | 15 |
| test_bus.lua | 8 |
| test_layers.lua | 2 |
| test_launcher.lua | 30 |
| test_launcher_skin_entry.lua | 1 |
| test_modes.lua | 7 |
| test_optionssetup.lua | 16 |
| test_realpages.lua | 7 |
| test_skinsetup.lua | 12 |
| test_skin_picker.lua | 16 |
| test_skin_picker_preview.lua | 9 |
| test_glyphs.lua | 1 |
| test_locale.lua | 4 |
| test_docs.lua | 5 |
| test_prose.lua | 15 |
| test_surface_parity.lua | 14 |
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
| test_skin_switch.lua | 5 |
| test_client_globals.lua | 3 |
| Skipped | 1 |
| **Total** | **358** |
