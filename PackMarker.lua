-- PackMarker
-- Auto-marks trash packs on mouseover, out of combat only.
--
-- You pick an active pack (e.g. via an OPie ring -> macro slice `/pmark Crystalcore`).
-- While a pack is active, hovering a mob whose name is listed in that pack gets the
-- next unused mark from its group's pool. Mobs already marked are left untouched, and
-- if a group's pool is exhausted it warns instead of stealing a mark.
--
-- Pack DATA lives in Packs.lua (loaded first, see the .toc). This file is the engine.

-- ===========================================================================
--  Internals
-- ===========================================================================

local ADDON, ns = ...        -- ADDON = "PackMarker"; ns = shared namespace from Packs.lua

-- Flatten the expansion->raid->section->pack tree (Packs.lua defines
-- ns.EXPANSIONS) into a key->pack lookup, which is what the marking engine works
-- against. Each pack gets back-references so the GUI / `/pmark list` can label it.
local PACKS = {}             -- [packKey] = pack

-- Visit every pack in a raid, whether it's grouped into sections or listed flat
-- under raid.packs (a raid may use either or both; sections come first).
local function forEachPackInRaid(raid, fn)
    for _, sec in ipairs(raid.sections or {}) do
        for _, pack in ipairs(sec.packs or {}) do fn(pack, sec) end
    end
    for _, pack in ipairs(raid.packs or {}) do fn(pack, nil) end
end
ns.forEachPackInRaid = forEachPackInRaid   -- GUI reuses this

local function buildPackIndex()
    wipe(PACKS)
    for _, expansion in ipairs(ns.EXPANSIONS or {}) do
        for _, raid in ipairs(expansion.raids or {}) do
            forEachPackInRaid(raid, function(pack, sec)
                if PACKS[pack.key] then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555PackMarker:|r duplicate pack key '"
                        .. tostring(pack.key) .. "' -- keys must be unique.")
                end
                pack.expansionKey   = expansion.key
                pack.expansionLabel = expansion.label
                pack.raidKey        = raid.key
                pack.raidLabel      = raid.label
                pack.sectionLabel   = sec and sec.label or nil
                PACKS[pack.key] = pack
            end)
        end
    end
end
buildPackIndex()
ns.PACKS = PACKS             -- expose the flat lookup (engine + API read this)

