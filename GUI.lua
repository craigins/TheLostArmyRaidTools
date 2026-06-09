-- PackMarker -- GUI
-- A control panel for the marking engine in PackMarker.lua. Everything here drives
-- the shared ns.API surface, so the buttons and the slash commands stay in lockstep
-- (the engine fires ns.FireChange() on every mutation, which refreshes this panel).
--
-- Layout:
--   LEFT  : raid -> pack browser (click a pack to activate it) + live pool status
--   RIGHT : raid roster, one row per player with 8 one-click icon buttons + clear
--   BOTTOM: marking + assignment action buttons
-- Plus a draggable minimap button and `/pmark gui` to toggle it.

local _, ns = ...
local API = ns.API

-- Clearing every assignment is destructive and has no undo, so it goes through a
-- confirmation popup -- a mid-raid misclick on "Clear Asn" shouldn't wipe the lot.
-- (Stash is the non-destructive way to set assignments aside.)
StaticPopupDialogs["PACKMARKER_CLEAR_ASSIGNMENTS"] = {
    text = "PackMarker: clear ALL target assignments?\nThis can't be undone -- use Stash to set them aside instead.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() API.assignClear() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,   -- avoids a known taint issue with the default index
}

-- ---------------------------------------------------------------------------
--  Constants / helpers
-- ---------------------------------------------------------------------------
local PACK_ROW_H, NUM_PACK_ROWS     = 18, 13
local ROSTER_ROW_H, NUM_ROSTER_ROWS = 24, 15

local ICON_ATLAS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
-- Fallback texcoords (4-wide grid) in case SetRaidTargetIconTexture isn't present.
local RT_COORDS = {
    [1] = {0,0.25,0,0.25},   [2] = {0.25,0.5,0,0.25},   [3] = {0.5,0.75,0,0.25},   [4] = {0.75,1,0,0.25},
    [5] = {0,0.25,0.25,0.5}, [6] = {0.25,0.5,0.25,0.5}, [7] = {0.5,0.75,0.25,0.5}, [8] = {0.75,1,0.25,0.5},
}
local function SetIcon(tex, idx)
    tex:SetTexture(ICON_ATLAS)
    if SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(tex, idx)
    else
        tex:SetTexCoord(unpack(RT_COORDS[idx]))
    end
end

-- Player role: the role the player actually set (UnitGroupRolesAssigned), else the
-- raid Main Tank flag; nil if unknown. Used for boss auto-fill + role icons.
local function playerRole(unit)
    if UnitGroupRolesAssigned then
        local r = UnitGroupRolesAssigned(unit)
        if r and r ~= "NONE" then return r end       -- "TANK" | "HEALER" | "DAMAGER"
    end
    if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return "TANK" end
    return nil
end

-- Inline Tank/Healer role icon for name text (DPS gets none, to keep it clean).
-- Prefer the crisp atlas role icons (modern raid-frame style); fall back to the
-- flat UI-LFG-ICON-ROLES texture only if the client doesn't have those atlases.
local ROLE_ATLAS   = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer" }
local ROLE_TCOORDS = { TANK = { 0, 19, 22, 41 }, HEALER = { 20, 39, 1, 20 } }  -- px in 64x64 atlas
local function atlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
local function roleIcon(role)
    if not role then return "" end
    local atlas = ROLE_ATLAS[role]
    if atlas and CreateAtlasMarkup and atlasExists(atlas) then
        return CreateAtlasMarkup(atlas, 16, 16) .. " "
    end
    local c = ROLE_TCOORDS[role]
    if not c then return "" end
    return ("|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:16:16:0:0:64:64:%d:%d:%d:%d|t "):format(c[1], c[2], c[3], c[4])
end
ns.RoleIcon = roleIcon   -- shared with BossAssign.lua

-- Stable collapse keys (must match the ones buildPackList generates).
local function expKey(exp)        return "exp\0" .. (exp.key or exp.label) end
local function raidKey(exp, raid) return "raid\0" .. (exp.key or exp.label) .. "\0" .. (raid.key or raid.label) end

