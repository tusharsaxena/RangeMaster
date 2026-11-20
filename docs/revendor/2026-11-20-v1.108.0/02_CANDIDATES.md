# 02 Candidates, LibKa0s v1.107.0 -> v1.108.0

Sources: `git -C ../LibKa0s log --oneline v1.107.0..v1.108.0`; LibKa0s CHANGELOG.md, the v1.108.0 block and its *What a consumer owes at its re-vendor*.

**Class A, delivered on the copy alone**
- The Bar dot (`modules/Elements_Indicator.lua`, `W.Bar` with `W.BarStyle("mini")`) draws a skin's real border and, under Glass, the skin's gloss (WidgetsBar minor 2, SD-LK-97.2 and 97.3). The release names this addon's indicator bar as the intended case.
- The footer lays only its shown marks (Widgets minor 30). The preset picker's footer carries no hidden mark, so nothing it draws moves.
- The shared menu measures no secret label and tints a submenu arrow from the menu palette (WidgetsDropdown minor 3). The preset picker's dropdown shows no secret label and no submenu.
- A drag strip whose rect reads secret places its tooltip above its nearest readable ancestor (WidgetsDragHandleTip minor 3). A screen container's strip reads its rect, so nothing moves.

**Class B, host change required**
- OptionsCompose minor 20's companions (`fontFromSkin`, `fontColorFromSkin`, `fontShadowFromSkin`, Font flags From skin, `borderStyleFromSkin`, `borderColorFromSkin`, ColorPair's `<key>FromSkin`). Held off in the re-vendor commit (`fromSkin = false`) and taken up by SD-SK-RM, the run's item for this addon's audit rows.
- `W.OwnerWarnings(owner, sink)`, new: a debug-gated report of an owner-less library widget in an owned window. Every library widget this addon builds passes its owner. Not offered: the run interview is skipped (SD-RV-RM); noted for the lead.
- `Core.ApplySkin`'s `skinBands`, `Callout:FollowKeys` / `MoveToSkin`, WaypointArrow's companions: none applies. This addon draws no window edge of its own and calls no Callout or WaypointArrow.

**Class C, whole-module**: none new.

**Blockers (3g)**: none. The schema failures the composers caused and the two new typed-value hits are fixed in the re-vendor commit.
