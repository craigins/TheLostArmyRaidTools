# Changelog

All notable changes to **PackMarker** are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/), and the project
aims to follow [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH).

> Versions before 3.0.0 predate this GitHub repo; their dates are approximate.

## [Unreleased]
- _Nothing yet._

## [3.0.0] - 2026-06-08
Major release: PackMarker grows from a trash-marking addon into a full raid-lead toolkit.

### Added
- **Boss assignment system.** New `Encounters.lua` templates and a dedicated **Boss
  Assignments** window (`/pmark boss`, the panel's *Boss Assigns* button, or right-click
  the minimap). Per-boss **duty/position slots**; pick a boss, **Auto-fill** from the live
  raid, override by hand (click a slot, then click raiders), then **Whisper All** /
  **Announce** / **Clear**. Saved per boss in `PackMarkerDB`.
- **Role-aware auto-fill.** Respects each player's actual role (`UnitGroupRolesAssigned`)
  and the raid **Main Tank** flag; exact `class` filters; only falls back to a class guess
  when a player has no role set. DPS no longer land in tank slots.
- **Tank/Healer role icons** next to roster names (both windows).
- **Bosses in the tree.** Each raid's bosses show as clickable red nodes under its trash
  sections; clicking one opens its assignments.
- **Test mode** (`/pmark test 10|25|off`) — a fake raid roster for solo testing;
  whispers/announces print locally as `[test]`. Auto-off on `/reload`.
- **Encounter scaffolds** (standard mechanics): Karazhan (all, 10-man), Gruul's Lair
  (Maulgar, Gruul), Magtheridon (channeler tanks + manual cube clickers), Serpentshrine
  Cavern (all 6), Tempest Keep (all 4), Zul'Aman (all, 10-man).

### Changed
- Interface version bumped to **20505** (TBC Classic / Anniversary).

## [2.1.0] - 2026-06
### Added
- **Expansion tier** on top of the browser: a collapsible **Expansion → Raid → Section →
  Pack** tree. Right-click a header to collapse/expand the whole tree.
- **Auto zone detection** — entering a known raid folds the tree to it (per-raid `zones`
  field; `/pmark zone` to re-run).
- **Mob ability/kill notes** (`MobInfo.lua`) shown on pack hover, in `/pmark name`, and via
  `/pmark info`.
- **Confirmation popup** before clearing all target assignments.
- Standardized the **mark convention** across packs (kill = Skull/X/Triangle/Square/Circle;
  poly = Moon/Star; banish = Diamond/Circle; Moon is strictly poly).
- Content: all TBC raids scaffolded; Tempest Keep and Serpentshrine Cavern trash packs.

## [2.0.0]
### Added
- **GUI control panel** (`/pmark gui`) and a draggable **minimap button**.
- **Multi-raid** organization of packs (raid -> pack hierarchy).

## [1.0.0]
### Added
- Initial release (by craigins): mouseover **trash auto-marking** with per-pack mark pools;
  **player -> icon assignments** with whisper / report / stash / restore; the `!assignment`
  self-service whisper. Marking is out-of-combat only.
