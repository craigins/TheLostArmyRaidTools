-- PackMarker -- PACK DATA
-- This is the only file you need to edit to add/change packs. The marking logic
-- lives in PackMarker.lua and reads the table defined here.
--
-- ===========================================================================
--  STRUCTURE  (expansion -> raid -> section -> pack -> group)
-- ===========================================================================
--  ns.EXPANSIONS is an ORDERED list of expansions (e.g. "Vanilla", "The Burning
--  Crusade"). Each expansion holds raids; a raid holds its packs either grouped
--  into SECTIONS (e.g. one per boss wing) or listed flat under raid.packs -- or
--  both. (Ordered = it shows up in the GUI / `/pmark list` in this order.)
--
--    expansion = { key=, label=, raids = { <raid>, ... } }
--    raid      = { key=, label=, zones={...}, sections = { <section>, ... } } -- grouped, OR
--    raid      = { key=, label=, zones={...}, packs    = { <pack>, ... } }    -- flat
--    section   = { label=, packs = { <pack>, <pack>, ... } }
--    pack      = { key=, label=, groups = { <group>, <group>, ... } }
--    group     = { names = { "Mob A", "Mob B" }, marks = { "SKULL", "CROSS" } }
--
--  A GROUP is a set of mob names sharing one ORDERED pool of marks. Put names that
--  must NOT collide in the SAME group so they draw different marks. The first
--  matching mob you hover gets the first mark in the pool, the next gets the second.
--
--  In the GUI, expansion / raid / section headers are all collapsible -- click one
--  to fold or unfold it.  `raid.zones` lists the in-game instance name(s) used for
--  auto zone-focus (falls back to matching raid.label if omitted).
--
--  FILLING IN PACKS:
--  The TBC raids below are scaffolded with one section per boss ("Pre-<Boss>") but
--  EMPTY packs -- the trash mob names must match in-game exactly, so add them as you
--  go: stand at a pull, hover a mob, run `/pmark name` to get its exact name + type,
--  then drop a pack into the right section. Example of a filled section is Tempest
--  Keep's "Pre-Void Reaver" / "Pre-Astromancer".
--
--  RULES
--   * Every `pack.key` must be UNIQUE across EVERYTHING (it's how `/pmark <key>`
--     and OPie slices target a pack). Labels can repeat; keys cannot.
--   * Keep every mark unique within a pack so two groups don't fight over an icon.
--   * Mob names must match in-game EXACTLY.
--
--  Valid mark names: STAR CIRCLE DIAMOND TRIANGLE MOON SQUARE CROSS (=X) SKULL
--     [1]=STAR  [2]=CIRCLE  [3]=DIAMOND  [4]=TRIANGLE
--     [5]=MOON  [6]=SQUARE  [7]=CROSS/X  [8]=SKULL

local _, ns = ...  -- shared addon namespace; the logic file reads ns.EXPANSIONS

-- Small helper: a list of empty "Pre-<Boss>" sections from a plain list of boss
-- names, so the scaffolding below stays readable. Add packs to a section later.
local function wings(...)
    local out = {}
    for _, boss in ipairs({ ... }) do
        out[#out + 1] = { label = "Pre-" .. boss, packs = {} }
    end
    return out
end

ns.EXPANSIONS = {

    -- #######################################################################
    --  THE BURNING CRUSADE
    -- #######################################################################
    {
        key = "TBC",
        label = "The Burning Crusade",
        raids = {

            -- ===============================================================
            --  KARAZHAN
            -- ===============================================================
            {
                key = "Karazhan",
                label = "Karazhan",
                zones = { "Karazhan" },
                sections = wings(
                    "Attumen the Huntsman",
                    "Moroes",
                    "Maiden of Virtue",
                    "Opera Event",
                    "The Curator",
                    "Shade of Aran",
                    "Terestian Illhoof",
                    "Netherspite",
                    "Prince Malchezaar",
                    "Nightbane"
                ),
            },

            -- ===============================================================
            --  GRUUL'S LAIR
            -- ===============================================================
            {
                key = "GruulsLair",
                label = "Gruul's Lair",
                zones = { "Gruul's Lair" },
                sections = wings(
                    "High King Maulgar",
                    "Gruul the Dragonkiller"
                ),
            },

            -- ===============================================================
            --  MAGTHERIDON'S LAIR
            -- ===============================================================
            {
                key = "MagtheridonsLair",
                label = "Magtheridon's Lair",
                zones = { "Magtheridon's Lair" },
                sections = wings(
                    "Magtheridon"
                ),
            },

            -- ===============================================================
            --  SERPENTSHRINE CAVERN
            -- ===============================================================
            {
                key = "SerpentshrineCavern",
                label = "Serpentshrine Cavern",
                zones = { "Serpentshrine Cavern" },
                sections = {
                    {
                        label = "Pre-Hydross the Unstable",
                        packs = {
                            -- Kill order: Hate-Screamers Skull/X (1st/2nd), Sporebats
                            -- Triangle/Square (3rd/4th), Beast-Tamer Circle (5th). The 4
                            -- non-CC icons are spent on kills 1-4, so a 5th kill borrows the
                            -- secondary-Banish icon (Circle). Moon is STRICTLY poly, never a kill.
                            {
                                key = "SSCHydross",
                                label = "Beast-Tamer Pack",
                                groups = {
                                    { names = { "Coilfang Hate-Screamer" }, marks = { "SKULL",    "CROSS"  } },
                                    { names = { "Serpentshrine Sporebat" }, marks = { "TRIANGLE", "SQUARE" } },
                                    { names = { "Coilfang Beast-Tamer" },   marks = { "CIRCLE" } },
                                },
                            },
                        },
                    },
                    {
                        label = "Pre-The Lurker Below",
                        -- The same pack is pulled ~6 times; this one definition covers them
                        -- all (re-select to reset the pool between pulls). Kill order:
                        -- Priestesses Skull/X, Shatterers Triangle/Square, Honor Guard Circle.
                        packs = {
                            {
                                key = "SSCLurker",
                                label = "Priestess Pack (x6 pulls)",
                                groups = {
                                    { names = { "Coilfang Priestess" },    marks = { "SKULL",    "CROSS"  } },
                                    { names = { "Coilfang Shatterer" },    marks = { "TRIANGLE", "SQUARE" } },
                                    { names = { "Vashj'ir Honor Guard" },  marks = { "CIRCLE" } },
                                },
                            },
                        },
                    },
                    {
                        label = "Pre-Leotheras the Blind",
                        packs = {
                            -- Pack 1: sheep the two Nether-Mages (Moon/Star); kill order is
                            -- Tidecaller (Skull) -> Skulker (X) -> Serpentguards (Triangle/Square).
                            {
                                key = "SSCLeotheras1",
                                label = "Nether-Mage Pack 1",
                                groups = {
                                    { names = { "Greyheart Nether-Mage" }, marks = { "MOON",     "STAR"   } },
                                    { names = { "Greyheart Tidecaller" },  marks = { "SKULL" } },
                                    { names = { "Greyheart Skulker" },     marks = { "CROSS" } },
                                    { names = { "Coilfang Serpentguard" }, marks = { "TRIANGLE", "SQUARE" } },
                                },
                            },
                            -- Cave entry: no CC called out, so straight kill order --
                            -- Fathom-Witches Skull/X (1st/2nd), Serpentguards Triangle/Square.
                            {
                                key = "SSCLeotheras2",
                                label = "Cave Entry Pack",
                                groups = {
                                    { names = { "Coilfang Fathom-Witch" }, marks = { "SKULL",    "CROSS"  } },
                                    { names = { "Coilfang Serpentguard" }, marks = { "TRIANGLE", "SQUARE" } },
                                },
                            },
                            -- Inside the cave: poly the Nether-Mage (Moon), Banish the Lurker
                            -- (Diamond); kill order Tidecallers Skull/X, Skulker 3rd, Shield-Bearer 4th.
                            {
                                key = "SSCLeotheras3",
                                label = "Cave Pack",
                                groups = {
                                    { names = { "Greyheart Nether-Mage" },    marks = { "MOON" } },
                                    { names = { "Serpentshrine Lurker" },     marks = { "DIAMOND" } },
                                    { names = { "Greyheart Tidecaller" },     marks = { "SKULL", "CROSS" } },
                                    { names = { "Greyheart Skulker" },        marks = { "TRIANGLE" } },
                                    { names = { "Greyheart Shield-Bearer" },  marks = { "SQUARE" } },
                                },
                            },
                        },
                    },
                    { label = "Pre-Fathom-Lord Karathress",  packs = {} },
                    { label = "Pre-Morogrim Tidewalker",     packs = {} },
                    { label = "Pre-Lady Vashj",              packs = {} },
                },
            },

            -- ===============================================================
            --  TEMPEST KEEP -- The Eye   (populated as the worked example)
            -- ===============================================================
            {
                key = "TempestKeep",
                label = "Tempest Keep",
                -- Auto zone-focus matches the instance name from GetInstanceInfo().
                -- The raid instance reports as "The Eye", so list it explicitly here.
                zones = { "The Eye", "Tempest Keep" },
                sections = {
                    {
                        label = "Pre-Al'ar",
                        packs = {
                            -- First-hallway "six-pack": Astromancer = Moon, Star Scryer = Star
                            -- (the CC/priority casters); Skull/X kill targets are the two
                            -- Vindicators; the two Legionnaires take Square/Triangle.
                            {
                                key = "Hallway",
                                label = "Hallway Six-Pack",
                                groups = {
                                    { names = { "Astromancer" },              marks = { "MOON" } },
                                    { names = { "Star Scryer" },              marks = { "STAR" } },
                                    { names = { "Bloodwarder Vindicator" },   marks = { "SKULL",  "CROSS"    } },
                                    { names = { "Bloodwarder Legionnaire" },  marks = { "SQUARE", "TRIANGLE" } },
                                },
                            },
                            -- Patrolling three-pack: Marshal whirlwinds (kite/run out), Squires
                            -- stun + heal. Marshal = Skull, the two Squires = X / Square.
                            {
                                key = "Marshal",
                                label = "Patrol (Marshal + Squires)",
                                groups = {
                                    { names = { "Bloodwarder Marshal" }, marks = { "SKULL" } },
                                    { names = { "Bloodwarder Squire" },  marks = { "CROSS", "SQUARE" } },
                                },
                            },
                            -- Al'ar's room, lower: Falconers shoot through walls -- kill first.
                            -- Hatchlings are paladin-AoE'd, so they're left unmarked on purpose.
                            {
                                key = "Falconers",
                                label = "Al'ar Room -- Falconers",
                                groups = {
                                    { names = { "Tempest Falconer" }, marks = { "SKULL", "CROSS" } },
                                },
                            },
                            -- Al'ar's room, upper: Phoenix Hawks (Dive + Mana Burn). Misdirection
                            -- pull, bait the Dive. Mark a simple kill order.
                            {
                                key = "PhoenixHawks",
                                label = "Al'ar Room -- Phoenix Hawks",
                                groups = {
                                    { names = { "Phoenix Hawk" }, marks = { "SKULL", "CROSS", "TRIANGLE" } },
                                },
                            },
                        },
                    },
                    {
                        label = "Pre-Void Reaver",
                        -- Role convention across these packs: Skull/X = primary kill (the
                        -- Sentinel if one is present, else the Devastator); Diamond/Circle =
                        -- Banish (Mechanics); Moon/Star = Sheep (Tempest-Smiths).
                        packs = {
                            -- Hallway, pull 1: a lone Devastator -- just kill it.
                            {
                                key = "VRDevastator",
                                label = "Hallway 1 -- Devastator",
                                groups = {
                                    { names = { "Crystalcore Devastator" }, marks = { "SKULL" } },
                                },
                            },
                            -- Hallway, pull 2: two Sentinels (Overcharge ~14-15k) -- kill order.
                            {
                                key = "VRSentinels",
                                label = "Hallway 2 -- Sentinels x2",
                                groups = {
                                    { names = { "Crystalcore Sentinel" }, marks = { "SKULL", "CROSS" } },
                                },
                            },
                            -- Room, roaming pack: 1 Devastator + 2 Smiths. Sheep the Smiths.
                            {
                                key = "VRRoaming",
                                label = "Room -- Roaming (1 Dev + 2 Smith)",
                                groups = {
                                    { names = { "Crystalcore Devastator" }, marks = { "SKULL" } },
                                    { names = { "Tempest-Smith" },          marks = { "MOON", "STAR" } },
                                },
                            },
                            -- Room, Mechanic packs (x2): 1 Devastator + 2 Mechanics + 1 Smith.
                            -- Banish the Mechanics, Sheep the Smith, kill the Devastator.
                            {
                                key = "VRMechanics",
                                label = "Room -- Mechanic Pack (1 Dev + 2 Mech + 1 Smith)",
                                groups = {
                                    { names = { "Crystalcore Devastator" }, marks = { "SKULL" } },
                                    { names = { "Crystalcore Mechanic" },   marks = { "DIAMOND", "CIRCLE" } },
                                    { names = { "Tempest-Smith" },          marks = { "MOON" } },
                                },
                            },
                            -- Room, Sentinel packs (x2): 2 Sentinels + 2 Mechanics + 1 Smith.
                            -- Sentinels die first; Banish Mechanics, Sheep the Smith.
                            {
                                key = "Crystalcore",
                                label = "Room -- Sentinel Pack (2 Sent + 2 Mech + 1 Smith)",
                                groups = {
                                    { names = { "Crystalcore Sentinel" }, marks = { "SKULL",  "CROSS"    } },
                                    { names = { "Crystalcore Mechanic" }, marks = { "DIAMOND", "CIRCLE" } },
                                    { names = { "Tempest-Smith" },        marks = { "MOON" } },
                                },
                            },
                        },
                    },
                    {
                        label = "Pre-Astromancer",
                        packs = {
                            {
                                key = "Vindicator",
                                label = "Bloodwarder Vindicator",
                                groups = {
                                    { names = { "Bloodwarder Legionnaire" },        marks = { "SQUARE", "TRIANGLE" } },
                                    { names = { "Bloodwarder Vindicator" },         marks = { "SKULL",  "CROSS"    } },
                                    { names = { "Astromancer", "Star Scryer" },     marks = { "MOON",   "STAR"     } },
                                },
                            },
                        },
                    },
                    {
                        label = "Pre-Kael'thas",
                        -- (no packs yet -- add the pre-Kael trash packs here)
                        packs = {},
                    },
                },
            },

            -- ===============================================================
            --  ZUL'AMAN
            -- ===============================================================
            {
                key = "ZulAman",
                label = "Zul'Aman",
                zones = { "Zul'Aman" },
                sections = wings(
                    "Akil'zon",
                    "Nalorakk",
                    "Jan'alai",
                    "Halazzi",
                    "Hex Lord Malacrass",
                    "Zul'jin"
                ),
            },

            -- ===============================================================
            --  THE BATTLE FOR MOUNT HYJAL  (instance: "Hyjal Summit")
            -- ===============================================================
            {
                key = "MountHyjal",
                label = "The Battle for Mount Hyjal",
                zones = { "Hyjal Summit", "The Battle for Mount Hyjal" },
                sections = wings(
                    "Rage Winterchill",
                    "Anetheron",
                    "Kaz'rogal",
                    "Azgalor",
                    "Archimonde"
                ),
            },

            -- ===============================================================
            --  BLACK TEMPLE
            -- ===============================================================
            {
                key = "BlackTemple",
                label = "Black Temple",
                zones = { "Black Temple" },
                sections = wings(
                    "High Warlord Naj'entus",
                    "Supremus",
                    "Shade of Akama",
                    "Teron Gorefiend",
                    "Gurtogg Bloodboil",
                    "Reliquary of Souls",
                    "Mother Shahraz",
                    "Illidari Council",
                    "Illidan Stormrage"
                ),
            },

            -- ===============================================================
            --  SUNWELL PLATEAU
            -- ===============================================================
            {
                key = "SunwellPlateau",
                label = "Sunwell Plateau",
                zones = { "Sunwell Plateau" },
                sections = wings(
                    "Kalecgos",
                    "Brutallus",
                    "Felmyst",
                    "Eredar Twins",
                    "M'uru",
                    "Kil'jaeden"
                ),
            },
        },
    },

    -- #######################################################################
    --  VANILLA  (example expansion -- fill in real packs or delete)
    -- #######################################################################
    {
        key = "Vanilla",
        label = "Vanilla",
        raids = {
            {
                key = "MoltenCore",
                label = "Molten Core (example)",
                zones = { "Molten Core" },
                sections = {
                    {
                        label = "Pre-Lucifron",
                        packs = {
                            {
                                key = "MC_Example",
                                label = "EXAMPLE -- Molten Giants",
                                groups = {
                                    { names = { "Molten Giant" },     marks = { "SKULL", "CROSS"  } },
                                    { names = { "Molten Destroyer" }, marks = { "MOON",  "SQUARE" } },
                                },
                            },
                        },
                    },
                },
            },
            {
                key = "BlackwingLair",
                label = "Blackwing Lair (example)",
                zones = { "Blackwing Lair" },
                -- (no packs yet -- add them here)
                packs = {},
            },
        },
    },

}
