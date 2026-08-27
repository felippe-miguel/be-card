# Gamejam — Architecture & AI Context

## Purpose

Primary architectural context for AI coding agents working on this Godot project.

The project is a data-driven deckbuilder structurally inspired by Monster Train and Slay the Spire. The initial goal is a flexible combat engine; game-specific rules and identity will evolve later.

Preserve these architectural decisions unless the user explicitly asks to change them.

## Architecture

Separate the project into:

1. **Data / Content** — JSON definitions for cards, units, battles, and future content.
2. **Domain / Game State** — `RefCounted` classes representing actual game state.
3. **Systems / Logic** — effects, targeting, turns, and other rules.
4. **Presentation** — Godot Nodes/Controls representing state and receiving input.

Flow:

```text
JSON
 ↓
Data classes
 ↓
Game State
 ↓
Systems
 ↓
Visual Nodes
```

Domain code must not depend on UI Nodes.

## Node vs RefCounted

Use Nodes for SceneTree/presentation/input:

- `Card` → `Control`
- `UnitView` → `Button`
- `BattleFloorView` → `PanelContainer`

Use `RefCounted` for data, state, and systems:

- `CardData`, `CardDatabase`
- `Unit`, `UnitData`, `UnitDatabase`
- `Pyre`
- `BattleDefinition`, `BattleDatabase`, `BattleState`
- `Battlefield`, `BattleFloor`
- `EffectSystem`, `TargetSystem`, `GameState`, `TargetRule`
- `CombatMath` (shared damage/block resolution used by `Unit` and `Pyre`)
- `Deck` (draw pile / hand / discard pile of `CardData`)

## Directory Structure

```text
res://
├── data/
│   ├── cards/
│   ├── units/
│   └── battles/
├── scenes/
│   ├── card.tscn
│   ├── card_pile_view.tscn
│   ├── unit_view.tscn
│   └── battle_floor.tscn
├── scripts/
│   ├── card.gd
│   ├── card_data.gd
│   ├── card_database.gd
│   ├── card_pile_view.gd
│   ├── deck.gd
│   ├── unit.gd
│   ├── unit_data.gd
│   ├── unit_database.gd
│   ├── unit_view.gd
│   ├── battle_definition.gd
│   ├── battle_database.gd
│   ├── battle_state.gd
│   ├── battlefield.gd
│   ├── battle_floor.gd
│   ├── battle_floor_view.gd
│   ├── effect_system.gd
│   ├── target_rule.gd
│   ├── target_system.gd
│   ├── combat_math.gd
│   ├── pyre.gd
│   ├── game_state.gd
│   └── game.gd
└── docs/
    └── ARCHITECTURE.md
```

The exact list may evolve; preserve responsibilities rather than filenames.

## Data-driven design

JSON is the content layer. Code is the engine.

Current data:

```text
data/
├── cards/
├── units/
└── battles/
```

Future data may reference assets such as artwork, particles, animations, audio, and VFX.

Avoid hardcoding content-specific behavior into generic systems.

## Cards and Effects

Flow:

```text
card.json
 ↓
CardDatabase
 ↓
CardData
 ↓
Card (visual)
```

`EffectSystem` interprets card effects such as:

- `damage`
- `block`
- `heal`
- `summon`

Effects modify game state, not UI Nodes.

`EffectSystem` reuses `BattleState.target_system` rather than creating its own
`TargetSystem` instance — there should only ever be one `TargetSystem` per
`BattleState`.

The card target schema is still being refined; do not assume the current JSON format is final.

## Deck, hand and discard

`Deck` is a `RefCounted` owned directly by `Game` (not by `BattleState` —
it is a meta-game concept, not battle/floor state). It holds three
`Array[CardData]`:

```text
draw_pile
hand
discard_pile
```

Flow:

```text
CardDatabase.cards (all CardData)
 ↓
Deck._init() — copies into draw_pile, shuffles
 ↓
Deck.draw(amount) — moves cards from draw_pile into hand
 ↓
Game.render_hand() — rebuilds Card visual nodes from deck.hand
 ↓
player plays a Card
 ↓
Game.execute_card() resolves the effect(s), then Deck.discard(card.data)
 ↓
Deck.discard_pile
```

