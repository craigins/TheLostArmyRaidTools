# PackMarker

Auto-marks trash packs on **mouseover**, **out of combat only**, by mob name.

You activate a *pack* (from the GUI, an OPie ring, or `/pmark <pack>`). While it's active,
hovering a mob whose name is in that pack assigns the next unused mark from its group's pool.
It never changes a mob that's already marked, and if a pool runs out it prints a warning
instead of stealing.

Packs are organized **by expansion → raid → section** (e.g. `The Burning Crusade → Tempest Keep
→ Pre-Void Reaver`) so it scales as you add more content. A full control-panel **GUI** (`/pmark
gui` or the minimap button) lets you browse the tree, watch each pack's mark pool fill up live,
and assign players to icons with one click.

## Install
Copy the `PackMarker` folder into your client's `Interface\AddOns\` folder (for the Anniversary
client that's `World of Warcraft\_anniversary_\Interface\AddOns\`), then restart the client.
You'll see `PackMarker: loaded.` in chat.

> Only **one person** should run it, and you must be **raid leader or assist** for marks to
> apply (it warns you if you're not).

## Commands
| Command | Does |
|---|---|
| `/pmark gui` | Open/close the marking control panel (also `/pmark show`, or left-click the minimap button) |
| `/pmark boss` | Open/close the boss-assignment window (also right-click the minimap button) |
| `/pmark test` | Toggle **test mode** (solo testing): roster becomes a fake raid; whispers/announces print locally as `[test]`. `/pmark test 10` or `25` picks the size, `/pmark test off` turns it off. Auto-off on `/reload` |
| `/pmark zone` | Fold the tree down to the raid you're currently standing in (manual auto-focus) |
| `/pmark <pack>` | Activate a pack (and reset its mark pools) |
| `/pmark off` | Stop marking |
| `/pmark reset` | Reset the active pack's pools (or just re-select the pack) |
| `/pmark clear` | Remove **all** raid markers in the world (including your own) |
| `/pmark list` | List packs |
| `/pmark name` | Print the hovered/target mob's **exact name + creature type** (use this to fill pack tables), plus any stored notes |
| `/pmark info` | Print a mob's ability/kill notes — hover/target a mob, or `/pmark info <name>` |
| `/pmark assign ...` | Assign players to icons (see below) |
| `/pmark` | Help + current status |

## The GUI
Open it with `/pmark gui` (or `/pmark show`), or click the **minimap button** (drag it around
the minimap edge to reposition; it remembers where you put it). The panel is movable (drag the
body) and closes with `Esc` or the X.

| Region | What it does |
|---|---|
| **Left — Raids / Packs** | A tree of **expansion → raid → section → pack** (sections are optional, e.g. one per boss wing). Click a **pack** to activate it (active one is marked `▶` and highlighted) — selecting a pack resets its pools, same as `/pmark <pack>`. **Hover a pack** to see a tooltip of its mobs, marks, and ability notes. Click any **header** to fold/unfold it (`▾`/`▸`); **right-click a header** to fold/unfold the whole tree. Collapsed state is remembered across `/reload`. |
| **Left — Active pack / mark pools** | Live view of the active pack's groups. Each mark shows **green** when it's still free and **grey** once it's placed in the world, so you can see at a glance what's left to mark. |
| **Right — Raid roster** | One row per player (class-colored). Click any of the 8 icon buttons to assign that player to that icon and whisper them. Click the highlighted icon again — or the red ✕ — to clear. |
| **Bottom buttons** | `Stop` / `Reset Pool` / `Clear Marks` (marking), and `Report` / `Remind` / `Stash` / `Restore` / `Clear Asn` (assignments) — the same actions as the slash commands. `Clear Asn` asks for confirmation first (no undo), so a mid-raid misclick won't wipe everyone's assignment. |

The panel and slash commands share one engine, so changes made either way stay in sync while
it's open. Roster, class colors, and pool status update automatically as people join/leave and
as marks go out.

### Auto zone detection
The **Auto-zone** checkbox (top-right of the panel, on by default) folds the tree for you. When
you enter a known raid instance, every *other* expansion and raid collapses, the one you're in
unfolds, and the list scrolls to it — so you're looking at just the relevant packs. It only fires
when the instance actually **changes**, so it never undoes folding you did by hand mid-raid, and
the fold is a normal (persisted) collapse so you can still expand anything afterwards. `/pmark
zone` re-runs it on demand.

Detection matches the instance name from the game against each raid's `label`, or an explicit
`zones = { ... }` list on the raid (see below) for instances whose internal name differs from the
label — e.g. Tempest Keep's raid reports as *"The Eye"*.

## Target assignments
Assign raid members to icons and whisper them their job. The GUI roster is the fast way; the
slash commands below do the same and work without opening the panel. Assignments persist across
`/reload` (saved in `PackMarkerDB`). The whisper shows the actual icon, e.g.
*"Your target is {skull}"* renders with the Skull icon.

| Command | Does |
|---|---|
| `/pmark assign <icon>` | Assign your **current target** to an icon (`1`–`8` or a name like `skull`/`moon`/`x`) and whisper them |
| `/pmark assign remove <name>` | Remove a player's assignment by name — works even if they've left the raid. Omit the name to remove your current target's |
| `/pmark assign show` | Print who is assigned to what (to you only) |
| `/pmark assign remind` | Re-whisper every assigned player their icon |
| `/pmark assign report` | Announce all assignments to **raid** chat (or **party** if not in a raid), grouped by icon |
| `/pmark assign stash` | Save the current assignments aside (one slot) and clear them |
| `/pmark assign restore` | Bring the stashed assignments back (replacing current) |
| `/pmark assign clear` | Remove all assignments |

**Stash/restore** is one slot, persisted across `/reload`. Use it to swap assignment sets:
set CC for trash → `stash` → set kick/interrupt assignments for the boss → after the boss,
`restore` to get your CC assignments back. Restoring replaces whatever's current and empties
the stash.

Example: target the mage and `/pmark assign moon`, target the warlock and `/pmark assign skull`,
then `/pmark assign report` to post the list to chat, and `/pmark assign remind` right before
the pull to re-whisper everyone.

### Self-service: the `!assignment` whisper
For raiders who can't remember their assignment, they can **whisper you** (the person running
PackMarker) a message starting with `!assignment`, and the addon auto-replies:
- If they have an assignment → their icon (e.g. *"Your target is {moon} Moon. Go get 'em!"*).
- If they don't → a friendly "you're off the hook" message.

