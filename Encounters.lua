-- PackMarker -- ENCOUNTER (boss) ASSIGNMENT TEMPLATES
-- ===========================================================================
--  ns.ENCOUNTERS is an ORDERED list of boss encounters. Each encounter has a
--  list of SLOTS -- a duty or a position that one or more raiders fill. The
--  addon auto-fills slots from the CURRENT raid (by class/role) and you tweak
--  by hand; assignments are then whispered / announced / shown in the panel.
--
--    encounter = { key=, label=, raid=, slots = { <slot>, ... } }
--    slot = {
--        id    = "unique-within-encounter",
--        label = "what to do / where to stand",
--        kind  = "duty" | "position",   -- default "duty"
--        count = <how many raiders>,    -- default 1
--        need  = { class = "WARLOCK" }  -- auto-fill filter (optional). Forms:
--                  class = "MAGE"  or  class = { "MAGE", "HUNTER" }
--                  role  = "TANK" | "HEALER" | "MELEE" | "RANGED" | "DPS"
--    }
--
--  Notes:
--   * Slots are auto-filled IN ORDER, each raider used once across duty slots
--     (so list tanks before interrupts, etc.). Slots with no `need` are left for
--     you to fill by hand (good for free-form positions).
--   * `role` matching is best-effort from class (TBC has no role API), so it's a
--     starting point -- you override in the panel. `class` matching is exact.
--   * key must be unique across all encounters.
-- ===========================================================================

local _, ns = ...

