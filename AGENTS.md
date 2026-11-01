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

Content language: player-facing text is Portuguese, but mechanic terms
stay in English using the exact glossary names from `data/keywords/`
(Strength, Poison, Block, On Hit...). Card and unit names stay as authored;
ids are always English. Unit `attack`/`max_hp` in JSON are player-scale
(enemies are halved in combat).

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
(raw overworld, passos 1.1 → 1.6) is implemented: main menu, `Main` root
scene, world map graph from JSON, `CampaignState` + travel, entering combat
points (battle returns to the map), visited/won point state, Esc behavior,
and placeholder merchant/event points. Etapa 2 (card collection in
`CampaignState`, starting collection from
`data/campaign/starting_collection.json`, raw "Coleção" panel on the
overworld) is implemented. Etapa 3 (`DeckList`s from
`data/campaign/starting_decks.json`, active deck chosen on the overworld,
battle `Deck` built from it with one `CardData` instance per copy) is
implemented. Etapa 4 (gold from combat points, half on repeats; card
merchant screen with fixed infinite stock from `data/merchants/`) is
implemented. Etapa 5 (DeckBuilder screen opened from the overworld deck
panel: create/edit/rename/delete decks on a working copy) is implemented.
Etapa 6 (artifacts as a per-deck collectible, max 1 per deck; generic
`Merchant` screen selling cards and/or artifacts) is implemented. Etapa 7
(events from `data/events/`, unique or repeatable, choices with
gold/card/artifact/battle effects) and Etapa 8 (autosave of `CampaignState`
ids to `user://campaign_save.json`, tolerant load, Continuar/Nova campanha
in the main menu) are implemented; Etapa 9 is the user's integration
playtest. Follow the plan one passo/etapa at a time, and stop for the user
to test in the editor before the next. The plan lists open design questions
to settle with the user when each etapa comes up.

`docs/MERCHANT_CARDS_EXECUTION_PLAN.md` is implemented: the merchant and
the DeckBuilder show real `Card`/`ArtifactCard` grids, cards and artifacts
have keyword tooltips (glossary in `data/keywords/`, derived from effects)
and colored highlighting in descriptions, and unit stats are at player
scale (`ENEMY_STAT_DIVISOR` halves enemies).

In parallel, `docs/CARDS_EXECUTION_PLAN.md` adds cards for 4 deck
archetypes: Passos 1–4 are implemented (new spells, `on_card_played`
combo units with the `card_type: spell` condition, and the new effects
`double_status`, `detonate_poison`, `shield_bash`, `raise_dead`).

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
