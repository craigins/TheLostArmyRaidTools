-- PackMarker -- MOB INFO  (abilities / kill notes)
-- ===========================================================================
--  ns.MOBINFO[<exact mob name>] = { "line 1", "line 2", ... }
--
--  These lines show up in two places:
--    * the GUI: hover a pack in the left browser to see every mob in it, its
--      mark, and these notes.
--    * chat: `/pmark name` (hover/target a mob) and `/pmark info <name>`.
--
--  The KEY must be the exact in-game mob name -- the same string you use in
--  Packs.lua. Keep lines short; they're tooltip text. This file is data only;
--  add entries freely. Mobs with no entry simply show no notes.
-- ===========================================================================

local _, ns = ...

ns.MOBINFO = {

    -- ----- Tempest Keep: Pre-Al'ar -----
    ["Astromancer"] = {
        "Kill first -- priority caster.",
        "Molten Armor (self); Blast Wave + Firebolt Volley (both AoE).",
    },
    ["Star Scryer"] = {
        "Sheepable. Domination, Arcane Blast, Starfall.",
    },
    ["Bloodwarder Vindicator"] = {
        "Hammer of Justice stuns the tank -- dispel it or use a Free Action Potion.",
        "Dispels magic (breaks your CC). Flash of Light: unkickable, heals little.",
    },
    ["Bloodwarder Legionnaire"] = {
        "Whirlwind -- melee step out. Sheepable.",
    },
    ["Bloodwarder Marshal"] = {
        "Whirlwind, but channeled and stationary -- the tank just runs out.",
    },
    ["Bloodwarder Squire"] = {
        "Stuns + heals, similar to Vindicators.",
    },
    ["Tempest Falconer"] = {
        "Auto-shot + Fire Shield (self). Shoots through walls -- kill first.",
    },
    ["Phoenix Hawk Hatchling"] = {
        "Wing Buffet + an AoE silence. Paladin AoE-tanks these; mind the silence.",
    },
    ["Phoenix Hawk"] = {
        "Dive + Mana Burn. Misdirection pull; bait the Dive with one ranged.",
    },

    -- ----- Tempest Keep: Pre-Void Reaver -----
    ["Crystalcore Devastator"] = {
        "Countercharge (arcane autos, silences casters in melee) + Knockback.",
        "Tank it into a wall to limit the knockbacks.",
    },
    ["Crystalcore Sentinel"] = {
        "KILL FIRST. Overcharge hits the tank for ~14-15k arcane (Warriors can Spell Reflect).",
        "Charged Arcane Explosion + Trample -- both AoE on melee.",
    },
    ["Crystalcore Mechanic"] = {
        "Banish target.",
        "Saw Blade (random bleed); Recharge heals nearby Sentinels.",
    },
    ["Tempest-Smith"] = {
        "Sheep (or Mind Control for its Shell Shock).",
        "Frag Bomb (armor debuff); Shell Shock (AoE fire + stun); Power Up / Golem Repair buff/heal Sentinels.",
    },

    -- ----- Serpentshrine Cavern -----
    -- (add SSC mob notes here as you learn them, same format, e.g.:)
    -- ["Coilfang Hate-Screamer"] = { "..." },

}