-- Tiny change-notification hub so the GUI can refresh when engine/assignment
-- state changes, regardless of whether the change came from a button or a slash
-- command. ns.OnChange(fn) subscribes; the engine calls ns.FireChange() after a
-- mutation. Kept dependency-free on purpose.
ns.refreshFns = {}
function ns.OnChange(fn) ns.refreshFns[#ns.refreshFns + 1] = fn end
function ns.FireChange()
    for _, fn in ipairs(ns.refreshFns) do pcall(fn) end
end

-- Addon version, read from the .toc (works across old/new metadata APIs).
local function getMeta(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then return C_AddOns.GetAddOnMetadata(ADDON, field) end
    if GetAddOnMetadata then return GetAddOnMetadata(ADDON, field) end
end
local ADDON_VERSION = getMeta("Version") or "?"
ns.version = ADDON_VERSION

local MARK_INDEX = {
    STAR = 1, CIRCLE = 2, DIAMOND = 3, TRIANGLE = 4,
    MOON = 5, SQUARE = 6, CROSS = 7, X = 7, SKULL = 8,
}
local MARK_LABEL = {
    [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross(X)", [8] = "Skull",
}

local active = nil          -- key of the active pack, or nil = off
local fallbackUsed = {}     -- [packKey][groupIndex][markIndex] = true (resets on pack select)
local lastWarn = {}         -- [groupKey] = GetTime() of last "out of marks" warning
local assigned = {}         -- [guid] = true for units we've marked this session
                            -- (GetRaidTargetIndex lags after SetRaidTarget, so a fast
                            --  re-fire of UPDATE_MOUSEOVER_UNIT would otherwise let one
                            --  mob consume a second mark; this dedupes by GUID)

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. ADDON .. ":|r " .. tostring(msg))
end

-- Print a mob's stored ability/kill notes (from MobInfo.lua), if any. Returns
-- true if it printed something.
local function printMobInfo(name)
    local info = name and ns.MOBINFO and ns.MOBINFO[name]
    if not info then return false end
    for _, line in ipairs(info) do
        DEFAULT_CHAT_FRAME:AddMessage("   |cffaaaaaa" .. line .. "|r")
    end
    return true
end

-- Send a raid-lead chat message, unless test mode is on -- then print it locally
-- (so you can test whispers/announces solo without messaging absent players).
local function rlSend(msg, channel, target)
    if ns.testMode then
        Print("|cff888888[test " .. (channel == "WHISPER" and ("-> " .. (target or "?")) or channel) .. "]|r " .. msg)
    else
        SendChatMessage(msg, channel, nil, target)
    end
end

-- Build a quick name->group lookup for the active pack (rebuilt on select).
local nameLookup = {}  -- [mobName] = { group = <group>, gi = <index> }
local function rebuildLookup(packKey)
    wipe(nameLookup)
    local pack = packKey and PACKS[packKey]
    if not pack then return end
    for gi, group in ipairs(pack.groups) do
        for _, n in ipairs(group.names) do
            nameLookup[n] = { group = group, gi = gi }
        end
    end
end

-- Visit every enemy unit we currently have a token for (for live "used mark" scan).
local function forEachVisibleUnit(fn)
    fn("target")
    fn("mouseover")
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local u = plate.namePlateUnitToken
            if u then fn(u) end
        end
    else
        for i = 1, 40 do
            local u = "nameplate" .. i
            if UnitExists(u) then fn(u) end
        end
    end
end

-- Which marks from this group are already placed in the world right now?
local function usedMarksForGroup(group, gi)
    local used = {}
    -- internal fallback (covers units we can't currently see, e.g. nameplates off)
    local fb = active and fallbackUsed[active] and fallbackUsed[active][gi]
    if fb then for idx in pairs(fb) do used[idx] = true end end
    -- live scan (self-correcting if a mob died / mark was cleared)
    local nameset = {}
    for _, n in ipairs(group.names) do nameset[n] = true end
    forEachVisibleUnit(function(u)
        local n = UnitName(u)
        if n and nameset[n] then
            local idx = GetRaidTargetIndex(u)
            if idx and idx > 0 then used[idx] = true end
        end
    end)
    return used
end

local function canMark()
    if IsInRaid() then
        return UnitIsGroupLeader("player")
            or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
    end
    return true  -- party or solo: anyone can set marks
end

local function tryMark(unit)
    if not active then return end
    if InCombatLockdown() then return end
    if not UnitExists(unit) then return end
    if UnitIsPlayer(unit) then return end
    if not UnitCanAttack("player", unit) then return end
    if UnitIsDead(unit) then return end
    if (GetRaidTargetIndex(unit) or 0) > 0 then return end  -- already marked: never change it

    local guid = UnitGUID(unit)
    if guid and assigned[guid] then return end  -- we just marked this unit; icon may not have registered yet

    local name = UnitName(unit)
    local entry = name and nameLookup[name]
    if not entry then return end  -- mob not in this pack

    local group, gi = entry.group, entry.gi
    local used = usedMarksForGroup(group, gi)

    for _, markName in ipairs(group.marks) do
        local idx = MARK_INDEX[markName]
        if idx and not used[idx] then
            SetRaidTarget(unit, idx)
            if guid then assigned[guid] = true end
            fallbackUsed[active] = fallbackUsed[active] or {}
            fallbackUsed[active][gi] = fallbackUsed[active][gi] or {}
            fallbackUsed[active][gi][idx] = true
            return
        end
    end

    -- Pool exhausted: warn (throttled), do NOT steal an existing mark.
    local key = active .. ":" .. gi
    local now = GetTime()
    if not lastWarn[key] or (now - lastWarn[key]) > 5 then
        lastWarn[key] = now
        Print("|cffff5555out of marks|r for " .. table.concat(group.names, "/")
            .. " (pool: " .. table.concat(group.marks, ", ") .. "). Not stealing a mark.")
    end
end

-- ===========================================================================
--  Pack selection / commands
-- ===========================================================================

local function selectPack(key)
    active = key
    fallbackUsed[key] = {}   -- reset this pack's pools
    wipe(assigned)
    wipe(lastWarn)
    rebuildLookup(key)
    if PackMarkerDB then PackMarkerDB.active = key end
    Print("active pack: |cffffff00" .. PACKS[key].label .. "|r (marks reset).")
    if not canMark() then
        Print("|cffff5555note:|r you're not raid leader/assist, so marks won't apply.")
    end
    ns.FireChange()
end

-- Stop marking (the `/pmark off` action; exposed so the GUI shares it).
local function stopMarking()
    active = nil
    if PackMarkerDB then PackMarkerDB.active = nil end
    Print("marking |cffff0000off|r.")
    ns.FireChange()
end

-- Reset the active pack's mark pools without changing which pack is active.
local function resetPools()
    if active then
        fallbackUsed[active] = {}
        wipe(assigned)
        wipe(lastWarn)
        Print("reset mark pools for " .. PACKS[active].label .. ".")
        ns.FireChange()
    else
        Print("no active pack.")
    end
end

local function findPackKey(input)
    if not input or input == "" then return nil end
    local lc = input:lower()
    for k in pairs(PACKS) do
        if k:lower() == lc then return k end
    end
    return nil
end

local function listPacks()
    Print("available packs:")
    for _, expansion in ipairs(ns.EXPANSIONS or {}) do
        Print("|cffcc99ff" .. expansion.label .. "|r")
        for _, raid in ipairs(expansion.raids or {}) do
            Print("  |cff88ddff" .. raid.label .. "|r")
            for _, sec in ipairs(raid.sections or {}) do
                Print("    |cffffcc55" .. sec.label .. "|r")
                for _, p in ipairs(sec.packs or {}) do
                    Print("      |cffffff00/pmark " .. p.key .. "|r  - " .. p.label)
                end
            end
            for _, p in ipairs(raid.packs or {}) do
                Print("    |cffffff00/pmark " .. p.key .. "|r  - " .. p.label)
            end
        end
    end
end

-- Live pool status for the active pack, for the GUI. For each group, reports its
-- names and, per mark, whether that mark is currently placed in the world. Marks
-- only reflect live usage when the pack is the active one (otherwise all "free").
local function getGroupStatus(packKey)
    local pack = PACKS[packKey]
    if not pack then return nil end
    local out = {}
    for gi, group in ipairs(pack.groups) do
        local used = (active == packKey) and usedMarksForGroup(group, gi) or {}
        local marks = {}
        for _, markName in ipairs(group.marks) do
            local idx = MARK_INDEX[markName]
            marks[#marks + 1] = { idx = idx, label = MARK_LABEL[idx], used = used[idx] or false }
        end
        out[gi] = { names = group.names, marks = marks }
    end
    return out
end

-- Clear every raid marker in the world. Markers are unique (one unit per icon), so
-- stealing each icon 1..8 onto the player removes it from whatever mob holds it; then
-- we clear it off the player. SetRaidTarget changes get dropped if fired too fast, and
-- the dropped one is usually the final clear -- which is why it'd leave a Skull stuck on
-- you that a second /pmark clear would fix. So we space the steals out AND verify the
-- final clear actually landed, retrying until GetRaidTargetIndex("player") reads 0.
-- (This clears your own marker too.)
local function clearAllMarks()
    if not canMark() then
        Print("|cffff5555can't clear:|r you're not raid leader/assist.")
        return
    end

    -- Phase 2: clear the player's icon, retrying until it actually sticks.
    local function clearSelf(tries)
        SetRaidTarget("player", 0)
        C_Timer.After(0.1, function()
            if (GetRaidTargetIndex("player") or 0) ~= 0 and tries < 12 then
                clearSelf(tries + 1)
            end
        end)
    end

    -- Phase 1: steal each icon onto the player, one per tick, then start clearing.
    local i = 0
    local function steal()
        i = i + 1
        if i <= 8 then
            SetRaidTarget("player", i)
            C_Timer.After(0.05, steal)
        else
            clearSelf(1)
        end
    end
    steal()

    -- Reset internal state so re-marking starts fresh.
    if active then fallbackUsed[active] = {} end
    wipe(assigned)
    wipe(lastWarn)
    Print("clearing all raid markers...")
    ns.FireChange()
end

-- ===========================================================================
--  Target assignments (player -> icon), stored in PackMarkerDB.assignments
-- ===========================================================================

-- {rtN} renders as the icon in CHAT messages (whisper/raid/party).
local function iconChat(idx) return "{rt" .. idx .. "}" end
-- Texture escape renders the icon in LOCAL prints (AddMessage doesn't expand {rtN}).
local function iconTex(idx)
    return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. idx .. ":0|t"
end

local function getAssignments()
    PackMarkerDB = PackMarkerDB or {}
    PackMarkerDB.assignments = PackMarkerDB.assignments or {}
    return PackMarkerDB.assignments
end

local function copyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function countTable(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- Accepts a number 1-8 or a mark name (skull, x, moon, ...). Returns an index or nil.
local function parseIcon(s)
    if not s or s == "" then return nil end
    local n = tonumber(s)
    if n and n >= 1 and n <= 8 then return n end
    return MARK_INDEX[s:upper()]
end

local function whisperAssignment(name, idx)
    rlSend("Your target is " .. iconChat(idx), "WHISPER", name)
end

-- Stable, icon-then-name sorted list of {name, idx}.
local function sortedAssignments()
    local list = {}
    for name, idx in pairs(getAssignments()) do
        list[#list + 1] = { name = name, idx = idx }
    end
    table.sort(list, function(a, b)
        if a.idx ~= b.idx then return a.idx < b.idx end
        return a.name < b.name
    end)
    return list
end

-- Core assignment write: store name->icon, whisper the player, notify the GUI.
-- `quiet` suppresses the local chat print (the GUI shows the state itself, so it
-- passes quiet=true to avoid spamming chat on every icon click). Still whispers.
local function assignPlayer(name, idx, quiet)
    if not name or not idx then return end
    getAssignments()[name] = idx
    whisperAssignment(name, idx)
    if not quiet then
        Print("assigned |cffffff00" .. name .. "|r -> " .. iconTex(idx) .. " " .. MARK_LABEL[idx] .. " (whispered).")
    end
    ns.FireChange()
end

-- Remove one player's assignment by exact stored key. Used by the GUI's per-row
-- clear button (slash-command removal goes through assignRemove, which resolves
-- partial names first).
local function unassignPlayer(name)
    local a = getAssignments()
    if name and a[name] then
        a[name] = nil
        ns.FireChange()
    end
end

local function assignTarget(iconArg)
    local idx = parseIcon(iconArg)
    if not idx then
        Print("usage: |cffffff00/pmark assign <1-8 or icon name>|r  (e.g. /pmark assign skull)")
        return
    end
    if not UnitExists("target") or not UnitIsPlayer("target") then
        Print("target a player first, then /pmark assign " .. (iconArg or "") .. ".")
        return
    end
    local name = GetUnitName("target", true)
    if not name then Print("couldn't read your target's name.") return end
    assignPlayer(name, idx)
end

local function assignClear()
    PackMarkerDB = PackMarkerDB or {}
    PackMarkerDB.assignments = {}
    Print("cleared all target assignments.")
    ns.FireChange()
end

local function assignShow()
    local list = sortedAssignments()
    if #list == 0 then
        Print("no assignments. Target a player and use |cffffff00/pmark assign <icon>|r.")
        return
    end
    Print("target assignments:")
    for _, e in ipairs(list) do
        Print("  " .. iconTex(e.idx) .. " " .. MARK_LABEL[e.idx] .. " -> |cffffff00" .. e.name .. "|r")
    end
end

local function assignRemind()
    local list = sortedAssignments()
    if #list == 0 then Print("no assignments to remind.") return end
    for _, e in ipairs(list) do
        whisperAssignment(e.name, e.idx)
    end
    Print("re-whispered " .. #list .. " assignment(s).")
end

local function assignReport()
    local list = sortedAssignments()
    if #list == 0 then Print("no assignments to report.") return end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not channel and not ns.testMode then Print("not in a group -- nowhere to report to.") return end
    rlSend("Target assignments:", channel)
    -- Group players under each icon, one line per icon (list is sorted icon-then-name).
    local curIdx, names = nil, {}
    local function flush()
        if curIdx then
            rlSend(iconChat(curIdx) .. " " .. MARK_LABEL[curIdx]
                .. " = " .. table.concat(names, ", "), channel)
        end
    end
    for _, e in ipairs(list) do
        if e.idx ~= curIdx then
            flush()
            curIdx, names = e.idx, {}
        end
        names[#names + 1] = e.name
    end
    flush()
end

-- One-level stash: save current assignments aside and clear, e.g. swap CC duty for
-- boss kick duty, then restore the CC assignments afterwards. Persists across /reload.
local function assignStash()
    PackMarkerDB = PackMarkerDB or {}
    local n = countTable(getAssignments())
    if n == 0 then Print("no assignments to stash.") return end
    local prev = countTable(PackMarkerDB.stash)
    PackMarkerDB.stash = copyTable(getAssignments())
    PackMarkerDB.assignments = {}
    if prev > 0 then
        Print("stashed " .. n .. " assignment(s) and cleared current (replaced a previous stash of " .. prev .. ").")
    else
        Print("stashed " .. n .. " assignment(s) and cleared current. |cffffff00/pmark assign restore|r to bring them back.")
    end
    ns.FireChange()
end

local function assignRestore()
    PackMarkerDB = PackMarkerDB or {}
    if countTable(PackMarkerDB.stash) == 0 then Print("nothing in the stash to restore.") return end
    local replaced = countTable(getAssignments())
    PackMarkerDB.assignments = copyTable(PackMarkerDB.stash)
    PackMarkerDB.stash = nil
    local msg = "restored " .. countTable(PackMarkerDB.assignments) .. " assignment(s) from stash"
    if replaced > 0 then msg = msg .. " (replaced " .. replaced .. " current)" end
    Print(msg .. ". |cffffff00/pmark assign remind|r to re-whisper.")
    ns.FireChange()
end

-- Match an input name to a stored assignment key, ignoring case and realm.
-- Returns the key on a single match, or (nil, matches) when zero or many match.
local function findAssignedKey(input)
    local a = getAssignments()
    local lc = input:lower()
    for name in pairs(a) do                       -- exact (case-insensitive) wins
        if name:lower() == lc then return name end
    end
    local short = lc:match("^([^%-]+)") or lc     -- else match on short name (strip realm)
    local matches = {}
    for name in pairs(a) do
        local nameShort = name:lower():match("^([^%-]+)") or name:lower()
        if nameShort == short then matches[#matches + 1] = name end
    end
    if #matches == 1 then return matches[1] end
    return nil, matches
end

-- Remove one player's assignment. By name (works even if they've left the raid),
-- or by current target when no name is given.
local function assignRemove(arg)
    local a = getAssignments()
    local key
    if arg and arg ~= "" then
        local matched, matches = findAssignedKey(arg)
        if matched then
            key = matched
        elseif matches and #matches > 1 then
            Print("'" .. arg .. "' matches several: " .. table.concat(matches, ", ")
                .. ". Use the full Name-Realm.")
            return
        else
            Print("no assignment found for '" .. arg .. "'. |cffffff00/pmark assign show|r to list.")
            return
        end
    else
        if not UnitExists("target") or not UnitIsPlayer("target") then
            Print("usage: |cffffff00/pmark assign remove <name>|r  (or target the player, then /pmark assign remove)")
            return
        end
        key = findAssignedKey(GetUnitName("target", true) or "")
        if not key then Print("your target has no assignment.") return end
    end
    local idx = a[key]
    a[key] = nil
    Print("removed " .. iconTex(idx) .. " " .. MARK_LABEL[idx] .. " from |cffffff00" .. key .. "|r.")
    ns.FireChange()
end

-- Responses to a "!assignment" whisper, for raiders with goldfish memory. %s is the
-- icon + label. Keep them ASCII-friendly (WoW chat is picky about emoji).
local ASSIGNED_REPLIES = {
    "Your target is %s. Try to remember this time! :)",
    "%s is all yours -- don't let me down!",
    "Psst... you're on %s. Eyes up, hero.",
    "You drew %s. Go get 'em!",
    "It's %s. Yes, still. It hasn't changed since last pull. <3",
}
local UNASSIGNED_REPLIES = {
    "You're off the hook this one -- just DPS and don't stand in the bad!",
    "No CC for you! Free as a bird. Fly, you fool!",
    "Nothing assigned to you. Sit back, relax, and pew pew.",
    "You're a free agent this fight. Make good choices.",
    "No target on you -- so no excuses if we wipe. ;)",
}

local lastWhisperReply = {}  -- [sender] = GetTime(), throttles replies

local function pick(t) return t[math.random(#t)] end

-- A raider whispered "!assignment". Reply with their icon, or a friendly all-clear.
local function handleAssignmentWhisper(sender)
    local now = GetTime()
    if lastWhisperReply[sender] and (now - lastWhisperReply[sender]) < 5 then return end
    lastWhisperReply[sender] = now

    local key = findAssignedKey(sender)
    local reply
    if key then
        local idx = getAssignments()[key]
        reply = pick(ASSIGNED_REPLIES):format(iconChat(idx) .. " " .. MARK_LABEL[idx])
    else
        reply = pick(UNASSIGNED_REPLIES)
    end
    SendChatMessage(reply, "WHISPER", nil, sender)
end

local function handleAssign(rest)
    rest = rest or ""
    local sub = rest:match("^(%S*)"):lower()
    local subArg = rest:match("^%S+%s+(.*)$")     -- everything after the subcommand (e.g. a name)
    if subArg then subArg = subArg:gsub("%s+$", "") end

    if sub == "" then
        Print("assignment commands:")
        Print("  |cffffff00/pmark assign <icon>|r        - assign your target to an icon (1-8 or name) + whisper them")
        Print("  |cffffff00/pmark assign remove <name>|r - remove a player's assignment (omit name to use target)")
        Print("  |cffffff00/pmark assign show|r          - list who has what")
        Print("  |cffffff00/pmark assign remind|r        - re-whisper everyone their assignment")
        Print("  |cffffff00/pmark assign report|r        - announce assignments to raid/party chat")
        Print("  |cffffff00/pmark assign stash|r         - save current assignments aside and clear")
        Print("  |cffffff00/pmark assign restore|r       - bring stashed assignments back")
        Print("  |cffffff00/pmark assign clear|r         - remove all assignments")
    elseif sub == "clear" then
        assignClear()
    elseif sub == "show" then
        assignShow()
    elseif sub == "remind" then
        assignRemind()
    elseif sub == "report" then
        assignReport()
    elseif sub == "stash" then
        assignStash()
    elseif sub == "restore" then
        assignRestore()
    elseif sub == "remove" then
        assignRemove(subArg)
    else
        assignTarget(sub)  -- sub is the icon (a single token)
    end
end

SLASH_PACKMARKER1 = "/packmark"
SLASH_PACKMARKER2 = "/pmark"
SlashCmdList["PACKMARKER"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd = msg:match("^(%S*)")
    local lc = cmd:lower()

    if lc == "" or lc == "help" then
        Print("|cffffff00v" .. ADDON_VERSION .. "|r commands:")
        Print("  |cffffff00/pmark gui|r     - open the control panel (raids, packs, assignments)")
        Print("  |cffffff00/pmark boss|r    - open boss mechanic/position assignments")
        Print("  |cffffff00/pmark test|r    - test mode for solo testing: |cffffff00/pmark test 10|r or |cffffff0025|r (fake raid)")
        Print("  |cffffff00/pmark zone|r    - fold the tree to the raid you're currently in")
        Print("  |cffffff00/pmark <pack>|r  - activate a pack (resets its mark pools)")
        Print("  |cffffff00/pmark off|r     - stop marking")
        Print("  |cffffff00/pmark reset|r   - reset the active pack's mark pools")
        Print("  |cffffff00/pmark clear|r   - remove ALL raid markers in the world")
        Print("  |cffffff00/pmark assign|r  - assign players to icons + whisper them (see /pmark assign)")
        Print("  |cffffff00/pmark list|r    - list packs")
        Print("  |cffffff00/pmark name|r    - print hovered/target mob's exact name + type (+ notes)")
        Print("  |cffffff00/pmark info|r    - print a mob's ability/kill notes (hover/target or <name>)")
        Print("  status: " .. (active and ("ON -> " .. PACKS[active].label) or "OFF"))
        return
    elseif lc == "off" then
        stopMarking()
        return
    elseif lc == "reset" then
        resetPools()
        return
    elseif lc == "gui" or lc == "show" or lc == "ui" then
        if ns.ToggleGUI then ns.ToggleGUI() else Print("GUI not loaded.") end
        return
    elseif lc == "zone" then
        if ns.ZoneFocus then ns.ZoneFocus() else Print("GUI not loaded.") end
        return
    elseif lc == "boss" then
        if ns.ToggleBossGUI then ns.ToggleBossGUI() else Print("Boss module not loaded.") end
        return
    elseif lc == "version" or lc == "ver" then
        Print("version |cffffff00" .. ADDON_VERSION .. "|r by " .. (getMeta("Author") or "?") .. ".")
        return
    elseif lc == "test" then
        local arg = msg:match("^%S+%s+(%S+)")   -- optional size / off
        if arg == "off" then
            ns.testMode = nil
        elseif arg == "10" or arg == "25" then
            ns.testMode = true; ns.testSize = tonumber(arg)
        else
            ns.testMode = not ns.testMode and true or nil  -- bare /pmark test toggles
        end
        ns.testSize = ns.testSize or 25
        if ns.testMode then
            Print("|cffff8800TEST MODE ON (" .. ns.testSize .. "-man)|r -- fake raid roster; whispers/announces"
                .. " print locally as |cff888888[test]|r. |cffffff00/pmark test 10|r, |cffffff00/pmark test 25|r,"
                .. " or |cffffff00/pmark test off|r (auto-off on /reload).")
        else
            Print("test mode |cffff0000OFF|r.")
        end
        ns.FireChange()
        return
    elseif lc == "clear" then
        clearAllMarks()
        return
    elseif lc == "assign" then
        handleAssign(msg:match("^%S+%s*(.*)$") or "")
        return
    elseif lc == "list" then
        listPacks()
        return
    elseif lc == "name" then
        local u = UnitExists("mouseover") and "mouseover" or "target"
        if UnitExists(u) then
            local nm = UnitName(u) or "?"
            Print("unit: |cffffff00" .. nm .. "|r  type: "
                .. (UnitCreatureType(u) or "?")
                .. "  mark: " .. (MARK_LABEL[GetRaidTargetIndex(u) or 0] or "none"))
            printMobInfo(nm)
        else
            Print("hover or target a mob first, then /pmark name.")
        end
        return
    elseif lc == "info" then
        local rest = msg:match("^%S+%s+(.*)$")
        local nm = (rest and rest ~= "") and rest or nil
        if not nm then
            local u = UnitExists("mouseover") and "mouseover" or "target"
            if UnitExists(u) then nm = UnitName(u) end
        end
        if not nm then
            Print("usage: |cffffff00/pmark info <mob name>|r  (or hover/target a mob)")
        else
            Print("info for |cffffff00" .. nm .. "|r:")
            if not printMobInfo(nm) then Print("   |cff808080no notes stored -- add them in MobInfo.lua|r") end
        end
        return
    end

    local key = findPackKey(cmd)
    if key then
        selectPack(key)
    else
        Print("unknown pack '" .. cmd .. "'.")
        listPacks()
    end
end

-- ===========================================================================
--  Internal API (consumed by GUI.lua)
-- ===========================================================================
-- One shared surface so the GUI and the slash commands drive the exact same
-- engine. Everything that mutates state calls ns.FireChange(), so an open GUI
-- stays in sync no matter where the change originated.
ns.API = {
    -- pack / marking
    selectPack    = selectPack,
    stopMarking   = stopMarking,
    resetPools    = resetPools,
    clearAllMarks = clearAllMarks,
    getActive     = function() return active end,
    getGroupStatus = getGroupStatus,
    canMark       = canMark,

    -- assignments
    assignPlayer   = assignPlayer,    -- (name, idx[, quiet])
    unassignPlayer = unassignPlayer,  -- (name)
    assignClear    = assignClear,
    assignRemind   = assignRemind,
    assignReport   = assignReport,
    assignStash    = assignStash,
    assignRestore  = assignRestore,
    getAssignments = getAssignments,
    findAssignedKey = findAssignedKey,

    -- labels / lookups
    MARK_LABEL = MARK_LABEL,
    MARK_INDEX = MARK_INDEX,
    iconTex    = iconTex,
}

-- ===========================================================================
--  Events
-- ===========================================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("CHAT_MSG_WHISPER")

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            PackMarkerDB = PackMarkerDB or {}
            math.randomseed(time())  -- vary the !assignment replies
            -- Note: we do NOT auto-activate on login; pick a pack when you get there.
            Print("|cffffff00v" .. ADDON_VERSION .. "|r loaded. |cffffff00/pmark|r for commands, |cffffff00/pmark list|r for packs.")
        end
        return
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        tryMark("mouseover")
    elseif event == "CHAT_MSG_WHISPER" then
        local text, sender = arg1, arg2
        if text and sender and text:lower():match("^%s*!assignment") then
            handleAssignmentWhisper(sender)
        end
    end
end)
