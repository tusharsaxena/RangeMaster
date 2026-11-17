local addonName, NS = ...
-- core/Namespace.lua — the namespace bootstrap: NS.name, the fallback version and the [RM] chat tag.

-- NS is the addon's single private table (architecture-§1); there is deliberately no _G[addonName].
NS.name = addonName

-- The fallback version. core/EnvSetup.lua's NS.Version() prefers the TOC's `## Version:` field and
-- answers this only when the manifest cannot be read (a headless run, a client with no reader).
NS.version = "0.1.0"

-- The cyan [RM] chat tag (slash-commands-§4). One constant so every line prints identically;
-- core/CoreSetup.lua hands it to the library printer as a FUNCTION so a later change is not frozen.
NS.PREFIX = "|cFF00FFFF[RM]|r"