`Deck.draw()` reshuffles `discard_pile` back into `draw_pile` when the draw
pile runs out (`reshuffle_discard_into_draw_pile()`), so play can continue
indefinitely instead of stalling once the draw pile is empty.

Current rules (see `Game._ready()` / `Game._on_end_turn_pressed()`):

- 5 cards drawn at battle start (`STARTING_HAND_SIZE`).
- 2 cards drawn at the start of each turn, right after `COMBAT_PHASE`
  returns to `PLAYER_ACTION` (`CARDS_DRAWN_PER_TURN`).
- Every card currently in `CardDatabase` is a single copy in the deck —
  there is no per-battle deck list/composition yet, and no duplicate
  copies of a card.

`Deck` does not distinguish `CardData.type` (`attack`/`skill`/`unit`) —
every card is drawn from the same pile and discarded to the same pile.
Type-based deck rules (e.g. separate piles, deck-building/composition
screens) are a future feature, not implemented.

`CardPileView` (`Control`, `res://scenes/card_pile_view.tscn`) is a
generic visual for a pile: it only shows a title and a card count, no
individual cards. `Game` owns two instances, `DeckPileView` and
`DiscardPileView`, updated whenever `Deck.changed` fires.

## Units

`UnitData` describes a unit type. `Unit` is a live instance.

```text
UnitData
 ↓
"what is a Skeleton?"
 ↓
Unit #1 — ALLY
Unit #2 — ENEMY
```

The same `UnitData` can create either faction.

A Unit conceptually contains:

```text
id
name
faction
floor_index
position_index
hp
max_hp
attack
block
```

Faction belongs to `Unit`, NOT `UnitData`.

```gdscript
enum Faction {
	ALLY,
	ENEMY
}
```

Do not put faction into unit JSON definitions unless explicitly changing this architecture.

`BattleState.create_unit()` is the central Unit creation path.

## Pyre

`Pyre` is a separate battle entity. It has its own health and block, but is
not a `Unit`: it has no faction, floor, position, or attack targeting.

`BattleState` owns the Pyre. Cards currently target Units only; future effects
that affect the Pyre must use a distinct target type.

`Unit` and `Pyre` both resolve block absorption through
`CombatMath.apply_block()` to avoid duplicating that math in two places.
`Unit.is_dead()` and `Pyre.is_destroyed()` are deliberately named
differently — a `Pyre` is not a `Unit` and does not "die" the same way.
Do not unify them into a shared interface without an explicit decision to do so.

## Unit signals

`Unit` currently exposes:

```gdscript
signal changed
```

State changes emit this signal.

`BattleFloor` listens to the signal of each Unit in its formations. When a Unit
reaches 0 HP, the floor removes it, compacts the formation, and emits
`unit_removed`.

```text
Unit.take_damage()
 ↓
changed.emit()
 ↓
UnitView
 ↓
update_display()
```

The domain model must not reference `UnitView`.

## UnitView

The old generic visual class `Enemy` was renamed to `UnitView`.

`UnitView` can represent either faction:

```text
UnitView
 └── Unit
      ├── ALLY
      └── ENEMY
```

Never use `Enemy` as a generic visual/domain name.

Prefer:

- `Unit`
- `UnitView`
- `create_unit_view()`
- `setup_units()`
- `unit_selected`
- `selected_unit`

Avoid:

- `Enemy`
- `EnemyView`
- `create_enemy_view()`
- `setup_enemies()`
- `enemy_selected`
- `selected_enemy`

## UI selection

The UI communicates domain objects, not visual Nodes:

```text
UnitView
 ↓
selected(Unit)
 ↓
BattleFloorView
 ↓
unit_selected(Unit)
 ↓
Game
```

The gameplay layer decides whether the selected Unit is a valid target.

## Battlefield and floors

```text
BattleState
└── Battlefield
    ├── Floor 0
    ├── Floor 1
    └── Floor 2
```

Each `BattleFloor` has two independent formations:

```text
BattleFloor
├── allies[]
└── enemies[]
```

`position_index = 0` always means the logical **front** of that faction.

Visual orientation is different:

```text
Enemies: [0] [1] [2] [3]
          ↑ front

Allies:  [3] [2] [1] [0]
                      ↑ front
```

