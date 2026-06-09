-- PackMarker -- BOSS ASSIGNMENTS
-- A self-contained window for per-boss duty/position assignments. Reads encounter
-- templates from Encounters.lua, auto-fills slots from the CURRENT raid by
-- class/role, lets you override by hand, then whispers / announces / displays them.
-- Reuses the building blocks shared by GUI.lua (ns.MakeList, ns.BuildRoster).

local _, ns = ...

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffPackMarker:|r " .. tostring(msg))
end

-- Send to chat, or print locally when test mode is on (solo testing).
local function send(msg, channel, target)
    if ns.testMode then
        Print("|cff888888[test" .. (channel == "WHISPER" and (" -> " .. (target or "?")) or "") .. "]|r " .. msg)
    else
        SendChatMessage(msg, channel, nil, target)
    end
end

-- Best-effort role -> class map (TBC has no role API; class match is exact, role
-- is a starting guess you override in the panel).
local ROLE_BY_CLASS = {
    WARRIOR = { "TANK", "MELEE" },
    ROGUE   = { "MELEE" },
    HUNTER  = { "RANGED" },
    MAGE    = { "RANGED" },
    WARLOCK = { "RANGED" },
    PRIEST  = { "HEALER", "RANGED" },
    PALADIN = { "TANK", "HEALER", "MELEE" },
    DRUID   = { "TANK", "HEALER", "MELEE", "RANGED" },
    SHAMAN  = { "HEALER", "MELEE", "RANGED" },
}

-- key -> encounter index
local encByKey = {}
for _, enc in ipairs(ns.ENCOUNTERS or {}) do encByKey[enc.key] = enc end

local function shortName(n) return (n and n:match("^([^%-]+)")) or n end

local function slotById(enc, slotId)
    for _, s in ipairs(enc.slots or {}) do if s.id == slotId then return s end end
end

-- ---------------------------------------------------------------------------
--  Storage:  PackMarkerDB.boss[encKey][slotId] = { "Name-Realm", ... }
-- ---------------------------------------------------------------------------
local function ensureDB()
    PackMarkerDB = PackMarkerDB or {}
    PackMarkerDB.boss = PackMarkerDB.boss or {}
    return PackMarkerDB.boss
end
local function encStore(encKey)
    local db = ensureDB()
    db[encKey] = db[encKey] or {}
    return db[encKey]
end
local function slotList(encKey, slotId)
    local s = encStore(encKey)
    s[slotId] = s[slotId] or {}
    return s[slotId]
end

-- ---------------------------------------------------------------------------
--  Resolution
-- ---------------------------------------------------------------------------
local function hasClassRole(classFile, role)
    local roles = classFile and ROLE_BY_CLASS[classFile]
    if roles then for _, r in ipairs(roles) do if r == role then return true end end end
    return false
end

-- Does a roster player satisfy a slot's need? Respects the player's ACTUAL role
-- (player.role, from UnitGroupRolesAssigned / Main Tank) when it's set; only falls
-- back to the class-capability guess when the player hasn't set a role.
local function matchesNeed(player, need)
    if not need then return true end
    if need.class then
        if type(need.class) == "table" then
            for _, c in ipairs(need.class) do if c == player.class then return true end end
            return false
        end
        return need.class == player.class
    end
    if need.role then
        local want, pr = need.role, player.role         -- pr: TANK/HEALER/DAMAGER or nil
        if want == "TANK" or want == "HEALER" then
            if pr then return pr == want end            -- explicit role wins
            return hasClassRole(player.class, want)      -- else class can-do guess
        else                                            -- MELEE / RANGED / DPS
            if pr == "TANK" or pr == "HEALER" then return false end  -- never a dps slot
            if want == "DPS" then return true end
            return hasClassRole(player.class, want)      -- MELEE/RANGED refined by class
        end
    end
    return true
end