ns.ENCOUNTERS = {

    -- ===============================================================
    --  Gruul's Lair -- High King Maulgar  (the classic "assignments" fight)
    -- ===============================================================
    {
        key = "Maulgar",
        label = "High King Maulgar",
        raid = "Gruul's Lair",
        slots = {
            { id = "maulgar",  label = "Tank -- Maulgar",                    need = { role = "TANK" } },
            { id = "krosh",    label = "Tank -- Krosh Firehand (Warlock)",   need = { class = "WARLOCK" } },
            { id = "olm",      label = "Tank -- Olm the Summoner",           need = { role = "TANK" } },
            { id = "blindeye", label = "Tank -- Blindeye the Seer",          need = { role = "TANK" } },
            { id = "kiggler",  label = "Kite/Tank -- Kiggler the Crazed",    need = { class = { "HUNTER", "MAGE" } } },
            { id = "intkig",   label = "Interrupt Kiggler",     count = 2,   need = { role = "MELEE" } },
            { id = "decurse",  label = "Decurse (Olm's Dark Decay)", count = 2, need = { class = { "MAGE", "DRUID" } } },
            { id = "healk",    label = "Heal the Krosh tank",   count = 2,   need = { role = "HEALER" } },
            { id = "pos",      label = "Position: spread for Blast Wave",    kind = "position" },
        },
    },
    {
        key = "Gruul", label = "Gruul the Dragonkiller", raid = "Gruul's Lair",
        slots = {
            { id = "maintank", label = "Tank -- Gruul (main)",                       need = { role = "TANK" } },
            { id = "offtank",  label = "Off-tank -- Hurtful Strike (stay in melee)", need = { role = "TANK" } },
            { id = "tankheal", label = "Heals -- the tanks", count = 3,              need = { role = "HEALER" } },
            { id = "pos",      label = "Position: SPREAD for Ground Slam / Shatter (no two players close)", kind = "position" },
        },
    },

    -- ===============================================================
    --  Magtheridon's Lair -- Magtheridon  (channeler tanks + cube clickers)
    -- ===============================================================
    {
        key = "Magtheridon", label = "Magtheridon", raid = "Magtheridon's Lair",
        slots = {
            { id = "chtanks", label = "P1 -- tank the 5 Hellfire Channelers", count = 5, need = { role = "TANK" } },
            { id = "chint",   label = "P1 -- interrupt Channeler Dark Mending", count = 5, need = { role = "DPS" } },
            { id = "magtank", label = "P2 -- tank Magtheridon", need = { role = "TANK" } },
            -- no `need` => left for you to assign by hand (deliberate per-cube picks)
            { id = "cubes",   label = "P2 -- Manticron Cube clickers (interrupt Blast Nova)", count = 5 },
            { id = "pos",     label = "Position: cube spots; spread for Quake/Debris; mind Cave-In", kind = "position" },
        },
    },

    -- ===============================================================
    --  Serpentshrine Cavern  (25-man; scaffolds -- refine as you go)
    -- ===============================================================
    {
        key = "Hydross", label = "Hydross the Unstable", raid = "Serpentshrine Cavern",
        slots = {
            { id = "nature", label = "Tank -- Nature side (pure)",     need = { role = "TANK" } },
            { id = "frost",  label = "Tank -- Frost side (corrupted)", need = { role = "TANK" } },
            { id = "dispel", label = "Dispel Water Tomb", count = 2, need = { class = { "PRIEST", "PALADIN", "DRUID", "SHAMAN" } } },
            { id = "pos",    label = "Position: drag Hydross across the line each transition; resist gear per side", kind = "position" },
        },
    },
    {
        key = "Lurker", label = "The Lurker Below", raid = "Serpentshrine Cavern",
        slots = {
            { id = "tank", label = "Tank -- The Lurker Below", need = { role = "TANK" } },
            { id = "adds", label = "P2 -- tank the Guardian / Ambusher adds", count = 2, need = { role = "TANK" } },
            { id = "pos",  label = "Position: jump in water for Spout; spread on platforms; mind Whirl knockback", kind = "position" },
        },
    },
    {
        key = "Leotheras", label = "Leotheras the Blind", raid = "Serpentshrine Cavern",
        slots = {
            { id = "tank", label = "Tank -- Leotheras (human phase)", need = { role = "TANK" } },
            { id = "pos",  label = "Position: spread fully for Demon Whirlwind; at 15% kill your OWN Inner Demon (Warlocks Banish theirs)", kind = "position" },
        },
    },

    -- ===============================================================
    --  Serpentshrine Cavern -- Fathom-Lord Karathress  (4 tanks + purge)
    -- ===============================================================
    {
        key = "Karathress",
        label = "Fathom-Lord Karathress",
        raid = "Serpentshrine Cavern",
        slots = {
            { id = "fl",       label = "Tank -- Fathom-Lord Karathress",    need = { role = "TANK" } },
            { id = "sharkkis", label = "Tank -- Fathom-Guard Sharkkis",     need = { role = "TANK" } },
            { id = "tidalvess",label = "Tank -- Fathom-Guard Tidalvess",    need = { role = "TANK" } },
            { id = "caribdis", label = "Tank -- Fathom-Guard Caribdis",     need = { role = "TANK" } },
            { id = "purge",    label = "Purge Tidalvess (totems/buffs)", count = 2, need = { class = "SHAMAN" } },
            { id = "tankheal", label = "Heals -- the 4 tanks",  count = 4,  need = { role = "HEALER" } },
            { id = "pos",      label = "Position: spread (Cataclysm / Tidal Surge)", kind = "position" },
        },
    },
    {
        key = "Morogrim", label = "Morogrim Tidewalker", raid = "Serpentshrine Cavern",
        slots = {
            { id = "tank",      label = "Tank -- Morogrim (face away for Tidal Wave)", need = { role = "TANK" } },
            { id = "murloctank",label = "Off-tank -- murloc waves", need = { role = "TANK" } },
            { id = "murlocaoe", label = "AoE down the murloc waves", count = 3, need = { role = "DPS" } },
            { id = "pos",       label = "Position: spread for Watery Grave; stay out of the front", kind = "position" },
        },
    },
    {
        key = "Vashj", label = "Lady Vashj", raid = "Serpentshrine Cavern",
        slots = {
            { id = "tank",     label = "Tank -- Lady Vashj (P1 & P3)", need = { role = "TANK" } },
            { id = "elites",   label = "P2 -- tank Coilfang Elites", count = 2, need = { role = "TANK" } },
            { id = "striders", label = "P2 -- kill/kite Coilfang Striders fast", count = 3, need = { role = "RANGED" } },
            -- no `need` => assign by hand (one trusted runner per generator)
            { id = "cores",    label = "P2 -- Tainted Core runners (relay to the 4 generators)", count = 4 },
            { id = "bats",     label = "P2 -- handle Toxic Spore Bats (ranged)", count = 2, need = { role = "RANGED" } },
            { id = "pos",      label = "Position: 4 generator stations; spread for Spore Bats; P1/P3 tank spot", kind = "position" },
        },
    },

    -- ===============================================================
    --  Tempest Keep -- The Eye  (scaffolds; refine slots as you go)
    -- ===============================================================
    {
        key = "Alar", label = "Al'ar", raid = "Tempest Keep",
        slots = {
            { id = "tank1",   label = "Tank -- Al'ar (Platforms 1 & 3)", need = { role = "TANK" } },
            { id = "tank2",   label = "Tank -- Al'ar (Platforms 2 & 4)", need = { role = "TANK" } },
            { id = "addtank", label = "Tank -- adds",                    need = { role = "TANK" } },
            { id = "embers",  label = "P2 -- kill Embers of Al'ar fast", count = 2, need = { role = "RANGED" } },
            { id = "dispel", label = "Dispel Melt Armor", count = 2, need = { class = { "PRIEST", "PALADIN", "DRUID", "SHAMAN" } } },
            { id = "pos",    label = "Position: P1 platform rotation; P2 spread for fire", kind = "position" },
        },
    },
    {
        key = "VoidReaver", label = "Void Reaver", raid = "Tempest Keep",
        slots = {
            { id = "tank", label = "Tank -- Void Reaver", need = { role = "TANK" } },
            { id = "pos",  label = "Position: spread evenly, dodge Arcane Orbs (no overlap)", kind = "position" },
        },
    },
    {
        key = "Solarian", label = "High Astromancer Solarian", raid = "Tempest Keep",
        slots = {
            { id = "tank", label = "Tank -- Solarian",                    need = { role = "TANK" } },
            { id = "adds", label = "Tank -- Solarium Agent / Priest adds", count = 2, need = { role = "TANK" } },
            { id = "pos",  label = "Position: run out 5yd for Wrath of the Astromancer (bomb)", kind = "position" },
        },
    },
    {
        key = "KaelThas", label = "Kael'thas Sunstrider", raid = "Tempest Keep",
        slots = {
            { id = "weapons",   label = "P2 -- weapon tanks / kill order",  count = 4, need = { role = "MELEE" } },
            { id = "thaladred", label = "P3 -- Tank Thaladred the Darkener", need = { role = "TANK" } },
            { id = "sanguinar", label = "P3 -- Tank Lord Sanguinar",         need = { role = "TANK" } },
            { id = "capernian", label = "P3 -- Handle Capernian (ranged)",   need = { class = { "HUNTER", "MAGE", "WARLOCK" } } },
            { id = "telonicus", label = "P3 -- Tank Telonicus",              need = { role = "TANK" } },
            { id = "pos",       label = "Position: P4 spread; P5 gravity lapse -- kill Phoenixes/eggs", kind = "position" },
        },
    },

    -- ===============================================================
    --  Karazhan  (10-man; scaffolds -- refine as you go)
    -- ===============================================================
    {
        key = "Attumen", label = "Attumen the Huntsman", raid = "Karazhan",
        slots = {
            { id = "midnight", label = "Tank -- Midnight (the horse)", need = { role = "TANK" } },
            { id = "attumen",  label = "Tank -- Attumen (after mount)", need = { role = "TANK" } },
            { id = "pos",      label = "Position: ranged spread; melee avoid the cleave", kind = "position" },
        },
    },
    {
        key = "Moroes", label = "Moroes", raid = "Karazhan",
        slots = {
            { id = "moroes",  label = "Tank -- Moroes", need = { role = "TANK" } },
            { id = "shackle", label = "Shackle add (undead)", need = { class = "PRIEST" } },
            { id = "sheep",   label = "Sheep add", need = { class = "MAGE" } },
            { id = "addtank", label = "Off-tank remaining adds", need = { role = "TANK" } },
            { id = "pos",     label = "Position: add kill order; mind Vanish + Garrote", kind = "position" },
        },
    },
    {
        key = "Maiden", label = "Maiden of Virtue", raid = "Karazhan",
        slots = {
            { id = "tank",   label = "Tank -- Maiden", need = { role = "TANK" } },
            { id = "dispel", label = "Dispel Holy Fire", count = 2, need = { class = { "PRIEST", "PALADIN", "DRUID", "SHAMAN" } } },
            { id = "pos",    label = "Position: spread 10yd; out of Consecration; mind Repentance stun", kind = "position" },
        },
    },
    {
        key = "Opera", label = "Opera Event", raid = "Karazhan",
        slots = {
            { id = "tank", label = "Tank -- boss (varies: Oz / Big Bad Wolf / Romulo & Julianne)", need = { role = "TANK" } },
            { id = "pos",  label = "Position: depends on the event that rolls", kind = "position" },
        },
    },
    {
        key = "Curator", label = "The Curator", raid = "Karazhan",
        slots = {
            { id = "tank",   label = "Tank -- The Curator", need = { role = "TANK" } },
            { id = "flares", label = "Kill Astral Flares immediately", count = 3, need = { role = "RANGED" } },
            { id = "pos",    label = "Position: spread for Arcane Bolt; burn during Evocation", kind = "position" },
        },
    },
    {
        key = "Aran", label = "Shade of Aran", raid = "Karazhan",
        slots = {
            { id = "elem",   label = "Off-tank / kill Water Elementals", need = { role = "TANK" } },
            { id = "decurse",label = "Decurse Chains of Ice", count = 2, need = { class = { "MAGE", "DRUID" } } },
            { id = "pos",    label = "Position: stack center; FLAME WREATH = DON'T MOVE; Blizzard = run", kind = "position" },
        },
    },
    {
        key = "Illhoof", label = "Terestian Illhoof", raid = "Karazhan",
        slots = {
            { id = "illhoof", label = "Tank -- Terestian Illhoof", need = { role = "TANK" } },
            { id = "kilrek",  label = "Tank -- Kil'rek (imp)", need = { role = "TANK" } },
            { id = "chains",  label = "Burn Demonic Chains / free Sacrifice", count = 2, need = { role = "DPS" } },
            { id = "pos",     label = "Position: spread; AoE the imps", kind = "position" },
        },
    },
    {
        key = "Netherspite", label = "Netherspite", raid = "Karazhan",
        slots = {
            { id = "red",   label = "Red beam (tank) rotation",   count = 2, need = { role = "TANK" } },
            { id = "green", label = "Green beam (healer) rotation", count = 2, need = { role = "HEALER" } },
            { id = "blue",  label = "Blue beam (dps) rotation",   count = 2, need = { role = "DPS" } },
            { id = "pos",   label = "Position: beam/portal management; banish-phase spots", kind = "position" },
        },
    },
    {
        key = "Prince", label = "Prince Malchezaar", raid = "Karazhan",
        slots = {
            { id = "tank", label = "Tank -- Prince Malchezaar", need = { role = "TANK" } },
            { id = "pos",  label = "Position: spread; avoid/kite Infernals (P2-P3)", kind = "position" },
        },
    },
    {
        key = "Nightbane", label = "Nightbane (optional)", raid = "Karazhan",
        slots = {
            { id = "tank",  label = "Tank -- Nightbane", need = { role = "TANK" } },
            { id = "bones", label = "P2 -- handle Restless Skeletons", count = 2, need = { role = "RANGED" } },
            { id = "pos",   label = "Position: mind Charred Earth; group up for Bellowing Roar fear", kind = "position" },
        },
    },

    -- ===============================================================
    --  Zul'Aman  (10-man; scaffolds -- refine as you go)
    -- ===============================================================
    {
        key = "Akilzon", label = "Akil'zon (Eagle)", raid = "Zul'Aman",
        slots = {
            { id = "tank",   label = "Tank -- Akil'zon", need = { role = "TANK" } },
            { id = "dispel", label = "Dispel Static Disruption", count = 2, need = { class = { "PRIEST", "PALADIN", "DRUID", "SHAMAN" } } },
            { id = "pos",    label = "Position: STACK tight on the group for Electrical Storm", kind = "position" },
        },
    },
    {
        key = "Nalorakk", label = "Nalorakk (Bear)", raid = "Zul'Aman",
        slots = {
            { id = "tank1", label = "Tank -- Nalorakk", need = { role = "TANK" } },
            { id = "tank2", label = "Off-tank -- swap on Brutal Swipe stacks", need = { role = "TANK" } },
            { id = "pos",   label = "Position: stack behind; tank swap ~3 stacks", kind = "position" },
        },
    },
    {
        key = "Janalai", label = "Jan'alai (Dragonhawk)", raid = "Zul'Aman",
        slots = {
            { id = "tank",     label = "Tank -- Jan'alai", need = { role = "TANK" } },
            { id = "hatchers", label = "Kill Hatchers / control egg hatching", count = 2, need = { role = "DPS" } },
            { id = "pos",      label = "Position: dodge Flame Breath; bomb spacing", kind = "position" },
        },
    },
    {
        key = "Halazzi", label = "Halazzi (Lynx)", raid = "Zul'Aman",
        slots = {
            { id = "tank",   label = "Tank -- Halazzi / Lynx Spirit", need = { role = "TANK" } },
            { id = "totems", label = "Kill Corrupted Lightning Totems", count = 2, need = { role = "DPS" } },
            { id = "pos",    label = "Position: spread; handle the split phase", kind = "position" },
        },
    },
    {
        key = "HexLord", label = "Hex Lord Malacrass", raid = "Zul'Aman",
        slots = {
            { id = "boss",    label = "Tank -- Hex Lord Malacrass", need = { role = "TANK" } },
            { id = "addtank", label = "Tank -- the gargoyle/add", need = { role = "TANK" } },
            { id = "cc",      label = "CC / kill order on the adds", count = 2, need = { role = "DPS" } },
            { id = "pos",     label = "Position: spread for Spirit Bolts; interrupt heals", kind = "position" },
        },
    },
    {
        key = "Zuljin", label = "Zul'jin", raid = "Zul'Aman",
        slots = {
            { id = "tank", label = "Tank -- Zul'jin", need = { role = "TANK" } },
            { id = "pos",  label = "Position: move per form (Bear/Eagle/Lynx/Dragonhawk phases)", kind = "position" },
        },
    },

    -- Add more encounters here (same shape). Example skeleton:
    -- {
    --     key = "Hydross", label = "Hydross the Unstable", raid = "Serpentshrine Cavern",
    --     slots = {
    --         { id = "nature", label = "Tank -- Nature side", need = { role = "TANK" } },
    --         { id = "frost",  label = "Tank -- Frost side",  need = { role = "TANK" } },
    --         { id = "pos",    label = "Position: drag across the line on each transition", kind = "position" },
    --     },
    -- },

}
