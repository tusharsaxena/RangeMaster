# 04 Execution plan

Nothing adopted from the tag in this item. The re-vendor is one commit, SD-RV-RM:

1. Copy both payloads whole from the v1.108.0 extract; both diffs empty before the prune.
2. Roll the provenance line to v1.108.0; keep the `LibKa0s icons:` line.
3. Prune icons and sounds with the tag's `tools/prune-icons.lua`.
4. Hold the six composed blocks in `settings/Containers_Display.lua` at minor 19's rows (`fromSkin = false`) until SD-SK-RM.
5. Fix the two typed-value hits kit revision 58 reads: `Kit.skinValues.rows` in `tests/run.lua`, each with the kit category `unreachable default`.
6. Refresh the standard reference to v2.116.0: the vendored quirks block in `docs/midnight-quirks.md` restamped (its content is unchanged at v2.116.0).
7. `docs/test-cases.md` regenerated; the README Tests badge rolled to its total; smoke check DRAW-6 for the Bar dot's border and gloss.
8. Gate under both clients: `ka0s-bounded lua tests/run.lua`, `KA0S_KIT_CLIENT=forever ka0s-bounded lua tests/run.lua`, and `ka0s-bounded luacheck .` (0/0), every authored file under 1500 lines.
