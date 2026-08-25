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

Card targeting is separate and may use concepts such as `selected_unit`, `selected_floor`, `all_enemies`, or `all_allies`. The final card target schema is still under design.

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

The project is currently in an architecture-cleanup phase:

1. Remove remaining inappropriate `Enemy` terminology.
2. Clean legacy selection/target names.
3. Separate Unit attack target rules from Card target rules.
4. Review `TargetSystem`.
5. Review targeting state names.
6. Update `docs/ARCHITECTURE.md`.
7. Resume new combat features only after cleanup is coherent.

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
