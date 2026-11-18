local _, NS = ...
-- settings/About.lua — the landing page's spec: the logo, the TOC Notes line and the slash command
-- list, rendered by the library's BuildLandingPage (options-ui-§5). The body is DATA, not drawing
-- code: no host logo, no reparenting onto an AceGUI frame (options-ui-§19).


local Helpers = NS.Helpers

-- `notes` and `rows` are functions because both are resolved at RENDER time: the TOC's Notes field
-- is not readable when this spec is declared, and NS.COMMANDS keeps growing as later files load.
local SPEC = {
    logo  = NS.Constants.LOGO_PATH,
    notes = function() return NS.Meta("Notes") or "" end,
    sections = {
        {
            heading = NS.L["Slash Commands"],
            rows    = function() return NS.Slash:LandingRows() end,
        },
    },
}

function Helpers.BuildMainContent(ctx)
    Helpers.BuildLandingPage(ctx, SPEC)
end
