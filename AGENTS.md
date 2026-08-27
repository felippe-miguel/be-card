# AGENTS.md

## Project

This is a **Godot / GDScript** project.

Read `docs/ARCHITECTURE.md` before architectural or structural changes.

## Mandatory GDScript formatting

**All GDScript indentation MUST use TAB characters. Never use spaces for indentation.**

Do not:
- convert tabs to spaces;
- mix tabs and spaces for indentation;
- use four spaces instead of a tab.

Correct:

```gdscript
func take_damage(amount: int) -> void:
	if amount <= 0:
		return

	hp -= amount

	if hp < 0:
		hp = 0

	changed.emit()
```

Incorrect:

```gdscript
func take_damage(amount: int) -> void:
    if amount <= 0:
        return
```

This applies to every `.gd` file, including new files.

## Architecture

- JSON is the content/data layer.
- `RefCounted` classes represent domain state and systems.
- Godot Nodes represent presentation and input.
- Domain code must not depend on UI Nodes.
- `UnitData` describes a unit type.
- `Unit` represents a live instance and owns faction.
- `Pyre` is a separate battle entity, not a `Unit`.
- `UnitView` represents either an ally or enemy visually.
- `position_index = 0` means the front of a formation.
- Visual orientation must not alter logical positions.
- Unit attack targeting is relative to the attacker and normally targets the opposite faction.
- Card targeting and Unit attack targeting are separate systems.

## Naming

If an object can represent either faction, use generic terminology.

Prefer:

```text
Unit
UnitView
unit_selected
selected_unit
create_unit_view()
setup_units()
```

Avoid:

```text
Enemy
EnemyView
enemy_selected
selected_enemy
create_enemy_view()
setup_enemies()
```

When renaming, search the whole repository and update scripts, scenes, signals, resource references, and call sites.

## Data-driven content

Prefer JSON for configurable game content.

Do not put faction into `UnitData` unless the architecture is explicitly changed.

Battle/spawn context determines whether a Unit instance is `ALLY` or `ENEMY`.

## UI/domain separation

Gameplay code should receive domain objects such as:

```gdscript
var unit: Unit
```

rather than visual Nodes such as `UnitView`.

`UnitView` represents a Unit and emits the domain Unit when selected.

## Targeting

Unit attacks use shapes such as:

```text
FRONT
REAR
ALL
RANDOM
SELECTED
```

The attacker's faction determines the opposing faction.

Avoid hardcoding `front_enemy` / `rear_enemy` into generic Unit attack rules.

Card targeting is separate and may use concepts such as `selected_unit`, `selected_floor`, `all_enemies`, or `all_allies`. Use optional `target_faction` values of `ally` or `enemy` to restrict `selected_unit` without creating faction-specific target names.

## Incremental workflow

The user prefers development one logical step at a time.

For each change:

1. Make the smallest coherent change.
2. Run/test the relevant Godot scene.
3. Confirm behavior before proceeding.

Avoid large rewrites when a small refactor is sufficient.

## Commits

Use Conventional Commits written in Portuguese:

```text
tipo(escopo): descrição curta no imperativo
```

Use a scope when it helps identify the affected system, for example:

```text
refactor(targeting): unifica resolução de alvos de carta
fix(combate): remove unidade derrotada da formação
feat(cartas): adiciona efeito de invocação
```

Do not add `Co-authored-by` trailers unless the user explicitly requests one.

## Current priority

The architecture-cleanup phase is done for now. Focus is back on features.

Resolved in the last review pass:

1. No remaining inappropriate `Enemy` terminology found (`enemies[]`,
   `EnemyContainer` are legitimate per-faction collections, not violations).
2. Legacy selection/target names are clean.
3. Unit attack target rules (`TargetRule.Shape`) and Card target rules
   (`TargetSystem.get_card_targets`) are separate.
4. `TargetSystem` reviewed: `EffectSystem` now reuses `BattleState.target_system`
   instead of creating a second instance.
5. Targeting/game state names reviewed; see `docs/ARCHITECTURE.md` for the one
   open naming question left (`PLAYER_ACTION`/`ENEMY_ACTION` vs `Unit.Faction`).
6. `docs/ARCHITECTURE.md` updated.

Intentionally kept, not dead code — reserved for upcoming features, do not
prune without discussion:

- `GameState.State.TARGETING_POSITION` — reserved for future
  position-targeting effects.
- `TargetRule.Shape.RANDOM` / `SELECTED` — declared, not yet implemented in
  `TargetSystem.get_attack_targets()`.