local function EnsureDB()
    PackMarkerDB = PackMarkerDB or {}
    PackMarkerDB.minimap = PackMarkerDB.minimap or { angle = 200 }
    PackMarkerDB.gui = PackMarkerDB.gui or {}
    PackMarkerDB.gui.collapsed = PackMarkerDB.gui.collapsed or {}  -- [collapseKey] = true
    if PackMarkerDB.gui.autoZone == nil then PackMarkerDB.gui.autoZone = true end

    -- One-time seed: with many raids, a fully-expanded tree is overwhelming, so
    -- start every raid collapsed (you see expansion -> raid headers, then expand
    -- what you need). Runs once; never fights your folding afterward.
    if not PackMarkerDB.gui.seeded then
        PackMarkerDB.gui.seeded = true
        for _, exp in ipairs(ns.EXPANSIONS or {}) do
            for _, raid in ipairs(exp.raids or {}) do
                PackMarkerDB.gui.collapsed[raidKey(exp, raid)] = true
            end
        end
    end
end

-- Collapsed state for expansion/raid/section headers, persisted so it survives /reload.
local function isCollapsed(key)
    return PackMarkerDB and PackMarkerDB.gui and PackMarkerDB.gui.collapsed
        and PackMarkerDB.gui.collapsed[key] or false
end
local function toggleCollapse(key)
    EnsureDB()
    PackMarkerDB.gui.collapsed[key] = (not PackMarkerDB.gui.collapsed[key]) or nil
end

-- Collapse (state=true) or expand (state=false) EVERY header in the whole tree.
-- Keys must match the ones buildPackList generates. Used by right-click on a header.
local function setAllCollapsed(state)
    EnsureDB()
    local c = PackMarkerDB.gui.collapsed
    for _, exp in ipairs(ns.EXPANSIONS or {}) do
        c[expKey(exp)] = state or nil
        for _, raid in ipairs(exp.raids or {}) do
            local rKey = raidKey(exp, raid)
            c[rKey] = state or nil
            for si, sec in ipairs(raid.sections or {}) do
                c[rKey .. "\0" .. (sec.label or si)] = state or nil
            end
        end
    end
end

