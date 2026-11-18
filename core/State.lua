local _, NS = ...
-- core/State.lua — session-only runtime state; nothing here is persisted to SavedVariables.
--
--   debug           the debug-console logging flag: off at login, reset on every /reload
--                   (debug-logging-§5); read and written only through core/DebugLogSetup.lua.
--   testMode        Test mode (preview-mode, options-ui-§15): every container shows placeholder
--                   ranges. Off at login, refused in combat, ended when combat starts; written only
--                   by NS.SetTestMode (core/RangeMaster.lua).
--   simMode         Sim mode: the distance simulator drives every container. The same lifetime
--                   rules as Test mode; written only by NS.SetSimMode (core/RangeMaster.lua).
--   rejectedEvents  every event name the client refused this session, appended once each by the
--                   SafeRegister helpers (core/CoreSetup.lua, events-frames-taint-§1).
NS.State = NS.State or {}
local State = NS.State

State.debug = false
State.testMode = false
State.simMode = false
State.rejectedEvents = State.rejectedEvents or {}
