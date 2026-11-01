# BeCard — Architecture & AI Context

## Purpose

Primary architectural context for AI coding agents working on this Godot
project. It describes what the code actually does **today** and the
reasoning behind it. Trust the code over this file if they ever disagree,
then fix this file.

Preserve these architectural decisions unless the user explicitly asks to
change them.

## Game design direction

BeCard is a data-driven deckbuilder with automatic grid combat, built
around a **persistent campaign in an open world**, not roguelike runs:

- The player freely explores a **world map** with points of interest:
  combat encounters, card merchants, artifact merchants, events, etc.
  Movement is free (any connected point, in any direction, revisiting is
  allowed). There is no forced forward path.
- Cards are **collected** permanently over the campaign (bought, earned),
  up to the complete collection of every card in the game.
- The player builds **multiple decks** from the cards they own and picks
  which deck to bring into each combat. The campaign deck list (what you
  built) is separate from the in-combat `Deck` (draw/hand/discard).
- Progress (collection, decks, gold, artifacts, explored map) is permanent
  and must eventually be saved to disk.

The earlier direction (Monster Train/Slay the Spire-style runs: one deck
grown along a branching path and lost at the end of the run) was
**dropped**. Do not introduce run-based concepts (`RunState`, "end of
run", "run deck", run-scoped relics).

The roadmap lives in `docs/CAMPAIGN_EXECUTION_PLAN.md`. Its Etapa 1
(raw overworld) has started: the game opens on a main menu, and "Jogar"
leads to an overworld that draws the world map graph from JSON, where
the player travels between connected points (see Scene flow and Overworld
below). Entering a combat point opens the battle, and the battle
returns to the map when it ends.

## Architecture layers

1. **Data / Content**: JSON definitions for cards, units, battles, and
   future content (encounters, world map, merchants, artifacts, events).
2. **Domain / Game State**: `RefCounted` classes representing actual game
   state.
3. **Systems / Logic**: effects, targeting, triggers, turns, and other
   rules.
4. **Presentation**: Godot Nodes/Controls representing state and receiving
   input.

```text
JSON → Data classes → Game State → Systems → Visual Nodes
```

Domain code must not depend on UI Nodes.

### Three scopes of state

Keep these clearly separated, especially once the campaign layer exists:

- **Catalog** (`CardDatabase`, `UnitDatabase`, `BattleDatabase`,
  `WorldMapData`, future artifact databases): everything that exists in the game. Loaded
  once and never mutated.
- **Campaign state** (`CampaignState`): what is specific to this player
  and survives the whole campaign. Today it holds the current map point,
  visited points and won combats. Planned: collection as
  `card_id -> copies`, saved deck lists, gold, artifacts. Store ids, not catalog objects, so it serializes
  cleanly to a save file.
- **Battle state** (`BattleState`, `Battlefield`, `BattleFloor`, `Unit`,
  plus `Deck`/`Mana` owned by `Game`): exists only during one combat.

## Node vs RefCounted

Nodes (presentation/input):

- `Main` (`Node`, `main.tscn`): the project's main scene. Owns the current
  screen (see Scene flow).
- `MainMenu` (`Control`, `main_menu.tscn`), `Overworld` (`Control`,
  `overworld.tscn`): screens instantiated by `Main`.
- `Game` (`Control`, `game.tscn`): the battle scene. It orchestrates one
  combat plus the debug sandbox UI. Opened by `Main` from a combat point,
  or directly in the editor (F6) as a standalone sandbox.
- `BattleFloorView` (`PanelContainer`, `battle_floor.tscn`)
- `UnitView` (`Button`, `unit_view.tscn`)
- `Card` (`Control`, `card.tscn`)
- `CardPileView` (`Control`, `card_pile_view.tscn`)
- `SfxPlayer` (`sfx_player.tscn`), plus `SfxSheet` (`Resource`, `.tres`
  files under `resources/audio/sfx/`)

`RefCounted` (data, state, systems):

- `CardData`, `CardDatabase`
- `UnitData`, `UnitDatabase`, `Unit`
- `BattleDefinition`, `BattleDatabase`, `BattleState`
- `Battlefield`, `BattleFloor`
- `EffectSystem`, `TargetSystem`
- `CombatMath` (shared block-absorption math)
- `Deck` (in-combat draw pile / hand / discard / graveyard)
- `Mana`
- `WorldMapData`, `WorldPointData` (overworld graph catalog)
- `CampaignState`

## Directory structure

```text
res://
├── data/
│   ├── cards/     (24 cards)
│   ├── units/     (38 unit types)
│   ├── battles/   (test_battle.json)
│   └── world/     (overworld.json)
├── resources/
│   ├── audio/     (music, sfx + SfxSheet .tres)
│   └── images/    (cards/<card_id>.png art, frames)
├── scenes/        (main, main_menu, overworld, game, battle_floor, unit_view, card, card_pile_view, sfx_player)
├── scripts/
└── docs/
    ├── ARCHITECTURE.md              (this file)
    ├── CAMPAIGN_EXECUTION_PLAN.md   (next phase: campaign/world map/collection)
    ├── MECHANICS_EXECUTION_PLAN.md  (completed: status/triggers/etc.)
    └── playtest_3x3.md              (completed: original 3x3 sandbox spec)
```

The exact list may evolve; preserve responsibilities rather than filenames.

## Data-driven design

JSON is the content layer. Code is the engine. Avoid hardcoding
content-specific behavior into generic systems.

Card art is resolved by convention, `res://resources/images/cards/<card_id>.png`
(`Card.ART_PATH_FORMAT`). A card without art simply shows none.

## Scene flow

```text
Main (main.tscn, run/main_scene)
 ├── MainMenu   — "Jogar" → Overworld, "Sair" → quit
 ├── Overworld  — world map; enter current combat point → Game,
 │                "Voltar ao menu"/Esc → MainMenu
 └── Game       — battle; battle_finished(victory) → Overworld
```

`Main` holds exactly one screen at a time (`current_screen`,
`switch_to()` frees the previous one with `queue_free()`, since the switch
usually happens inside a signal emitted by that very screen). Screens never
change scenes themselves. They only emit signals (`play_pressed`,
`quit_pressed`, `back_to_menu_pressed`), and `Main` decides what comes
next. `Main` also owns the `CampaignState` (a fresh one on every "Jogar",
since there's no save/continue yet), with no global autoload. `Main` only passes the battle a `battle_id` (`Game.setup_battle()`), not
the whole `CampaignState`. The battle reports back through
`battle_finished(victory)`. `Main` records it on the current point
(`CampaignState.record_current_combat_result()`) and returns to the
overworld at the same point.

## Overworld

`data/world/overworld.json` defines the world map as a graph:
`start_point`, `points` (`id`, `name`, `type`, `position` in screen
pixels), and `connections` (undirected `[id_a, id_b]` pairs, always
traversable both ways). `WorldMapData.load_from_file()` parses it into
`WorldPointData`s. Duplicate or missing point ids and connections that
reference unknown points are skipped with a console warning instead of
breaking the map. There is a single map, so there's no multi-map database.

`Main` loads the map once and hands it, plus the `CampaignState`, to each
new `Overworld` via `setup()` before it enters the tree. `Overworld.render_map()` adds one
`Line2D` per connection, then one `Button` per point (in that order, so
buttons draw on top of line ends) to `MapCanvas`. Each button is centered
on its point **after** entering the tree (`reset_size()`), because its
real size depends on the theme font and the two-line text. Point types so
far are `camp` (neutral) and `combat`.

Movement: `CampaignState.current_point_id` starts at the map's
`start_point`. `CampaignState.can_travel_to()`/`travel_to()` own the rule
(any point connected to the current one, via `WorldMapData.are_connected()`,
never the current point itself) and emit `changed`. `Overworld` only
reflects it in `refresh_points()`: the current point is highlighted (★ +
color) and stays enabled (Passo 1.4 will use it to enter the point),
neighbors are enabled (click = travel), and everything else is disabled.
Travel is instant.

Point state: `CampaignState.visited_point_ids` (the start point plus every
point traveled to) and `won_combat_point_ids` (sets as `id -> true`). A won
combat stays **repeatable** (user decision): it only gets a "✔" marker, and
a later defeat doesn't unmark it. Visited points (other than the current
one) get a bluish tint. Repeat rewards will be decided once gold exists.

Esc on the overworld (`_unhandled_input`) goes back to the main menu, same
as "Voltar ao menu".

Entering: arriving at a point never enters it (you can pass through a
combat point without fighting). Clicking the **current** point emits
`point_entered(point_id)` if `WorldPointData.can_enter()` (today: `combat`
with a `battle` id, shown with a "— entrar" hint). `Main` opens the battle
for `combat` points.

This is a deliberately raw clickable-graph map (no camera, scroll or art).
If the map later becomes a free-walking character map, only this
presentation should change, not the graph data or campaign state.

## Current battle flow

`Game._ready()` loads the three databases, starts the battle for
`battle_id` (`get_battle_definition()` → `start_new_battle_state()`), builds
the `Deck`/`Mana` (`setup_deck_and_mana()`), and sets up the debug panels.

- From the campaign: `Main` calls `Game.setup_battle(battle_id)` before
  adding it to the tree, which also sets `in_campaign = true`.
- Opened directly (F6): `battle_id` stays `DEFAULT_BATTLE_ID`
  (`test_battle`). An unknown id also falls back to it with a console
  warning.

"Resetar combate" restarts the same `battle_id`. "Random" still replaces it
with a random field (debug).

Turn loop ("Rodar turno", `Game._on_run_turn_button_pressed()`):

1. The player plays cards from hand (mana cost, targeting, see below).
2. "Rodar turno" resolves the whole turn instantly in the domain
   (`BattleState.execute_full_turn()`), then `Game.play_turn_replay()`
   replays it visually with pacing (see Turn replay).
3. Turn counter advances, `Mana.refill()`, `Deck.discard_hand()`, a new
   hand of `STARTING_HAND_SIZE` (5) is drawn.
4. While `enemy_waves_spawned < MAX_ENEMY_WAVES` (4), a wave of
   `ENEMIES_PER_WAVE` (3) random enemies spawns into empty cells.

`Game.check_battle_end()` runs reactively on every
`BattleFloor.battlefield_changed`: defeat = no allies left (any time),
victory = no enemies left **after** all waves have spawned. Either one
goes through `end_battle()`, which sets `game_over`/`battle_won` and locks
"Rodar turno" until "Resetar combate"/"Random".

Campaign-only controls (hidden unless `in_campaign`): "Voltar ao mapa"
(`ReturnToMapButton`, shown after the battle ends, emits
`battle_finished(battle_won)`) and "Fugir pro mapa" in the menu
(`FleeButton`, emits `battle_finished(false)`, so fleeing counts as a
defeat). The battle never switches screens itself.

Battle menu: a centered modal (`MenuOverlay` → full-screen `Dim` +
`CenterContainer` + panel with Continuar / Fugir pro mapa / Sair do Jogo),
opened by the "Menu" button or Esc (`toggle_menu()`). The `Dim` blocks all
clicks to the board and hand while it's open, so no extra "paused" state is
needed. `MenuOverlay.z_index = 1000` because hand cards draw with their own
`z_index` (hand index, `Card.HOVERED_Z_INDEX = 100` on hover) and would
otherwise render over the modal. Input was already blocked by tree order;
only drawing was wrong.

The wave loop, `MAX_ENEMY_WAVES`/`ENEMIES_PER_WAVE`, and
`BattleState.ALLY_STAT_MULTIPLIER = 2` (allies spawn with double ATK/HP)
are temporary sandbox tuning, not settled design. They should become
per-encounter data once the campaign layer exists.

### Debug sandbox

`game.tscn` deliberately keeps two ways to do the same things:

- **Debug panels** (free, no cost): spawn any unit into any cell of either
  grid (`SpawnSidebar`), action buttons (Atacar, Remover, Reposicionar,
  Flanquear, Avançar, Recuar, Troca, Linha de Frente, Concentração,
  Teleporte), "Resetar combate", "Random" (empty grid + random units per
  faction), and a "preview" checkbox for the turn preview.
- **Real cards** (Deck/Mana/hand, with cost and discard).

A movement/buff card arms the **same** `Game.PendingAction` the equivalent
debug button would, with `pending_card` attached. These debug tools stay
as development tools. They are not part of the future campaign flow.

## Battlefield: the 3x3 grid

```text
BattleState
└── Battlefield
    └── BattleFloor (index 0, the only floor actually used)
        ├── allies[]   (flat Array[Unit], LANES*ROWS, null = empty cell)
        └── enemies[]
```

Each faction has its own 3x3 grid. `BattleFloor.LANES = 3`, `ROWS = 3`;
`row` 0 = Front, 1 = Middle, 2 = Back (`BattleFloor.Row`). A unit occupies
exactly one cell (`Unit.lane`, `Unit.row`, -1/-1 when not placed).
`BattleFloor.cell_index(lane, row)` is the flat index, static so views use
the same formula.

There is no formation, push, or compaction: an empty cell stays empty
until something fills it on purpose.

- `place_unit_at(unit, lane, row)`: fails if the cell is invalid or
  occupied.
- `add_unit(unit)`: first empty cell (row by row, lane by lane). Fallback
  when the caller offers no cell choice.
- `move_unit(unit, lane, row)`, `swap_units(a, b)` (same faction only).
- `remove_unit(unit)`. Units are also removed reactively when they die
  (`_on_unit_changed()` → `is_dead()`).
- Queries: `get_unit_at`, `get_lane_units` (Front→Back),
  `get_units_for_faction`, `get_adjacent_units` (orthogonal, same
  faction), `adjacent_lanes(lane)`.

Signals: `unit_added(unit)`, `unit_removed(unit, old_lane, old_row)`,
`unit_moved(unit, old_lane, old_row)`, and `battlefield_changed`, a
catch-all for any position or stat change on the floor (used by the turn
preview and `check_battle_end()`).

`Battlefield` still supports multiple floors and `BattleDefinition` still
has a `floors` array, but everything (`TargetSystem.get_battle_floor()`,
`EffectSystem`, `Game.get_main_floor()`, the aura/trigger wiring in
`BattleState._init()`) only uses floor 0. Treat multi-floor as unused
legacy shape, not a feature (see Legacy shape at the end).

## Units

`UnitData` describes a unit type. `Unit` is a live instance. The same
`UnitData` can create either faction. **Faction belongs to `Unit`, not
`UnitData`.** Do not put faction into unit JSON. The battle definition or
spawn context decides it.

`BattleState.create_unit(unit_id, faction)` is the central creation path.
It copies data from `UnitData`, applies `ALLY_STAT_MULTIPLIER` to allies,
applies `initial_statuses`, and wires the death event
(`wire_unit_events()`).

`UnitData` fields (all optional except id/name/stats):

- `max_hp`, `attack`, `description` (free text shown in the hover panel)
- `attack_pattern` (default `"lane_front"`) + `attack_pattern_count`
- `aura_adjacent_ally_max_hp_bonus` (Guardião aura)
- `initial_statuses` (`{"strength": 2}`)
- `triggers` (`[{"event": ..., "effect": {...}, "condition"?: {...}}]`)
- `back_row_attack_bonus`, `advance_attack_bonus`

### Stats, modifiers and statuses

Two deliberately separate layers:

- **Direct modifiers**: `Unit.modify_attack()` (permanent ATK, used by
  Flanquear/Linha de Frente/Concentração/`modify_attack` effects), and
  derived bonuses recomputed **from scratch** on every grid change, never
  incrementally:
  - `BattleState.recalculate_auras()` → `Unit.set_received_max_hp_bonus()`
    (Guardião aura, orthogonal neighbors).
  - `BattleState.recalculate_position_modifiers()` →
    `Unit.set_position_attack_bonus()` (`back_row_attack_bonus` while in
    Back).
- **Statuses** (`Unit.statuses`, `status_id -> stacks`): Strength,
  Weakness, Poison, Burn, Stun. Reapplying **adds** stacks. Each status
  owns its consumption rule: Poison deals stacks and decays by 1, Burn
  deals stacks and is consumed fully (both in
  `process_end_of_turn_statuses()`), Stun skips one attack and consumes 1
  (`execute_unit_attack()`).

`Unit.get_effective_attack()` = `attack` + Strength − Weakness (+
`advance_attack_bonus` if `advanced_this_turn`), never negative. It is
used for real damage and for the UI. `advanced_this_turn` is set when a
unit moves to a lower row and reset at the end of `execute_full_turn()`.

`Unit.died` is emitted once, **before** `changed`, while lane/row are
still valid. `BattleState.on_unit_died()` captures position, removes the
unit from the grid immediately (so Death Spawn can summon into the freed
cell), then fires `on_death`.

## Combat

A unit never searches the battlefield itself:
`BattleState.execute_unit_attack(unit)` asks
`TargetSystem.get_pattern_attack_targets(unit)` and applies
`Unit.attack_unit()` to each target. On a real hit it emits
`attack_resolved(attacker, target, damage_dealt, hp_after, block_after)`.

`BattleState.execute_full_turn()`, fixed order (no initiative system):

```text
on_turn_start (all units)
→ enemies attack (execute_faction_turn, snapshot per floor)
→ allies attack
→ process_end_of_turn_statuses (Poison/Burn)
→ on_turn_end (all units)
→ reset advanced_this_turn
```

Iterations always snapshot the unit list first so mid-phase deaths and
removals don't break the loop.

`BattleState.is_victory()`/`is_defeat()` exist (unit counts across
floors), but the sandbox's real end check is `Game.check_battle_end()`,
which adds the wave gate.

### Turn preview (simulation)

`BattleState.simulate_full_turn()` runs `execute_full_turn()` on a fully
independent clone (`clone_for_simulation()`) and returns
`{real_unit: {hp, block}}`; a missing unit means it would die. The clone
sets `suppress_events` while rebuilding the roster (so `on_summon` doesn't
refire) and keeps `simulation_origin_map` (real unit → clone) because
triggers like Knockback can move units mid-simulation, so position is not
a reliable identity. Nothing is ever connected to a clone's
`attack_resolved`. `Game.update_turn_preview()` shows the predictions
through `UnitView.set_turn_preview()` whenever the preview checkbox is on,
refreshed on every `battlefield_changed`.

### Turn replay

The domain resolves a turn instantly and never waits. `Game` records
every `attack_resolved` into `turn_replay_log`, then
`play_turn_replay()` rewinds each `UnitView` to its pre-turn snapshot and
reveals each attack step by step (`TURN_REPLAY_STEP_DELAY`, attack pulse,
hit flash, damage popup). Units that died are already gone from the
`BattleFloor`, but `BattleFloorView.suppress_removal_refresh` keeps their
views on screen (`pending_removals`) until the fatal hit is replayed
(`reveal_pending_removal()`/`flush_pending_removals()`). Combat logic is
never duplicated outside the domain for this.

## Targeting architecture

Unit attack targeting and card targeting are **separate systems**. Avoid
faction-specific names (`front_enemy`, `selected_enemy`) in either.

### Unit attack patterns

String ids on `Unit.attack_pattern`, resolved by
`TargetSystem.get_pattern_attack_targets()`. The target faction is always
the attacker's opposite.

| Pattern | Behavior |
|---|---|
| `lane_front` | first N of own lane, Front→Back (Lanceiro uses count 2) |
| `lane_rear` | first N of own lane, Back→Front |
| `adjacent_lanes_furthest` | deepest unit across the neighbor lanes, never own lane |
| `primary_plus_adjacent_row` | first in own lane + same row in neighbor lanes |
| `front_or_rear_by_position` | `lane_rear` when attacker is in Back, else `lane_front` |

`TargetSystem.PATTERN_DESCRIPTIONS`/`describe_pattern()` sit next to the
implementation on purpose, so the UI text can't drift from the logic.

### Card targeting

Effect `target` values: `selected_unit` (optionally filtered by
`target_faction`: `ally`/`enemy`), `all_enemies`, `all_allies`.
`TargetSystem.get_card_targets(target_type, selected_unit, target_faction)`
is the single resolver for unit targets. `EffectSystem.can_target_selected_unit()`
is the same check used by both the real click and the hover preview, so
preview eligibility never disagrees with what clicking does.

Movement/buff cards (`reposition`, `teleport`, `flank`, `advance`,
`retreat`, `swap`, `frontline`, `concentration`) don't use `target`; the
target is implied by the action and driven by `Game.PendingAction` clicks
(`CardData.describe_action_type()` provides the label).

Summon cards take a grid cell (`selected_lane`/`selected_row`).

### Trigger targeting

A third, separate vocabulary for trigger effects, resolved by
`BattleState.resolve_trigger_targets()`: `self`, `trigger_target`,
`lane_enemies`, `lane_allies`, `all_allies`, `all_enemies`,
`adjacent_allies`. Targets come from the event context, not a player
choice.

## Effects

`EffectSystem.execute_effect(effect, selected_unit, selected_lane,
selected_row)` handles card effects. Non-summon effects resolve targets
via `TargetSystem`, then go through the static
`EffectSystem.apply_basic_effect(type, targets, effect)`: `damage`,
`block`, `heal`, `apply_status`, `remove_status`, `cleanse`,
`modify_attack`. Trigger effects reuse the same `apply_basic_effect()`.

`summon` is not a basic effect: `execute_summon_effect()` creates an ally
via `BattleState.create_unit()` and places it at the chosen cell
(`add_unit()` fallback).

`EffectSystem` reuses `BattleState.target_system`. There is only ever one
`TargetSystem` per `BattleState`.

## Events and triggers

Each `Unit` carries `triggers` copied from `UnitData`.
`BattleState.fire_event(unit, event, context)` runs every trigger of that
unit listening to the event (if `trigger_condition_met()`, which today only
knows a `row` key). `fire_event_all()` fires it for every unit on the
floor.

Events: `on_summon`, `on_move` (from `BattleFloor` signals, suppressed
during simulation rebuild), `on_attack`, `on_hit` (context: `target`,
`damage_dealt`), `on_kill`, `on_death` (context: lane/row/faction captured
before removal), `on_turn_start`, `on_turn_end`, `on_card_played` (fired by
`Game.finish_card_play()`).

`execute_trigger_effect()` special-cases `summon` (Death Spawn, into the
dead unit's cell), `move` (Knockback, via `BattleFloor.move_unit()`), and
`"amount": "damage_dealt"` (Vampiric). Everything else goes through
`apply_basic_effect()`. This is deliberately a small event→effect table,
not a universal rules engine.

## Cards

```text
data/cards/*.json → CardDatabase → CardData → Card (visual)
```

`CardData`: `id`, `name`, `description`, `cost`, `type`
(`attack`/`skill`/`unit`, informational only, `Deck` ignores it),
`effects`. `Game._on_card_played()` dispatches on the **first** effect's
`type`. `CardData.get_summon_unit_id()` lets `Card` show the summoned
unit's ATK/HP preview.

### Deck, hand, discard, graveyard

`Deck` is owned by `Game`, not `BattleState`. It is the **in-combat**
shuffle: `draw_pile`, `hand`, `discard_pile`, `graveyard_pile`.

- Today `setup_deck_and_mana()` builds it from **every card in
  `CardDatabase`**, one copy each. In the campaign this becomes "build the
  combat `Deck` from the chosen deck list" (see
  `CAMPAIGN_EXECUTION_PLAN.md` Etapa 2). Don't confuse the two concepts or
  reuse the name `Deck` for the campaign deck list.
- `draw(amount)` reshuffles discard into draw when empty (emits
  `reshuffled`), and respects `MAX_HAND_SIZE = 7`.
- End of turn: `discard_hand()` discards the whole hand, then 5 new cards
  are drawn.
- Played summon cards go to the graveyard (`bury()`) and never come back.
  Other cards go to discard.

`CardPileView` shows a title + count. `Game` has three: Baralho, Descarte,
Cemitério.

### Hand layout and animation

`Cards` is a plain `Control`, not an `HBoxContainer`, because a real
`Container` would fight manual positioning. `Game.layout_hand()` fans cards
out (`HAND_CARD_GAP`) and overlaps them once they no longer fit
`HAND_AREA_WIDTH`. `z_index` = hand index; hover raises temporarily to
`Card.HOVERED_Z_INDEX`.

`Game.render_hand()` reconciles instead of rebuilding. The `CardData`
reference is used as identity, which works today because each card type
is a single `CardData` instance. **Multiple copies of a card (campaign
decks) will break this assumption** and need distinct instances or another
identity. Existing views tween to their new slot, new ones animate in from
the deck pile (`play_draw_entrance()`), and leaving ones animate to the
discard/graveyard pile (`animate_card_leaving()`) with `is_leaving = true`.
`draw_cards()` draws one at a time with `CARD_DRAW_DELAY` and a draw sound.

### Mana

`Mana` (owned by `Game`): `current`/`max_mana`, `STARTING_MANA = 4`
(tunable, not settled design). It refills fully each turn.
`_on_card_played()` checks `can_afford()` before any targeting starts, and
`finish_card_play()` spends it only on success. `Game._on_mana_changed()` →
`update_hand_affordability()` recolors every hand card's cost label
(`Card.set_affordable()`).

### Pending card, confirm and cancel

Playing a card puts it in `Game.pending_card` (`Card.set_pending(true)`
locks its hover pose, and `static var Card.any_card_pending` stops other
cards reacting to hover) and arms a `Game.PendingAction`:

- `SPAWN`: click an empty ally cell.
- `EFFECT_UNIT` (`selected_unit` effects): hover-gated preview on legal
  targets only (`UnitView.arm_effect_preview()`), click to resolve.
- `CONFIRM` (`all_enemies`/`all_allies` effects, Linha de Frente): the
  preview shows immediately on every affected unit, and a left click
  anywhere confirms (`confirm_pending_card()`).
- `REPOSITION`/`FLANK`/`TELEPORT`/`SWAP`/`ADVANCE`/`RETREAT`: next unit
  click chooses the unit (`card_needs_unit_selection`), then a cell/second
  unit if needed. `CONCENTRATION`: click a lane.

Cancel with `Esc` (`ui_cancel`). Esc is layered in `Game._input()`: if
the menu is open it closes the menu, otherwise if something is pending it
cancels it, otherwise it opens the menu. Confirm and cancel live in
`Game._input()`, not `_gui_input()`, so they intercept clicks before the
GUI routes them to whatever `Control` is under the cursor.
`cancel_pending_action()` disarms all previews and returns the card to
normal. Nothing is spent. `finish_card_play()` spends mana, discards/buries,
fires `on_card_played`, and refreshes the turn preview.

## Presentation

### BattleFloorView

`battle_floor.tscn`:

```text
BattleFloor (PanelContainer)
└── Layout (HBoxContainer)
    ├── AllySection  → AllyLabel, AllyGrid (GridContainer)
    ├── VSeparator
    ├── EnemySection → EnemyLabel, EnemyGrid (GridContainer)
    ├── VSeparator2
    └── PatternInfoPanel → PatternInfoTitle, PatternInfoBody
```

Each cell is a fixed `Button` created once in `_ready()`, never destroyed
or reordered, so a cell always represents the same (lane, row). Occupying
or emptying a cell only swaps its content (a `UnitView` instance that
covers it). An empty cell click emits `cell_selected(faction, lane, row)`.
A click on an occupied cell is captured by the `UnitView` first.

Signals to `Game`: `unit_selected(unit)`, `cell_selected(...)`,
`unit_hover_started(unit)`/`unit_hover_ended(unit)`. Hover highlights the
unit's attack targets (red) and Guardião aura neighbors (green), and fills
`PatternInfoPanel` (`Game.show_pattern_info()`: description + pattern
text + aura).

### UnitView

Represents either faction. Never use `Enemy`/`EnemyView` terminology. It
emits the domain `Unit` (`selected(unit)`), never itself. It displays
name, HP, block, effective ATK, statuses, and position, and handles effect
preview colors (`get_delta_color()`: red worse / green better), turn
preview, highlight, attack preview (Linha de Frente), hit flash, attack
pulse and damage popup. `restore_base_display()` returns to the real state
(or the turn preview if active).

### UI → domain

```text
UnitView → selected(Unit) → BattleFloorView → unit_selected(Unit) → Game
```

The gameplay layer decides whether the selected unit is a valid target.

## Battle definitions

```json
{ "floors": [ { "units": [
  { "id": "warrior", "faction": "ally", "lane": 0, "row": 0 },
  { "id": "tank",    "faction": "enemy", "lane": 0, "row": 0 }
] } ] }
```

Faction is per instance. `lane`/`row` are optional (`add_unit()` fallback).
`BattleDefinition.empty()` is a single empty floor (used by "Random" and
the simulation clone). In the campaign, encounters will reference battle
definitions and add victory rules and rewards (see
`CAMPAIGN_EXECUTION_PLAN.md` Etapa 3).

## Legacy shape

`Battlefield` still supports multiple floors and `BattleDefinition` still
has a `floors` array (leftover from the pre-3x3 multi-floor formations),
but only floor 0 is used (see Battlefield above). Don't build on
multi-floor. Collapsing it to a single floor would change the battle JSON
format, so do it only as its own deliberate change.

The other pre-3x3 leftovers (`Pyre`, `GameState`, `EnemySpawner`,
`TargetRule`/`TargetSystem.get_attack_targets()`) were removed.