Do not change logical indexes to compensate for visual orientation.

## Positioning

Current `add_unit()` behavior:

```text
add_unit()
 ↓
find_first_free_position()
 ↓
first free slot
```

Normal summons do not insert into the middle.

After removal, `reorder_units()` compacts the remaining formation.

Future operations may include:

- `add_unit_at(position)`
- `insert_unit_at(position)`
- `move_unit(from, to)`
- push/pull/reposition mechanics

Not implemented yet.

## BattleFloor signals

```gdscript
signal unit_added(unit: Unit)
signal unit_removed(unit: Unit)
```

Summon flow:

```text
EffectSystem
 ↓
BattleFloor.add_unit()
 ↓
unit_added.emit()
 ↓
BattleFloorView
 ↓
create_unit_view()
 ↓
UnitView
```

## BattleFloorView

Current visual structure:

```text
BattleFloorView
└── HBoxContainer
	├── AllyContainer
	└── EnemyContainer
```

Both contain `UnitView` instances.

When `unit_removed` is emitted, `BattleFloorView` removes the matching view
and restores visual order from each Unit's logical `position_index`.

## Battle definitions

Battles are data-driven. Faction is assigned per instance by the battle definition:

```json
{
  "floors": [
    {
      "units": [
        {
          "id": "slime",
          "faction": "enemy"
        },
        {
          "id": "skeleton",
          "faction": "ally"
        }
      ]
    }
  ]
}
```

Flow:

```text
battle.json
 ↓
BattleDatabase
 ↓
BattleDefinition
 ↓
BattleState
 ↓
Battlefield
```

## Summoning

Current flow:

```text
Card
 ↓
summon effect
 ↓
TARGETING_FLOOR
 ↓
player selects floor
 ↓
BattleState.create_unit()
 ↓
Faction.ALLY
 ↓
BattleFloor.add_unit()
 ↓
unit_added
 ↓
UnitView
```

Default summon uses first free slot.

## Targeting architecture

Unit attack targeting and card targeting are separate concepts.

### Unit attacks

Use a shape/rule:

```text
FRONT
REAR
ALL
RANDOM
SELECTED
```

For normal attacks, the target faction is the **opposite faction of the attacker**.

Avoid names such as `front_enemy` or `rear_enemy` for attack rules.

Flow:

```text
Unit
 ↓
attack shape
 ↓
TargetSystem
 ↓
opposite faction
 ↓
same floor
 ↓
targets
```

`TargetRule` currently has:

```gdscript
enum Shape {
	FRONT,
	REAR,
	ALL,
	RANDOM,
	SELECTED
}
```

Only implemented shapes should be used. `RANDOM` and `SELECTED` are
intentionally declared but not yet implemented in
`TargetSystem.get_attack_targets()` — they are reserved for future attack
rules, not dead code to prune.

`TargetSystem` conceptually exposes:

```gdscript
get_attack_targets(attacker, shape)
```

It determines opposite faction and limits the search to the attacker's floor.

### Card targeting

Cards may need:

```text
selected_unit
selected_floor
all_enemies
all_allies
...
```

`TargetSystem.get_card_targets(target_type, selected_unit, target_faction)` is
the single resolver for targets that are Units. `selected_floor` is consumed by
effects that require a floor and is handled by the UI flow.

`selected_unit` means the Unit chosen by the UI. Use the optional
`target_faction` field to limit it to `ally` or `enemy`, without reintroducing
names such as `selected_enemy`.

## GameState

Current interaction concepts include:

```text
PLAYER_ACTION
TARGETING_UNIT
TARGETING_FLOOR
TARGETING_POSITION
COMBAT_PHASE
```

`TARGETING_POSITION` is declared but not yet driven by any flow — reserved
for future position-targeting effects, not dead code.

`ENEMY_ACTION` was renamed to `COMBAT_PHASE`: the phase runs every living
Unit's automatic attack, ally and enemy alike (see Combat below), not just
enemy Units, so a faction-specific name no longer described it. This also
resolves the previous `PLAYER_ACTION` / `ENEMY_ACTION` vs `Unit.Faction`
naming mismatch — `COMBAT_PHASE` does not imply a faction at all.

Important distinction:

```text
UI event:
	"a Unit was selected"

Game state:
	"the game is asking for a Unit target"
```


## Combat

Current intended flow:

```text
BattleState
 ↓
TargetSystem.get_attack_targets(attacker, shape)
 ↓
target
 ↓
Unit.attack(target)
 ↓
target.take_damage()
```

A Unit should not search the battlefield to choose its own target.

`BattleState.execute_unit_attack(unit)` implements that flow for a single
Unit. `BattleState.execute_combat_phase()` drives the automatic-turn feature:
it walks every `BattleFloor`, snapshots that floor's Units via
`get_units()` (so mid-phase deaths/removals don't affect the iteration), and
calls `execute_unit_attack()` for each living Unit — ally and enemy alike.

Trigger: an explicit "Encerrar turno" button in `game.tscn`
(`Game._on_end_turn_pressed()`), only while `GameState.current` is
`PLAYER_ACTION`. It transitions to `COMBAT_PHASE`, runs
`BattleState.execute_combat_phase()`, then transitions back to
`PLAYER_ACTION`. The phase currently resolves synchronously (no per-attack
animation/pacing yet — combat feedback is still `print()`-based, consistent
with `UnitView`'s current debug-first display).

Not yet implemented: turn order within/across floors beyond
`BattleFloor.get_units()` order (allies then enemies, each in
`position_index` order), and any battle victory/defeat condition — combat
can currently run to "all Units on one side dead" with no end-of-battle
detection.

## Design direction

The combat is structurally inspired by Monster Train:

- multiple floors
- ally/enemy formations
- front/rear positions
- automatic unit attacks
- cards
- summons
- targeted effects
- future movement/advancement
- future Pyre damage rules

Do not blindly copy Monster Train. The final game will have its own mechanics.

## Debugging

During development, `UnitView` displays:

```text
Unit name
Faction
HP / Max HP
ATK
Block
Floor
Position
```

Keep this while the combat model is being developed.

## Current refactoring status

Completed:

- `Enemy` visual → `UnitView`
- `enemy_selected` → `unit_selected`
- UI selection now passes `Unit`, not the visual Node
- Unit attack targeting uses `TargetRule.Shape`
- Unit attack targeting determines opposite faction from attacker
- Unit attack targeting is restricted to attacker's floor
- Battle creation does not execute test attacks
- Pyre is separate from Unit; current cards target Units only
- Defeated Units leave their formation and their views are removed
- Generic visual `Enemy` nomenclature removed
- Card effects restrict selected Units with `target_faction`
- `EffectSystem` reuses `BattleState.target_system` instead of creating a
  second `TargetSystem` instance
- `Unit` and `Pyre` share block-absorption math via `CombatMath`
- `UnitView` derives its faction label from `Unit.Faction.keys()` instead of
  duplicating the enum as strings
- `BattleDefinition.floors` and `CardData.effects` are typed `Array[Dictionary]`,
  consistent with the rest of the typed collections in the domain layer
- Automatic Unit turns: `GameState.State.ENEMY_ACTION` renamed to
  `COMBAT_PHASE`; `BattleState.execute_combat_phase()` runs every living
  Unit's attack (ally and enemy) each phase; triggered by an explicit
  "Encerrar turno" button, resolving the `PLAYER_ACTION`/`ENEMY_ACTION` vs
  `Unit.Faction` naming mismatch

Still to review:

- final card target schema
- final `TargetSystem` organization
- attack API naming
- position/slot terminology
- `TargetRule.Shape.RANDOM` / `SELECTED` still not implemented in
  `TargetSystem.get_attack_targets()`
- `GameState.State.TARGETING_POSITION` still not driven by any flow
- battle victory/defeat condition — not implemented yet
- turn order within/across floors beyond current formation order

## AI agent rules

Before structural changes:

1. Read this document.
2. Inspect the current repository files.
3. Search all references to concepts being renamed.
4. Preserve domain/system/presentation separation.
5. Avoid leaving old and new abstractions active simultaneously.
6. Make small, testable changes.
7. Run/test the relevant Godot scene after meaningful changes.
8. Update this document after important architectural decisions.

If this document conflicts with the user's explicit request, follow the user's request and then update the document to reflect the new decision.
