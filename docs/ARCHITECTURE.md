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

## Directory Structure

```text
res://
├── data/
│   ├── cards/
│   ├── units/
│   └── battles/
├── scenes/
│   ├── card.tscn
│   ├── unit_view.tscn
│   └── battle_floor.tscn
├── scripts/
│   ├── card.gd
│   ├── card_data.gd
│   ├── card_database.gd
│   ├── unit.gd
│   ├── unit_data.gd
│   ├── unit_database.gd
│   ├── unit_view.gd
│   ├── battle_definition.gd
│   ├── battle_database.gd
│   ├── battle_state.gd
│   ├── battlefield.gd
│   ├── floor.gd
│   ├── battle_floor_view.gd
│   ├── effect_system.gd
│   ├── target_rule.gd
│   ├── target_system.gd
│   └── game_state.gd
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

The card target schema is still being refined; do not assume the current JSON format is final.

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

Only implemented shapes should be used.

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

`TargetSystem.get_card_targets(target_type, selected_unit)` is the single
resolver for targets that are Units. `selected_floor` is consumed by effects
that require a floor and is handled by the UI flow.

`selected_unit` means the Unit chosen by the UI. It does not encode a faction;
future card rules can validate the selected Unit without reintroducing names
such as `selected_enemy`.

## GameState

Current interaction concepts include:

```text
PLAYER_ACTION
TARGETING_UNIT
TARGETING_FLOOR
ENEMY_ACTION
```

The targeting state names are under review.

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

Next major combat feature: automatic Unit actions/turns.

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

Still to review:

- remaining `enemy` terminology
- final card target schema
- final `TargetSystem` organization
- attack API naming
- position/slot terminology
- stale `Enemy` references

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