Replies are picked at random from a few variants to keep it lively, and throttled to one
reply per player every 5 seconds so it can't be spammed.

## Future considerations
- **Auto-prune assignments** when a player leaves the raid (drop their assignment automatically
  on `GROUP_ROSTER_UPDATE`). Tabled for now — would likely be an opt-in toggle, since transient
  roster flicker (e.g. a brief disconnect) could otherwise remove a valid assignment. Use
  `/pmark assign remove <name>` manually in the meantime.

## How marking works
- Hover a mob → if it matches a name in the active pack, it gets the next free mark from
  that name's **group pool**.
- Names in the **same group** share a pool, so they get *different* marks. Example: Devastator
  + Sentinel are one group with `{SKULL, CROSS}`, so the first you hover gets Skull, the
  second gets X — never two Skulls.
- Already-marked mobs are skipped (so it won't overwrite a CC mark someone else placed).
- "In use" is detected live from your target, mouseover, and **nameplates** — so turn enemy
  nameplates on (default `V`) for the most reliable pool tracking.

## Files
- `Packs.lua` — **the main data file you edit to add/change raids & packs**.
- `MobInfo.lua` — optional per-mob ability/kill notes (`ns.MOBINFO`), shown in tooltips & `/pmark info`.
- `Encounters.lua` — boss-assignment templates (`ns.ENCOUNTERS`): the duty/position slots per boss.
- `PackMarker.lua` — the marking engine + assignment logic + slash commands.
- `GUI.lua` — the marking control panel and minimap button.
- `BossAssign.lua` — the boss-assignment window (auto-fill, whisper, announce).
- `PackMarker.toc` — load order: `Packs`, `MobInfo`, `Encounters`, `PackMarker`, `GUI`, `BossAssign`.
- `CHANGELOG.md` — version history.

## Adding / editing expansions, raids & packs
Edit the `ns.EXPANSIONS` table in `Packs.lua`. The tree is **expansion → raid → section → pack**.
A raid holds its packs either grouped into **sections** (e.g. one per boss wing) or listed flat
under `packs` — or both. Everything appears in the GUI / `/pmark list` in the order you write it.

```lua
ns.EXPANSIONS = {
    {
        key = "TBC", label = "The Burning Crusade",
        raids = {
            {
                key = "TempestKeep", label = "Tempest Keep",
                sections = {                              -- grouped by wing (collapsible in the GUI)
                    {
                        label = "Pre-Void Reaver",
                        packs = {
                            {
                                key = "VoidReaver", label = "Void Reaver Pack",
                                groups = {
                                    { names = { "Some Demon" },    marks = { "SQUARE", "TRIANGLE" } },
                                    { names = { "Some Humanoid" }, marks = { "MOON",   "DIAMOND"  } },
                                },
                            },
                            -- more packs in this wing...
                        },
                    },
                    -- more sections...
                },
            },
            {
                key = "Karazhan", label = "Karazhan",
                packs = {                                 -- flat: a raid can skip sections entirely
                    { key = "KaraServants", label = "Servants", groups = { --[[ ... ]] } },
                },
            },
        },
    },
    -- more expansions (Vanilla, etc.)...
}
```

A section with `packs = {}` (or a raid with no packs) still shows its header in the tree, so you
can lay out your expansions/wings first and fill in the packs later.

Rules:
- Every `pack.key` must be **unique across everything** (it's how `/pmark <key>` and OPie target
  a pack). The addon warns in chat on a duplicate key.
- Names must match in-game **exactly** — use `/pmark name` while hovering to confirm.
- Valid marks: `STAR CIRCLE DIAMOND TRIANGLE MOON SQUARE CROSS` (=X) `SKULL`. Keep each mark
  unique within a pack.

**Auto-zone matching:** by default a raid is detected by its `label`. If the in-game instance
name differs, add a `zones` list to the raid so detection still works:

```lua
{ key = "TempestKeep", label = "Tempest Keep", zones = { "The Eye", "Tempest Keep" }, sections = { ... } },
```

The shipped file scaffolds **all of The Burning Crusade** — Karazhan, Gruul's Lair, Magtheridon's
Lair, Serpentshrine Cavern, Tempest Keep, Zul'Aman, Mount Hyjal, Black Temple, Sunwell Plateau —
each with one **empty section per boss** (`Pre-<Boss>`) and the correct `zones` for auto-focus.
Tempest Keep is filled in as a worked example (the real `Crystalcore`/`Vindicator` packs); the
rest are waiting for you to drop packs into the right wing as you confirm mob names with `/pmark
name`. A small **Vanilla** expansion (Molten Core / Blackwing Lair) is included as a second-
expansion example — fill in or delete.

> On first load every raid starts **collapsed** (you see expansion → raid headers); expand the
> ones you want, or just walk into an instance and let auto-zone open it for you.

## Mob notes (abilities / kill tips)
Store per-mob ability and kill notes in `MobInfo.lua`, keyed by the **exact mob name**:

```lua
ns.MOBINFO = {
    ["Crystalcore Sentinel"] = {
        "KILL FIRST. Overcharge hits the tank ~14-15k arcane (Warriors can Spell Reflect).",
        "Charged Arcane Explosion + Trample -- both AoE on melee.",
    },
    -- ...
}
```

These show up when you **hover a pack** in the GUI (each mob, its mark, and its notes) and in
`/pmark name` / `/pmark info`. A mob with no entry simply shows no notes — add them whenever. You
can also give a **pack** an optional one-line `note = "..."` field; it appears at the bottom of
that pack's hover tooltip.

## Boss assignments
A separate window (`/pmark boss`, the **Boss Assigns** button on the panel, or right-click the
minimap) handles **per-boss duty & position assignments** that adapt to who's in the raid. Bosses
also appear **in the marking-panel tree** — under each raid, below its trash sections, as red
crossed-swords rows; click one to jump straight to its assignments. (Any encounter in
`Encounters.lua` whose `raid` matches the raid's label/key shows up automatically.)

Each boss is a template in `Encounters.lua` made of **slots** — a duty (tank X, interrupt, decurse,
heal) or a position (named text like "spread for Blast Wave"). A slot can declare what it needs
(`need = { class = "WARLOCK" }` or `need = { role = "TANK" }`).

In the window: pick a boss (left), and either hit **Auto-fill** (fills every slot with a `need`
from the current raid, each raider used once) or click a **slot** (middle) then click **raiders**
(right) to set it by hand. Then:
- **Auto-fill** — fills from the live roster. It **respects each player's actual role** — the role
  they set (`UnitGroupRolesAssigned`) or the raid **Main Tank** flag — so DPS don't land in tank
  slots. Only when a player hasn't set a role does it fall back to a class-capability guess. `class`
  filters are always exact. Tank/Healer players also get a **role icon** next to their name in the
  roster (both windows).
- **Whisper All** — privately whispers each assigned raider their job(s) for this boss.
- **Announce** — posts the slot → players list to raid/party chat.
- **Clear** — wipes this boss's assignments.

Assignments are saved per boss in `PackMarkerDB`, so they persist across `/reload`.

```lua
-- Encounters.lua
{
    key = "Karathress", label = "Fathom-Lord Karathress", raid = "Serpentshrine Cavern",
    slots = {
        { id = "fl",    label = "Tank -- Karathress",        need = { role = "TANK" } },
        { id = "purge", label = "Purge Tidalvess", count = 2, need = { class = "SHAMAN" } },
        { id = "pos",   label = "Position: spread", kind = "position" },   -- no need => manual
    },
},
```

Shipped with **High King Maulgar** and **Fathom-Lord Karathress** as worked examples; add your own
in `Encounters.lua` (same shape). *Note:* delivery is whisper + chat + the panel; an on-screen
per-raider reminder (everyone runs the addon) is a possible future add.

## OPie integration
PackMarker is driven entirely by `/pmark`, so OPie just needs macro slices:

1. Make a WoW macro per pack, e.g. one named **Crystalcore** with body:
   ```
   /pmark Crystalcore
   ```
   Add more for each pack, plus optionally **MarkOff** (`/pmark off`).
2. `/opie` → create a custom ring (e.g. "Marking") → add each macro as a slice → bind the
   ring to a key.
3. In the raid: open the ring, click the pack you're standing at, hover the mobs. At the
   next pull, click that pack (or the next one) again — selecting a pack resets its pools,
   so you don't need a separate reset slice.

## Versioning & releases
The current version is shown in `PackMarker.toc` (`## Version:`), on login, and via `/pmark
version`. We follow [Semantic Versioning](https://semver.org/) — MAJOR.MINOR.PATCH — and keep a
[CHANGELOG.md](CHANGELOG.md).

To cut a release:
1. Bump `## Version:` in `PackMarker.toc`.
2. Add a dated entry at the top of `CHANGELOG.md` under a new version heading (move items out of
   `[Unreleased]`).
3. Commit, then push to GitHub (and tag the release, e.g. `git tag v3.0.0`).

Pushes are intentional/manual — nothing is auto-pushed on edit.
