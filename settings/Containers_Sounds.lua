local _, NS = ...
-- settings/Containers_Sounds.lua — the Containers page's Sounds entry: whether the selected container
-- plays its bands' sounds, and on which channel (modules/Sounds.lua).
--
--     [ Sounds ]
--
--     [Play band sounds] [Sound channel]
--     Each band's own sound is chosen on Band sets > Bands.
--
-- NOT OFFERED FOR A `nameplates` CONTAINER (design spec 5.5): its per-plate instances never play one,
-- so the rail does not list an entry that would do nothing (`hiddenFor`, read by settings/Containers.lua).

local L = NS.L
local H = NS.Helpers

local PAGE = "containers_sounds"
local GROUP = L["Sounds"]

local CHANNELS = { Master = L["Master"], SFX = L["Effects"], Dialog = L["Dialog"], Music = L["Music"],
    Ambience = L["Ambience"] }
local CHANNELS_SORT = { "Master", "SFX", "Dialog", "Music", "Ambience" }

NS.RegisterSchemaRows(NS.StampSelectionRows({
    { path = "container.sounds.enabled", page = PAGE, group = GROUP, order = 10, type = "bool",
      label = L["Play band sounds"],
      desc = L["Play a band's sound when the unit enters it, after it has held for 0.2 seconds, at most once a second, and never on the first band after the unit changes."] },
    { path = "container.sounds.channel", page = PAGE, group = GROUP, order = 20, type = "string",
      values = CHANNELS, sorting = CHANNELS_SORT, label = L["Sound channel"],
      desc = L["The game's volume channel the sounds play on."] },
}))

local function soundsNote(ctx)
    H.TextRow(ctx, L["Each band's own sound is chosen on Band sets > Bands."], { fontObject = "GameFontDisableSmall" })
end

NS.RegisterContainerSection(PAGE, L["Sounds"], {
    tooltip = L["Band sounds: whether this container plays them, and on which channel."],
    hiddenFor = function(c) return NS.CM.IsPlates(c.unit) end,
    afterGroup = { [GROUP] = soundsNote },
})
