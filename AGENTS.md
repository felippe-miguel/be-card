# AGENTS.md

## Project

This is a **Godot 4.7 / GDScript** project.

Read `docs/ARCHITECTURE.md` before architectural or structural changes — it
is the technical reference (data flow, class responsibilities, current
designs and the reasoning behind them). This file is about *how to work in
this repo*, not how the systems work internally.

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

## Architecture quick rules

- JSON is the content/data layer.
- `RefCounted` classes represent domain state and systems.
- Godot Nodes represent presentation and input.
- Domain code must not depend on UI Nodes.
- `UnitData` describes a unit type; `Unit` is a live instance and owns faction.
- `Pyre` is a separate battle entity, not a `Unit`.
- `position_index = 0` means the front of a formation.
- Visual orientation (which screen column a slot renders at) must not alter logical `position_index`.
- Unit attack targeting and card targeting are separate systems.

See `docs/ARCHITECTURE.md` for the full explanation of each of these.

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

## Data-driven content

Prefer JSON for configurable game content.

Do not put faction into `UnitData` unless the architecture is explicitly
changed — battle/spawn context determines whether a `Unit` instance is
`ALLY` or `ENEMY`.

## UI/domain separation

Gameplay code should receive domain objects such as:

```gdscript
var unit: Unit
```

rather than visual Nodes such as `UnitView`. `UnitView` represents a `Unit`
and emits the domain `Unit` when selected.

## Targeting

Unit attack targeting (`TargetRule.Shape`) and card targeting
(`TargetSystem.get_card_targets`) are separate systems — see
`docs/ARCHITECTURE.md`'s Targeting architecture section for the current
shapes and target types. Avoid hardcoding faction-specific names like
`front_enemy`/`rear_enemy`/`selected_enemy` into either.

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

Only commit when the user explicitly asks, after they've tested the change
in the editor. Implement the change, describe it, then wait — do not stage
or commit on your own initiative.

## Testing

After meaningful changes:

- run the relevant Godot scene;
- verify affected behavior;
- check typed GDScript declarations;
- check signals/connections;
- check scene/resource paths after renames;
- check Node paths after scene hierarchy changes.

## Current status

The combat/card loop is implemented and stable: automatic combat turns,
victory/defeat, deck/hand/discard with mana cost, automatic enemy spawning,
summon-to-a-specific-slot with live preview, unit-targeted effect preview,
and pending-card cancel/confirm. See `docs/ARCHITECTURE.md` for how each of
these actually works, and `git log` for the history of how they got there.

The project is now in a **gameplay-testing phase** — no specific feature is
queued. Wait for the user's direction each session rather than assuming the
next step.

Possible future directions, not decided or prioritized — ask the user
before picking one up:

- Pyre-targeting effects (cards/attacks currently only ever target `Unit`s).
- Per-battle deck composition (today every card in `CardDatabase` is the deck).
- Card type (`attack`/`skill`/`unit`) affecting `Deck` behavior.
- `TargetRule.Shape.RANDOM`/`SELECTED` for Unit attacks (declared, unimplemented).
- Turn order within/across floors beyond current formation order.

## General rule

Before structural changes:

1. Read `docs/ARCHITECTURE.md`.
2. Inspect the current repository files — do not blindly follow stale
   code or docs if they contradict what's actually there.
3. When renaming, search the whole repository for references (scripts,
   scenes, signals, resource paths) before changing anything.
4. Preserve domain/system/presentation separation.
5. Avoid leaving old and new abstractions active simultaneously.
6. Make the smallest coherent change; avoid large rewrites when a small
   refactor is sufficient.
7. Run/test the relevant Godot scene after meaningful changes (see Testing).
8. Update `docs/ARCHITECTURE.md` after important architectural decisions.

If the user's explicit request conflicts with `docs/ARCHITECTURE.md`, follow
the user's request, then update the document to reflect the new decision.