-- Fill every slot that has a `need` from the current raid; each raider used once
-- across duty slots. Slots without `need` (free positions) are left untouched.
local function autoFill(encKey)
    local enc = encByKey[encKey]
    if not enc then return end
    local roster = ns.BuildRoster and ns.BuildRoster() or {}
    local store = encStore(encKey)
    local usedDuty, usedPos = {}, {}

    for _, slot in ipairs(enc.slots) do
        if slot.need then
            local kind = slot.kind or "duty"
            local used = (kind == "position") and usedPos or usedDuty
            local count = slot.count or 1
            local picked = {}
            for _, p in ipairs(roster) do
                if #picked >= count then break end
                if not used[p.name] and matchesNeed(p, slot.need) then
                    picked[#picked + 1] = p.name
                    used[p.name] = true
                end
            end
            store[slot.id] = picked
        end
    end
    Print("auto-filled |cffffff00" .. enc.label .. "|r from the current raid (edit as needed).")
end

local function toggleAssign(encKey, slotId, name)
    local enc = encByKey[encKey]; if not enc then return end
    local list = slotList(encKey, slotId)
    for i, n in ipairs(list) do
        if n == name then table.remove(list, i); return end   -- already in: remove
    end
    local slot = slotById(enc, slotId)
    local count = (slot and slot.count) or 1
    if #list >= count then table.remove(list, 1) end           -- full: drop the oldest
    list[#list + 1] = name
end

local function clearSlot(encKey, slotId)
    encStore(encKey)[slotId] = {}
end

local function clearEncounter(encKey)
    ensureDB()[encKey] = {}
    Print("cleared assignments for |cffffff00" .. (encByKey[encKey] and encByKey[encKey].label or encKey) .. "|r.")
end

local function whisperAll(encKey)
    local enc = encByKey[encKey]; if not enc then return end
    local store = encStore(encKey)
    local jobs = {}   -- [name] = { "label", ... }
    for _, slot in ipairs(enc.slots) do
        for _, name in ipairs(store[slot.id] or {}) do
            jobs[name] = jobs[name] or {}
            jobs[name][#jobs[name] + 1] = slot.label
        end
    end
    local n = 0
    for name, list in pairs(jobs) do
        send("[" .. enc.label .. "] Your assignment: " .. table.concat(list, "; "), "WHISPER", name)
        n = n + 1
    end
    if n == 0 then Print("nothing assigned to whisper.") else Print("whispered " .. n .. " player(s).") end
end

local function announce(encKey)
    local enc = encByKey[encKey]; if not enc then return end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not channel and not ns.testMode then Print("not in a group -- nowhere to announce.") return end
    local store = encStore(encKey)
    local any = false
    send(enc.label .. " assignments:", channel)
    for _, slot in ipairs(enc.slots) do
        local list = store[slot.id]
        if list and #list > 0 then
            local names = {}
            for _, n in ipairs(list) do names[#names + 1] = shortName(n) end
            send(slot.label .. ": " .. table.concat(names, ", "), channel)
            any = true
        end
    end
    if not any then Print("nothing assigned to announce.") end
end

-- ---------------------------------------------------------------------------
--  Window
-- ---------------------------------------------------------------------------
local frame, encList, slotListUI, rosterListUI, hintFS
local selEnc, selSlot   -- current selection

local function Refresh()
    if not frame or not frame:IsShown() then return end

    -- default to first encounter
    if not selEnc and ns.ENCOUNTERS and ns.ENCOUNTERS[1] then selEnc = ns.ENCOUNTERS[1].key end

    -- encounter list (raid headers + boss rows)
    local encItems, lastRaid = {}, nil
    for _, enc in ipairs(ns.ENCOUNTERS or {}) do
        if enc.raid ~= lastRaid then encItems[#encItems + 1] = { kind = "raid", label = enc.raid }; lastRaid = enc.raid end
        encItems[#encItems + 1] = { kind = "boss", key = enc.key, label = enc.label }
    end
    encList:SetItems(encItems)

    -- slot list for the selected encounter
    local enc = selEnc and encByKey[selEnc]
    local slotItems = {}
    if enc then
        local store = encStore(enc.key)
        for _, slot in ipairs(enc.slots) do
            slotItems[#slotItems + 1] = { slot = slot, names = store[slot.id] or {} }
        end
    end
    slotListUI:SetItems(slotItems)

    local tm = ns.testMode and ("|cffff8800[TEST " .. (ns.testSize or 25) .. "]|r  ") or ""
    if enc then
        hintFS:SetText(tm .. "|cffffd100" .. enc.label .. "|r  -- click a slot, then click raiders to fill it")
    else
        hintFS:SetText(tm .. "|cff808080Select an encounter on the left.|r")
    end

    rosterListUI:SetItems(ns.BuildRoster and ns.BuildRoster() or {})
end

local refreshQueued = false
local function RefreshSoon()
    if refreshQueued or not frame or not frame:IsShown() then return end
    refreshQueued = true
    C_Timer.After(0.05, function() refreshQueued = false; Refresh() end)
end

-- ----- encounter row -----
local function createEncRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    if row:GetHighlightTexture() then row:GetHighlightTexture():SetAlpha(0.3) end
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.2, 0.5, 1, 0.25); row.bg:Hide()
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if self.encKey then selEnc = self.encKey; selSlot = nil; Refresh() end
    end)
    return row
end
local function updateEncRow(row, item)
    row.text:ClearAllPoints()
    if item.kind == "raid" then
        row.encKey = nil
        row.bg:Hide()
        row.text:SetPoint("LEFT", 4, 0); row.text:SetPoint("RIGHT", -4, 0)
        row.text:SetText(item.label); row.text:SetTextColor(0.45, 0.8, 1)
    else
        row.encKey = item.key
        row.bg:SetShown(item.key == selEnc)
        row.text:SetPoint("LEFT", 14, 0); row.text:SetPoint("RIGHT", -4, 0)
        row.text:SetText(item.label)
        if item.key == selEnc then row.text:SetTextColor(1, 1, 0.5) else row.text:SetTextColor(0.9, 0.9, 0.9) end
    end
end

-- ----- slot row -----
local function createSlotRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    if row:GetHighlightTexture() then row:GetHighlightTexture():SetAlpha(0.25) end
    row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
    row.sel:SetColorTexture(0.2, 0.5, 1, 0.25); row.sel:Hide()

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("TOPLEFT", 6, -3); row.label:SetPoint("RIGHT", -22, 0)
    row.label:SetJustifyH("LEFT"); row.label:SetWordWrap(false)

    row.who = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.who:SetPoint("BOTTOMLEFT", 14, 3); row.who:SetPoint("RIGHT", -22, 0)
    row.who:SetJustifyH("LEFT"); row.who:SetWordWrap(false)

    local clr = CreateFrame("Button", nil, row)
    clr:SetSize(16, 16); clr:SetPoint("RIGHT", -3, 0)
    clr:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    clr:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    clr:SetScript("OnClick", function()
        if selEnc and row.slotId then clearSlot(selEnc, row.slotId); Refresh() end
    end)
    row.clear = clr

    row:SetScript("OnClick", function(self)
        if self.slotId then selSlot = self.slotId; Refresh() end
    end)
    return row
end
local function updateSlotRow(row, item)
    local slot = item.slot
    row.slotId = slot.id
    local count = slot.count or 1
    local tag = (slot.kind == "position") and "|cff88ddff[pos]|r " or ""
    row.label:SetText(tag .. slot.label)

    local names = {}
    for _, n in ipairs(item.names) do names[#names + 1] = shortName(n) end
    local whoStr = (#names > 0) and table.concat(names, ", ") or "--"
    row.who:SetText(whoStr .. "  |cff707070(" .. #item.names .. "/" .. count .. ")|r")

    row.sel:SetShown(slot.id == selSlot)
    row.clear:SetShown(#item.names > 0)
end

-- ----- roster row -----
local function createRosterRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    if row:GetHighlightTexture() then row:GetHighlightTexture():SetAlpha(0.2) end
    row.tick = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.tick:SetPoint("LEFT", 4, 0); row.tick:SetText("|cff40ff40+|r")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 18, 0); row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if not selEnc then Print("pick an encounter first.") return end
        if not selSlot then Print("pick a slot first (click one in the middle).") return end
        if self.playerName then toggleAssign(selEnc, selSlot, self.playerName); Refresh() end
    end)
    return row
end
local function updateRosterRow(row, item)
    row.playerName = item.name
    row.text:SetText((ns.RoleIcon and ns.RoleIcon(item.role) or "") .. item.display)
    if item.color then row.text:SetTextColor(item.color.r, item.color.g, item.color.b)
    else row.text:SetTextColor(1, 1, 1) end

    local inSlot = false
    if selEnc and selSlot then
        for _, n in ipairs(slotList(selEnc, selSlot)) do
            if n == item.name then inSlot = true break end
        end
    end
    row.tick:SetShown(inSlot)
end

local function makeButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22); b:SetText(text); b:SetScript("OnClick", onClick)
    return b
end

local function Build()
    ensureDB()
    frame = CreateFrame("Frame", "PackMarkerBossFrame", UIParent, "BackdropTemplate")
    frame:SetSize(720, 500)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", Refresh)
    tinsert(UISpecialFrames, "PackMarkerBossFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16); title:SetText("PackMarker -- Boss Assignments")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    hintFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintFS:SetPoint("TOPLEFT", 18, -38); hintFS:SetPoint("RIGHT", -16, 0); hintFS:SetJustifyH("LEFT")

    -- column headers
    local h1 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h1:SetPoint("TOPLEFT", 18, -56); h1:SetText("Bosses")
    local h2 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h2:SetPoint("TOPLEFT", 216, -56); h2:SetText("Slots")
    local h3 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h3:SetPoint("TOPLEFT", 522, -56); h3:SetText("Raid roster")

    -- left: encounters
    local encInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    encInset:SetPoint("TOPLEFT", 16, -72); encInset:SetPoint("BOTTOMLEFT", 16, 46); encInset:SetWidth(190)
    encList = ns.MakeList("PackMarkerBossEncScroll", encInset, 18, 20, createEncRow, updateEncRow)

    -- middle: slots
    local slotInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    slotInset:SetPoint("TOPLEFT", 214, -72); slotInset:SetPoint("BOTTOMLEFT", 214, 46); slotInset:SetWidth(300)
    slotListUI = ns.MakeList("PackMarkerBossSlotScroll", slotInset, 30, 12, createSlotRow, updateSlotRow)

    -- right: roster
    local rosterInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    rosterInset:SetPoint("TOPLEFT", 520, -72); rosterInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 46)
    rosterListUI = ns.MakeList("PackMarkerBossRosterScroll", rosterInset, 22, 16, createRosterRow, updateRosterRow)

    -- bottom buttons
    local fill = makeButton(frame, "Auto-fill",   80, function() if selEnc then autoFill(selEnc); Refresh() end end)
    local wh   = makeButton(frame, "Whisper All", 90, function() if selEnc then whisperAll(selEnc) end end)
    local ann  = makeButton(frame, "Announce",    80, function() if selEnc then announce(selEnc) end end)
    local clr  = makeButton(frame, "Clear",       70, function() if selEnc then clearEncounter(selEnc); Refresh() end end)
    fill:SetPoint("BOTTOMLEFT", 16, 14)
    wh:SetPoint("LEFT", fill, "RIGHT", 6, 0)
    ann:SetPoint("LEFT", wh, "RIGHT", 6, 0)
    clr:SetPoint("BOTTOMRIGHT", -16, 14)

    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function() RefreshSoon() end)
    if ns.OnChange then ns.OnChange(RefreshSoon) end   -- refresh on test-mode toggle, etc.

    frame:Hide()
end

function ns.ToggleBossGUI()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- Open the window focused on a specific encounter (used by boss rows in the tree).
function ns.OpenBossFor(encKey)
    if not frame then Build() end
    if encByKey[encKey] then selEnc = encKey; selSlot = nil end
    frame:Show()
    Refresh()
end
