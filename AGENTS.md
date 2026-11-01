# AGENTS.md

## Project

This is a **Godot 4.7 / GDScript** project: a data-driven deckbuilder with
automatic 3x3 grid combat, designed around a **persistent open-world
campaign** (free world map exploration, a permanent card collection, and
multiple player-built decks chosen per combat). It is **not** a roguelike
with runs. Don't introduce run-based concepts. See `docs/ARCHITECTURE.md`'s
Game design direction section.

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
- Each faction has its own 3x3 grid; a unit occupies one cell (`lane`, `row`), `row = 0` is the Front. No formations, no push/compaction.
- Unit attack patterns, card targeting and trigger targeting are separate systems.
- Keep catalog (databases), campaign state (collection/decks/gold, planned) and battle state (`BattleState`, `Deck`, `Mana`) separate. The in-combat `Deck` is not the player's campaign deck list.
- Multi-floor (`Battlefield.floors`, `BattleDefinition.floors`) is unused legacy shape; only floor 0 exists in practice. Don't build on it.
- `Main` (`main.tscn`) is the main scene and owns the current screen; screens only emit signals and never change scenes themselves.

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

Unit attack patterns (`TargetSystem.get_pattern_attack_targets`), card
targeting (`TargetSystem.get_card_targets`) and trigger targeting
(`BattleState.resolve_trigger_targets`) are separate systems — see
`docs/ARCHITECTURE.md`'s Targeting architecture section for the current
patterns and target types. Avoid hardcoding faction-specific names like
`front_enemy`/`rear_enemy`/`selected_enemy` into any of them.

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

The single-combat sandbox is implemented and stable: 3x3 grid combat with
attack patterns, statuses, events/triggers, movement and buff cards,
deck/hand/discard/graveyard with mana cost, enemy waves, turn preview
(simulation) and animated turn replay, card art and SFX, plus debug
panels. `docs/playtest_3x3.md` and `docs/MECHANICS_EXECUTION_PLAN.md` are
both fully implemented. See `docs/ARCHITECTURE.md` for how it works, and
`git log` for the history.

The current phase is the **campaign layer**, planned in
`docs/CAMPAIGN_EXECUTION_PLAN.md` (raw overworld → collection → deck lists
→ merchants → deck builder → artifacts → events → save/load). Etapa 1
(raw overworld) is split into small passos (1.1 → 1.6). Passos 1.1 (main
menu + `Main` root scene), 1.2 (world map graph from JSON drawn on the
overworld), 1.3 (`CampaignState` + travel between connected points) and
1.4 (entering a combat point opens the battle, which returns to the map)
and 1.5 (visited/won point state, plus Esc menu behavior) are implemented.
Next is 1.6 (placeholder merchant/event points). Follow
the plan one passo/etapa at a time, and stop for the user to test in the
editor before the next. The plan lists open design questions to settle
with the user when each etapa comes up.

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