Resolved: automatic Unit turns. `GameState.State.ENEMY_ACTION` was renamed to
`COMBAT_PHASE` — during this phase every living Unit (ally and enemy) attacks
once, not just enemies, resolving the `PLAYER_ACTION`/`ENEMY_ACTION` vs
`Unit.Faction` naming mismatch. Triggered by an explicit "Encerrar turno"
button (`Game._on_end_turn_pressed()`), which calls
`BattleState.execute_combat_phase()`.

Resolved: battle victory/defeat. `BattleState.is_victory()`/`is_defeat()`
check unit counts per faction across all floors (Pyre not included yet).
`Game.check_battle_result()` runs after every card and after the combat
phase; on end it moves `GameState` to the new `BATTLE_OVER` state and shows
`ResultLabel`.

Resolved: deck/hand/discard. New `Deck` (owned by `Game`) holds
`draw_pile`/`hand`/`discard_pile` of `CardData`. 5 cards drawn at battle
start, 2 per turn, reshuffles discard into draw pile when it empties. Cards
are discarded once their effect resolves in `Game.execute_card()`.
`CardPileView` shows pile counts only — no card-type distinction yet (all
cards share one deck/discard pile, per explicit user decision). Card count
in `data/cards/` grew from 5 to 15 example cards. See
`docs/ARCHITECTURE.md` for the full flow.

Resolved: hand size limit and hand layout. `Deck.MAX_HAND_SIZE = 7`; drawing
beyond that is a no-op (card stays in the draw pile). `Game`'s `Cards` node
is a plain `Control` (not `HBoxContainer`), manually laid out by
`Game.layout_hand()`: cards fan out left-to-right and overlap once the hand
doesn't fit `HAND_AREA_WIDTH`. Resting z-index is fixed and left-to-right
(`Card.set_hand_position()`, rightmost on top); hover raises a card to
`Card.HOVERED_Z_INDEX` only while the mouse is over it, then it drops back
to its own resting z-index on mouse-exit. (A "last-hovered card stays on
top permanently" variant was tried and reverted per user feedback — felt
arbitrary rather than a predictable fan.) `Card` also got a bordered/
shadowed `Panel` background (`StyleBoxFlat`) so overlapping cards are
readable, plus a hover border highlight. `CostLabel` moved from the
top-right to the top-left corner of the card, since the left edge is the
part that stays visible even when a card is overlapped by the one to its
right.

Resolved: mana cost validation. New `Mana` (owned by `Game`): `current`/
`max_mana`, refilled to `max_mana` every turn (no carryover), spent when a
card resolves in `Game.execute_card()`. `Game._on_card_played()` blocks
playing a card it can't afford before any targeting state starts. Cards show
unaffordable cost in red (`Card.set_affordable()`). `STARTING_MANA = 3` is a
tunable default, not a fixed design decision — revisit if it feels wrong in
play.

Resolved: automatic enemy spawning. New `EnemySpawner` (owned by `Game`):
for the first `MAX_SPAWN_TURNS` turns (3), spawns one random enemy per
floor with room, from a fixed `ENEMY_POOL` (excludes `dragon` — reserved as
boss-tier, not a random early spawn). `Game.current_turn` tracks the turn
number; `Game.spawn_enemies_if_needed()` runs the wave (via a new
`GameState.State.SPAWN_PHASE`) once at battle start and once at the end of
every `_on_end_turn_pressed()`, before returning to `PLAYER_ACTION`.
`test_battle.json` no longer pre-places enemies — only the player's
starting `ally` units remain, per explicit user decision, since removing
allies too would make `BattleState.is_defeat()` fire immediately (see
`docs/ARCHITECTURE.md`). Added 5 new unit types for spawn variety: goblin,
wolf (Lobo), bat (Morcego), troll, bandit (Bandido).

Next: no feature decided yet — candidates include Pyre-targeting effects,
per-battle deck composition (vs. today's "every card in CardDatabase is the
deck"), or card type distinctions (attack/skill/unit) affecting Deck
behavior. Ask the user before picking one.

## Testing

After meaningful changes:

- run the relevant Godot scene;
- verify affected behavior;
- check typed GDScript declarations;
- check signals/connections;
- check scene/resource paths after renames;
- check Node paths after scene hierarchy changes.

## General rule

Do not blindly follow stale code if it contradicts `docs/ARCHITECTURE.md`.

Inspect the current repository first, then make the smallest change consistent with the architecture and the user's request.
