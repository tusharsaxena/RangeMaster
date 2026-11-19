-- tests/settings_env.lua — the shared harness of the settings suites (tests/test_settings_*.lua and
-- the container verbs in tests/test_slash.lua): a fresh profile with the selections cleared, chat
-- capture, the popup spy, and the real pages' contexts and the labels they drew.
-- Not a suite: each settings suite loads it with dofile.
--
-- Every case runs on a FRESH profile (the real db, the selections, the apply queue, the Undo slot
-- and the popup function put back however the case ends), so one case's containers never leak
-- into the next.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks

local E = {}

--- Run `body(p)` on a fresh profile.
function E.with(body)
  local saved = { db = NS.db, popup = M.StaticPopup_Show, combat = M.InCombatLockdown,
    selC = NS.State.selectedContainer, selB = NS.State.selectedBandSet, band = NS.State.selectedBand }
  local p = {}
  NS.db = { profile = p, global = saved.db.global }
  NS.State.selectedContainer, NS.State.selectedBandSet, NS.State.selectedBand = nil, nil, nil
  NS.CM.__reset()
  NS.Presets.__reset()
  local ok, err = pcall(function()
    NS.Database.PrepareProfile(p)
    body(p)
  end)
  -- The renderer's instances go too: a preview built here (the picker's) watches its units on the
  -- ticker, and a later suite would find them still watched.
  NS.Container.__reset()
  NS.CM.__reset()
  NS.Presets.__reset()
  NS.db = saved.db
  M.StaticPopup_Show, M.InCombatLockdown = saved.popup, saved.combat
  NS.State.selectedContainer, NS.State.selectedBandSet = saved.selC, saved.selB
  NS.State.selectedBand = saved.band
  if not ok then error(err, 0) end
end

--- Every chat line `fn` prints, color escapes stripped.
function E.capture(fn)
  local out = {}
  local cf = M.DEFAULT_CHAT_FRAME
  local old = rawget(cf, "AddMessage")
  cf.AddMessage = function(_, msg)
    out[#out + 1] = (tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err, 0) end
  return out
end

--- Whether any line of `out` contains `text` (plain).
function E.said(out, text)
  for _, line in ipairs(out) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

--- Record every StaticPopup_Show as { which, a, b }, answering a dialog stand-in whose `data` the
--- caller sets, as the client's does.
function E.spyPopups()
  local shown = {}
  M.StaticPopup_Show = function(which, a, b)
    local dialog = { which = which, a = a, b = b }
    shown[#shown + 1] = dialog
    return dialog
  end
  return shown
end

--- Accept `dialog` the way its OK button does.
function E.accept(dialog)
  M.StaticPopupDialogs[dialog.which].OnAccept(dialog, dialog.data)
end

--- The real page ctx for `pageKey`, rendered once through its OnShow.
function E.page(pageKey, name)
  local panel = M.__subcategories[name]
  if panel then panel:__fire("OnShow") end
  for _, c in ipairs(NS.Helpers.__panels()) do
    if c.pageKey == pageKey and c.scroll then return c end
  end
end

--- Every label text drawn in `ctx`'s scroll, as a set.
function E.labels(ctx)
  local seen = {}
  local function walk(w)
    for _, child in ipairs(w.children or {}) do
      if child.labelText then seen[child.labelText] = true end
      if child.text then seen[child.text] = true end
      walk(child)
    end
  end
  walk(ctx.scroll)
  return seen
end

--- The nav rail's entries as drawn on `ctx`, labels in order.
function E.railLabels(ctx)
  local out = {}
  for _, b in ipairs(ctx.__railKids or {}) do out[#out + 1] = b.__ka0sNavText end
  return out
end

return E