-- ---- zone detection ----
-- Normalize a zone/raid name for loose matching: lowercase, trim, drop a trailing
-- "(example)" tag so the shipped example labels still match their instance.
local function normZone(s)
    return (s or ""):lower():gsub("%s*%(example%)%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Find the expansion+raid for an instance name. A raid can declare raid.zone or
-- raid.zones = { ... } to list the exact GetInstanceInfo name(s); otherwise we fall
-- back to matching the raid's label. Returns exp, raid (or nil).
local function findRaidByZone(instanceName)
    local target = normZone(instanceName)
    if target == "" then return nil end
    for _, exp in ipairs(ns.EXPANSIONS or {}) do
        for _, raid in ipairs(exp.raids or {}) do
            local zones = raid.zones or (raid.zone and { raid.zone }) or nil
            if zones then
                for _, z in ipairs(zones) do
                    if normZone(z) == target then return exp, raid end
                end
            end
            if normZone(raid.label) == target then return exp, raid end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
--  Roster / pack-list data builders
-- ---------------------------------------------------------------------------

-- Fake raids for test mode, so the assignment UIs are usable solo. /pmark test [10|25].
local TEST_ROSTER_25 = {  -- 3 tanks / 5 healers / 17 dps
    { "Tankwar", "WARRIOR", "TANK" },   { "Tankdin", "PALADIN", "TANK" },   { "Tankbear", "DRUID", "TANK" },
    { "Holypal", "PALADIN", "HEALER" }, { "Holypriest", "PRIEST", "HEALER" }, { "Restodruid", "DRUID", "HEALER" },
    { "Restosham", "SHAMAN", "HEALER" },{ "Discpriest", "PRIEST", "HEALER" },
    { "Mageone", "MAGE", "DAMAGER" },   { "Magetwo", "MAGE", "DAMAGER" },   { "Magethree", "MAGE", "DAMAGER" },
    { "Lockone", "WARLOCK", "DAMAGER" },{ "Locktwo", "WARLOCK", "DAMAGER" },{ "Huntone", "HUNTER", "DAMAGER" },
    { "Hunttwo", "HUNTER", "DAMAGER" }, { "Rogueone", "ROGUE", "DAMAGER" }, { "Roguetwo", "ROGUE", "DAMAGER" },
    { "Furywar", "WARRIOR", "DAMAGER" },{ "Enhsham", "SHAMAN", "DAMAGER" }, { "Boomkin", "DRUID", "DAMAGER" },
    { "Shadowp", "PRIEST", "DAMAGER" }, { "Retpal", "PALADIN", "DAMAGER" }, { "Catdruid", "DRUID", "DAMAGER" },
    { "Elesham", "SHAMAN", "DAMAGER" }, { "Huntthree", "HUNTER", "DAMAGER" },
}
local TEST_ROSTER_10 = {  -- 2 tanks / 3 healers / 5 dps (Kara/ZA-sized)
    { "Tankwar", "WARRIOR", "TANK" },   { "Tankbear", "DRUID", "TANK" },
    { "Holypriest", "PRIEST", "HEALER" }, { "Holypal", "PALADIN", "HEALER" }, { "Restosham", "SHAMAN", "HEALER" },
    { "Mageone", "MAGE", "DAMAGER" },   { "Lockone", "WARLOCK", "DAMAGER" }, { "Huntone", "HUNTER", "DAMAGER" },
    { "Rogueone", "ROGUE", "DAMAGER" }, { "Shadowp", "PRIEST", "DAMAGER" },
}

local function assignedIconFor(A, name)   -- exact key, else ignore realm suffix
    local idx = A[name]
    if not idx then
        local short = name:match("^([^%-]+)") or name
        for k, v in pairs(A) do
            if (k:match("^([^%-]+)") or k) == short then idx = v break end
        end
    end
    return idx
end

-- The party/raid as a sorted list of { name=<Name-Realm key>, display=, color=, role=, assignedIdx= }.
local function buildRoster()
    local A = API.getAssignments()

    if ns.testMode then
        local src = (ns.testSize == 10) and TEST_ROSTER_10 or TEST_ROSTER_25
        local out = {}
        for i, p in ipairs(src) do
            local class = p[2]
            out[i] = {
                name = p[1], display = p[1], class = class, role = p[3],
                color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or nil,
                assignedIdx = assignedIconFor(A, p[1]),
            }
        end
        table.sort(out, function(a, b) return a.display < b.display end)
        return out
    end

    local out = {}
    local function add(unit)
        if not UnitExists(unit) then return end
        local full = GetUnitName(unit, true)   -- "Name" same-realm, "Name-Realm" cross-realm
        if not full then return end
        local _, class = UnitClass(unit)
        -- Find this player's assigned icon: exact key first, else ignore realm suffix.
        local idx = A[full]
        if not idx then
            local short = full:match("^([^%-]+)") or full
            for k, v in pairs(A) do
                if (k:match("^([^%-]+)") or k) == short then idx = v break end
            end
        end
        out[#out + 1] = {
            name = full,
            display = UnitName(unit) or full,
            class = class,   -- class file (e.g. "WARLOCK"), for boss-assignment matching
            role = playerRole(unit),   -- "TANK"/"HEALER"/"DAMAGER" or nil
            color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or nil,
            assignedIdx = idx,
        }
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    elseif IsInGroup() then
        add("player")
        for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
    else
        add("player")   -- solo: show yourself so the panel is usable for testing
    end

    table.sort(out, function(a, b) return a.display < b.display end)
    return out
end

-- Flat display list for the left browser: an expansion -> raid -> section -> pack
-- tree, honoring collapsed headers. Each row carries its `kind`, collapse key, and
-- whether it has children, so the row renderer draws the right indent/arrow.
local function buildPackList()
    local activeKey = API.getActive()
    local out = {}

    local function addPacks(packs)
        for _, p in ipairs(packs or {}) do
            out[#out + 1] = { kind = "pack", key = p.key, label = p.label, active = (p.key == activeKey) }
        end
    end

    for _, exp in ipairs(ns.EXPANSIONS or {}) do
        local eKey = expKey(exp)
        local eCollapsed = isCollapsed(eKey)
        out[#out + 1] = { kind = "expansion", label = exp.label, collapseKey = eKey,
                          collapsed = eCollapsed, hasChildren = true }
        if not eCollapsed then
            for _, raid in ipairs(exp.raids or {}) do
                local rKey = raidKey(exp, raid)
                local rCollapsed = isCollapsed(rKey)
                out[#out + 1] = { kind = "raid", label = raid.label, collapseKey = rKey,
                                  collapsed = rCollapsed, hasChildren = true }
                if not rCollapsed then
                    for si, sec in ipairs(raid.sections or {}) do
                        local sKey = rKey .. "\0" .. (sec.label or si)
                        local sCollapsed = isCollapsed(sKey)
                        local hasPacks = sec.packs and #sec.packs > 0
                        out[#out + 1] = { kind = "section", label = sec.label, collapseKey = sKey,
                                          collapsed = sCollapsed, hasChildren = hasPacks }
                        if hasPacks and not sCollapsed then addPacks(sec.packs) end
                    end
                    addPacks(raid.packs)   -- any packs listed directly on the raid
                    -- boss nodes for this raid (any encounter whose raid matches)
                    for _, enc in ipairs(ns.ENCOUNTERS or {}) do
                        if enc.raid == raid.label or enc.raid == raid.key then
                            out[#out + 1] = { kind = "boss", encKey = enc.key, label = enc.label }
                        end
                    end
                end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
--  A small recycled-row list built on FauxScrollFrame (classic-friendly).
-- ---------------------------------------------------------------------------
local function MakeList(name, parent, rowHeight, numRows, createRow, updateRow)
    -- The FauxScrollFrame handles the scrollbar + offset only; it holds no content.
    -- Position it inside the inset, leaving 20px on the right for the scrollbar.
    local scroll = CreateFrame("ScrollFrame", name, parent, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26, 6)

    local list = { scroll = scroll, rows = {}, rowHeight = rowHeight, numRows = numRows, items = {} }

    -- Rows are children of the INSET (not the scroll frame) and just sit over the
    -- scroll area, anchored relative to it. Parenting rows to a ScrollFrame can
    -- leave them unrendered; this is the pattern Blizzard's own list frames use.
    for i = 1, numRows do
        local row = createRow(parent)
        row:SetHeight(rowHeight)
        if i == 1 then
            row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", list.rows[i - 1], "BOTTOMLEFT", 0, 0)
        end
        row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
        list.rows[i] = row
    end

    function list:Refresh()
        local n = #self.items
        FauxScrollFrame_Update(scroll, n, self.numRows, self.rowHeight)
        local offset = FauxScrollFrame_GetOffset(scroll)
        for i = 1, self.numRows do
            local item = self.items[i + offset]
            if item then
                updateRow(self.rows[i], item)
                self.rows[i]:Show()
            else
                self.rows[i]:Hide()
            end
        end
    end
    function list:SetItems(items) self.items = items or {}; self:Refresh() end

    -- Scroll so the row carrying `collapseKey` is visible near the top.
    function list:ScrollToKey(key)
        for i, item in ipairs(self.items) do
            if item.collapseKey == key then
                local maxOffset = math.max(0, #self.items - self.numRows)
                local off = math.min(i - 1, maxOffset)
                local bar = _G[name .. "ScrollBar"]
                if bar then bar:SetValue(off * self.rowHeight) end
                self:Refresh()
                return
            end
        end
    end

    scroll:SetScript("OnVerticalScroll", function(self, value)
        FauxScrollFrame_OnVerticalScroll(self, value, rowHeight, function() list:Refresh() end)
    end)
    return list
end

-- Share the proven building blocks with the boss-assignment module (BossAssign.lua).
ns.MakeList    = MakeList
ns.BuildRoster = buildRoster

-- ---------------------------------------------------------------------------
--  Panel construction (lazy: built on first toggle)
-- ---------------------------------------------------------------------------
local frame          -- the main panel
local packList, rosterList, statusFS

local function RefreshPanel()
    if not frame or not frame:IsShown() then return end
    packList:SetItems(buildPackList())
    rosterList:SetItems(buildRoster())

    -- Active-pack pool status.
    local activeKey = API.getActive()
    if not activeKey then
        statusFS:SetText("|cff808080No pack active. Click one on the left.|r")
        return
    end
    local status = API.getGroupStatus(activeKey)
    local lines = {}
    if status then
        for _, g in ipairs(status) do
            local marks = {}
            for _, m in ipairs(g.marks) do
                -- icon + label; free = green, used = struck-through grey
                if m.used then
                    marks[#marks + 1] = API.iconTex(m.idx) .. "|cff808080" .. m.label .. "|r"
                else
                    marks[#marks + 1] = API.iconTex(m.idx) .. "|cff40ff40" .. m.label .. "|r"
                end
            end
            lines[#lines + 1] = "|cffffd100" .. table.concat(g.names, " / ") .. "|r"
            lines[#lines + 1] = "   " .. table.concat(marks, "  ")
        end
    end
    statusFS:SetText(table.concat(lines, "\n"))
end

-- Coalesce bursts of events into one refresh next frame.
local refreshQueued = false
local function RefreshSoon()
    if refreshQueued or not frame or not frame:IsShown() then return end
    refreshQueued = true
    C_Timer.After(0.05, function() refreshQueued = false; RefreshPanel() end)
end

-- Auto zone focus: when you enter a known raid instance, fold every expansion and
-- raid except the one you're standing in (and unfold that one), then scroll to it.
-- Fires only when the detected instance CHANGES, so it won't undo your manual
-- folding mid-raid. Folding others is a real (persisted) collapse, so you can still
-- expand anything by hand afterwards. `force` re-applies even if the zone is the same.
local function applyZoneFocus(force)
    EnsureDB()
    if not PackMarkerDB.gui.autoZone then return end

    local exp, raid
    if IsInInstance() then exp, raid = findRaidByZone((GetInstanceInfo())) end
    if not raid then
        ns._lastFocusKey = nil   -- left / unknown instance: allow a future re-focus
        return
    end

    local rKey = raidKey(exp, raid)
    if not force and ns._lastFocusKey == rKey then return end
    ns._lastFocusKey = rKey

    local collapsed = PackMarkerDB.gui.collapsed
    for _, e in ipairs(ns.EXPANSIONS or {}) do
        collapsed[expKey(e)] = true
        for _, r in ipairs(e.raids or {}) do collapsed[raidKey(e, r)] = true end
    end
    collapsed[expKey(exp)] = nil     -- unfold the one we're in
    collapsed[rKey] = nil

    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffPackMarker:|r auto-focused on |cffffff00"
        .. raid.label .. "|r.")

    if frame and frame:IsShown() then
        RefreshPanel()
        packList:ScrollToKey(rKey)
    end
end

-- Exposed so the slash command can re-run detection on demand (`/pmark zone`).
ns.ZoneFocus = function() applyZoneFocus(true) end

-- ----- left: pack browser row (expansion / raid / section / pack) -----
local ROW_INDENT = { expansion = 5, raid = 15, section = 26, boss = 26, pack = 38 }  -- left pad per level
local ARROW_OPEN, ARROW_SHUT = "\226\150\190 ", "\226\150\184 "  -- ▾ / ▸
local MARK_ACTIVE = "\226\150\182 "                              -- ▶ (active pack)

-- Tooltip for a pack row: every mob in the pack with its mark + ability notes
-- (from ns.MOBINFO), plus an optional pack.note. Headers get a short hint instead.
local function showRowTooltip(row)
    if row.kind == "pack" then
        local pack = row.packKey and ns.PACKS and ns.PACKS[row.packKey]
        if not pack then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(pack.label or row.packKey, 1, 1, 1)
        for _, group in ipairs(pack.groups or {}) do
            local markStr = ""
            for _, mn in ipairs(group.marks or {}) do
                local idx = API.MARK_INDEX[mn]
                if idx then markStr = markStr .. API.iconTex(idx) end
            end
            for _, name in ipairs(group.names or {}) do
                GameTooltip:AddLine(markStr .. " " .. name, 1, 0.82, 0)
                local info = ns.MOBINFO and ns.MOBINFO[name]
                if info then
                    for _, line in ipairs(info) do
                        GameTooltip:AddLine("   " .. line, 0.8, 0.8, 0.8, true)
                    end
                end
            end
        end
        if pack.note then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(pack.note, 0.6, 0.85, 1, true)
        end
        GameTooltip:Show()
    elseif row.kind == "boss" then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.headerLabel or "Boss", 1, 0.45, 0.35)
        GameTooltip:AddLine("Click to open boss assignments.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    elseif row.collapseKey then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(row.headerLabel or "", 1, 1, 1)
        GameTooltip:AddLine("Left-click: fold/unfold.  Right-click: fold/unfold ALL.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end
end

local function createPackRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.9, 0.8, 0.2, 0.22)
    row.bg:Hide()
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    if row:GetHighlightTexture() then row:GetHighlightTexture():SetAlpha(0.35) end
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self, button)
        if self.kind == "pack" then
            if self.packKey then API.selectPack(self.packKey) end
        elseif self.kind == "boss" then
            if self.encKey and ns.OpenBossFor then ns.OpenBossFor(self.encKey) end
        elseif self.collapseKey then     -- header
            if button == "RightButton" then
                setAllCollapsed(not isCollapsed(self.collapseKey))  -- this header drives the direction
            else
                toggleCollapse(self.collapseKey)
            end
            RefreshPanel()
        end
    end)
    row:SetScript("OnEnter", showRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function updatePackRow(row, item)
    row.kind = item.kind
    row.packKey = (item.kind == "pack") and item.key or nil
    row.encKey = (item.kind == "boss") and item.encKey or nil
    row.collapseKey = item.collapseKey
    row.headerLabel = (item.kind ~= "pack") and item.label or nil

    -- If the tooltip is currently anchored to this (recycled) row, refresh it.
    if GameTooltip:IsShown() and GameTooltip:GetOwner() == row then showRowTooltip(row) end

    -- arrow only on headers that actually have children to fold
    local arrow = ""
    if item.kind ~= "pack" and item.hasChildren then
        arrow = item.collapsed and ARROW_SHUT or ARROW_OPEN
    end

    if item.kind == "expansion" then
        row.bg:Hide()
        row.text:SetText(arrow .. item.label)
        row.text:SetTextColor(0.8, 0.6, 1)        -- light purple
    elseif item.kind == "raid" then
        row.bg:Hide()
        row.text:SetText(arrow .. item.label)
        row.text:SetTextColor(0.45, 0.8, 1)       -- blue
    elseif item.kind == "section" then
        row.bg:Hide()
        row.text:SetText(arrow .. item.label)
        row.text:SetTextColor(1, 0.82, 0.3)       -- gold
    elseif item.kind == "boss" then
        row.bg:Hide()
        -- crossed-swords texture (renders reliably, unlike a unicode glyph)
        row.text:SetText("|TInterface\\GossipFrame\\BattleMasterGossipIcon:14|t " .. item.label)
        row.text:SetTextColor(1, 0.45, 0.35)      -- red -- distinct from trash sections
    else  -- pack
        row.bg:SetShown(item.active)
        row.text:SetText((item.active and MARK_ACTIVE or "") .. item.label)
        if item.active then row.text:SetTextColor(1, 1, 0.5) else row.text:SetTextColor(0.85, 0.85, 0.85) end
    end

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", ROW_INDENT[item.kind] or 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
end

-- ----- right: roster row -----
local function onIconClick(row, idx)
    if not row.fullName then return end
    if row.assignedIdx == idx then
        -- clicking the current icon clears the assignment
        local key = API.findAssignedKey(row.fullName) or row.fullName
        API.unassignPlayer(key)
    else
        -- replace any existing assignment (possibly keyed without realm) then set
        local existing = API.findAssignedKey(row.fullName)
        if existing and existing ~= row.fullName then API.unassignPlayer(existing) end
        API.assignPlayer(row.fullName, idx, true)   -- quiet: panel shows the state
    end
end

local function createRosterRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    if row:GetHighlightTexture() then row:GetHighlightTexture():SetAlpha(0.2) end

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetWidth(108)
    row.name:SetJustifyH("LEFT")

    -- clear (remove assignment) button on the far right
    local clr = CreateFrame("Button", nil, row)
    clr:SetSize(16, 16)
    clr:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    clr:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    clr:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    clr:SetScript("OnClick", function()
        if row.fullName then
            local key = API.findAssignedKey(row.fullName) or row.fullName
            API.unassignPlayer(key)
        end
    end)
    clr:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Clear assignment"); GameTooltip:Show()
    end)
    clr:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.clear = clr

    -- eight raid-target icon buttons, left to right after the name
    row.icons = {}
    local prev
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(18, 18)
        if i == 1 then b:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
        else            b:SetPoint("LEFT", prev, "RIGHT", 2, 0) end
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        SetIcon(t, i)
        b.icon = t
        local glow = b:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("TOPLEFT", -2, 2)
        glow:SetPoint("BOTTOMRIGHT", 2, -2)
        glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        glow:SetBlendMode("ADD")
        glow:Hide()
        b.glow = glow
        b:SetScript("OnClick", function() onIconClick(row, i) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((API.MARK_LABEL[i] or "?") .. "  |cff808080(click to assign)|r")
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.icons[i] = b
        prev = b
    end
    return row
end

local function updateRosterRow(row, item)
    row.fullName = item.name
    row.assignedIdx = item.assignedIdx
    row.name:SetText(roleIcon(item.role) .. item.display)
    if item.color then row.name:SetTextColor(item.color.r, item.color.g, item.color.b)
    else                row.name:SetTextColor(1, 1, 1) end

    local a = item.assignedIdx
    for i = 1, 8 do
        local b = row.icons[i]
        if a then
            local on = (i == a)
            b.icon:SetDesaturated(not on)
            b:SetAlpha(on and 1 or 0.45)
            b.glow:SetShown(on)
        else
            b.icon:SetDesaturated(false)
            b:SetAlpha(0.9)
            b.glow:Hide()
        end
    end
    row.clear:SetShown(a ~= nil)
end

-- ----- bottom action buttons -----
local function makeButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function BuildPanel()
    EnsureDB()

    frame = CreateFrame("Frame", "PackMarkerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(648, 472)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        PackMarkerDB.gui.point = { p, rp, x, y }
    end)
    frame:SetScript("OnShow", RefreshPanel)
    if PackMarkerDB.gui.point then
        local pt = PackMarkerDB.gui.point
        frame:ClearAllPoints()
        frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    end
    tinsert(UISpecialFrames, "PackMarkerFrame")  -- ESC closes

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("PackMarker")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- open the boss-assignment window
    local bossBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    bossBtn:SetSize(96, 20)
    bossBtn:SetPoint("TOPLEFT", 14, -12)
    bossBtn:SetText("Boss Assigns")
    bossBtn:SetScript("OnClick", function() if ns.ToggleBossGUI then ns.ToggleBossGUI() end end)

    -- auto zone-focus toggle (top-right, left of the close button)
    local zcb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    zcb:SetSize(24, 24)
    zcb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -12)
    zcb:SetChecked(PackMarkerDB.gui.autoZone)
    zcb:SetScript("OnClick", function(self)
        PackMarkerDB.gui.autoZone = self:GetChecked() and true or false
        if PackMarkerDB.gui.autoZone then applyZoneFocus(true) end
    end)
    zcb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Auto-focus zone")
        GameTooltip:AddLine("When you enter a known raid, fold every other expansion/raid and jump to this one.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    zcb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local zcbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zcbl:SetPoint("RIGHT", zcb, "LEFT", -2, 0)
    zcbl:SetText("Auto-zone")

    -- section headers
    local lhead = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lhead:SetPoint("TOPLEFT", 20, -42); lhead:SetText("Raids / Packs")
    local rhead = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rhead:SetPoint("TOPLEFT", 286, -42); rhead:SetText("Raid roster  |cff808080(click an icon to assign)|r")

    -- left: pack browser inset
    local packInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    packInset:SetPoint("TOPLEFT", 16, -58)
    packInset:SetSize(256, 244)
    packList = MakeList("PackMarkerPackScroll", packInset, PACK_ROW_H, NUM_PACK_ROWS, createPackRow, updatePackRow)

    -- left: active-pack pool status inset
    local statusInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    statusInset:SetPoint("TOPLEFT", packInset, "BOTTOMLEFT", 0, -8)
    statusInset:SetSize(256, 120)
    local statusHead = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusHead:SetPoint("BOTTOMLEFT", statusInset, "TOPLEFT", 4, 2)
    statusHead:SetText("|cffffffffActive pack -- mark pools|r")
    statusFS = statusInset:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFS:SetPoint("TOPLEFT", 8, -8)
    statusFS:SetPoint("BOTTOMRIGHT", -8, 8)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetJustifyV("TOP")
    statusFS:SetSpacing(2)

    -- right: roster inset
    local rosterInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    rosterInset:SetPoint("TOPLEFT", 282, -58)
    rosterInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 46)
    rosterList = MakeList("PackMarkerRosterScroll", rosterInset, ROSTER_ROW_H, NUM_ROSTER_ROWS, createRosterRow, updateRosterRow)

    -- bottom: action buttons (two clusters: marking, then assignments)
    local y = 14
    local off    = makeButton(frame, "Stop",        58, function() API.stopMarking() end)
    local reset  = makeButton(frame, "Reset Pool",  76, function() API.resetPools() end)
    local clear  = makeButton(frame, "Clear Marks", 84, function() API.clearAllMarks() end)
    local report = makeButton(frame, "Report",      62, function() API.assignReport() end)
    local remind = makeButton(frame, "Remind",      62, function() API.assignRemind() end)
    local stash  = makeButton(frame, "Stash",       54, function() API.assignStash() end)
    local restore= makeButton(frame, "Restore",     64, function() API.assignRestore() end)
    local clrAsn = makeButton(frame, "Clear Asn",   72, function() StaticPopup_Show("PACKMARKER_CLEAR_ASSIGNMENTS") end)

    off:SetPoint("BOTTOMLEFT", 16, y)
    reset:SetPoint("LEFT", off, "RIGHT", 4, 0)
    clear:SetPoint("LEFT", reset, "RIGHT", 4, 0)
    clrAsn:SetPoint("BOTTOMRIGHT", -16, y)
    restore:SetPoint("RIGHT", clrAsn, "LEFT", -4, 0)
    stash:SetPoint("RIGHT", restore, "LEFT", -4, 0)
    remind:SetPoint("RIGHT", stash, "LEFT", -4, 0)
    report:SetPoint("RIGHT", remind, "LEFT", -4, 0)

    -- stay in sync with engine + group/marker changes while open
    ns.OnChange(RefreshSoon)
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("RAID_TARGET_UPDATE")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function() RefreshSoon() end)

    -- Built shown-by-default; hide it so the first ToggleGUI opens (and OnShow
    -- populates) rather than immediately closing it.
    frame:Hide()
end

-- ---------------------------------------------------------------------------
--  Toggle + minimap button
-- ---------------------------------------------------------------------------
function ns.ToggleGUI()
    if not frame then BuildPanel() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

local function CreateMinimapButton()
    EnsureDB()
    local b = CreateFrame("Button", "PackMarkerMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ICON_ATLAS)
    if SetRaidTargetIconTexture then SetRaidTargetIconTexture(icon, 8) else icon:SetTexCoord(unpack(RT_COORDS[8])) end

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function reposition()
        local angle = math.rad(PackMarkerDB.minimap.angle or 200)
        b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
    end

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if ns.ToggleBossGUI then ns.ToggleBossGUI() end
        else
            ns.ToggleGUI()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local s = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / s, cy / s
            PackMarkerDB.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
            reposition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("PackMarker")
        GameTooltip:AddLine("|cffffffffLeft-click|r: marking panel", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffRight-click|r: boss assignments", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    reposition()
end

-- Saved variables are ready at PLAYER_LOGIN; set up the minimap button then, and
-- watch for instance changes to drive auto zone focus.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")   -- fires on every instance/zone load
loader:SetScript("OnEvent", function(_, event)
    EnsureDB()
    if event == "PLAYER_LOGIN" then
        CreateMinimapButton()
    end
    -- Both events: re-evaluate the current instance (no-op if unchanged/unknown).
    applyZoneFocus()
end)
