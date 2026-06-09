-- luacheck config for the PackMarker WoW addon.
-- We target Lua 5.1 (the WoW runtime) and silence "undefined global" noise,
-- since the game exposes hundreds of APIs luacheck can't know about. Real
-- problems (unused locals, shadowing, syntax errors, bad scoping) still fire.
std = "lua51"
max_line_length = false
self = false

-- Globals our addon legitimately defines / writes to.
globals = {
    "PackMarkerDB",
    "SlashCmdList",
    "SLASH_PACKMARKER1", "SLASH_PACKMARKER2",
    "StaticPopupDialogs",   -- GUI registers a confirm dialog on this WoW table
}

ignore = {
    "113",  -- accessing an undefined global (WoW API)
    "143",  -- accessing an undefined field of a global (e.g. C_Timer.NewTicker)
}
