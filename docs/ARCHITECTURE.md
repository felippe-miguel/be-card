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
- `Mana` (current/max mana, refilled per turn, spent to play cards)
- `EnemySpawner` (spawns enemy `Unit`s automatically for the first few turns)

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
│   ├── mana.gd
│   ├── enemy_spawner.gd
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

Hand size is capped at `Deck.MAX_HAND_SIZE` (currently 7): drawing beyond
that is a no-op, the card stays in `draw_pile` until there's room.

## Hand layout

`Cards` (the node holding hand `Card` views) is a plain `Control`, not an
`HBoxContainer` — a real `Container` would fight any manual positioning by
re-sorting children every layout pass. `Game.layout_hand()` positions each
`Card` explicitly: cards fan out left-to-right, spaced by
`Game.HAND_CARD_GAP` when there's room, and overlap (reduced spacing) once
the hand no longer fits `Game.HAND_AREA_WIDTH` — never escaping past that
reserved width, however large the hand gets. `Game.HAND_AREA_WIDTH` is
hardcoded to the space `BottomBar`'s layout currently leaves for `Cards`;
it must be revisited if a sibling of `Cards` in `BottomBar` changes size.

Stacking order is fixed and left-to-right: `Card.z_index` = hand index (via
`set_hand_position()`), so the rightmost card is always on top at rest.
Hovering a card raises it to `Card.HOVERED_Z_INDEX` (temporarily above
everything) and lowers it back to its own `rest_z_index` on mouse-exit —
hover never permanently changes the resting order. A "last-hovered card
stays on top after the mouse leaves" variant was tried and reverted per
explicit user feedback: it made the stacking order feel arbitrary instead
of a fixed, predictable left-to-right fan.

## Mana

`Mana` (owned by `Game`, alongside `Deck`) tracks `current`/`max_mana`.
`Game._on_end_turn_pressed()` calls `Mana.refill()` at the start of each
turn — mana does not carry over between turns. `Game._on_card_played()`
checks `Mana.can_afford(card.data.cost)` before entering any targeting
state, so an unaffordable card never starts a target-selection flow; the
actual `Mana.spend()` happens in `Game.execute_card()`, at the same point
`Deck.discard()` runs. `Card.set_affordable()` colors the cost label red
when the card can't currently be played. `Game.STARTING_MANA = 3` is a
tunable default, not settled game design.

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

## Unit effect preview

While a card with a `"selected_unit"` effect is pending
(`GameState.State.TARGETING_UNIT`), hovering a `UnitView` previews that
effect's result on it — resulting HP after `damage`/`heal`, resulting
block after `block` — instead of only knowing whether it's a legal target
once clicked.

`Game.begin_unit_effect_preview(card_data)` arms this per-unit: for every
`UnitView` across every floor, it filters `card_data.effects` to the
`"selected_unit"` ones and keeps only those `EffectSystem.
can_target_selected_unit()` says this specific `Unit` can legally receive
— the exact same check that already gates the real click in
`Game.can_select_unit_for_card()`. This means preview eligibility can
never disagree with what clicking would actually do. Eligible effects are
handed to `UnitView.arm_effect_preview(effects)`; ineligible units are
simply never armed, so hovering them shows nothing.

`UnitView.show_effect_preview()` runs on the view's own `mouse_entered` —
unlike the summon-placement preview (see Positioning above), nothing here
needs to move as a result of hovering, so there's no risk of the
"element moves out from under the mouse" flicker that made a decoupled
hover-zone overlay necessary there. It simulates the armed effects in
order (matching the order `EffectSystem.execute_effect()` would actually
apply them) using `CombatMath.apply_block()` for `damage` — so a preview
correctly accounts for block absorption — and simple clamped arithmetic
for `heal`/`block`, without touching the real `Unit`.

`unit_view.tscn` changed from a single `Button.text` (one multi-line
string) to separate child `Label`s per field (`NameLabel`, `FactionLabel`,
`HpLabel`, `AtkLabel`, `BlockLabel`, `PositionLabel`, under a `Content`
`VBoxContainer`) specifically so `HpLabel`/`BlockLabel` can have their own
`font_color` overridden per preview, independent of the rest — per
explicit user decision, the previewed number itself turns red/green
(`UnitView.get_delta_color()`), not an appended "→ result" arrow.
A `DeathIndicator` `Label` ("X", large, red, anchored full-rect on top of
`Content`) shows whenever the previewed HP would reach 0, a first hint
that a card is about to be lethal before it's actually played.
`Game.end_unit_effect_preview()` disarms every view (reverting labels to
real values/colors, hiding the death indicator) once a legal unit is
actually clicked.

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

This diagram is the *full-floor* layout — `position_index` maps to those
exact screen columns only once a faction's formation is full. Below that,
`BattleFloorView` anchors occupied slots to the edge farthest from center
(so a sparse formation doesn't crowd toward the middle) — see Summon-to-slot
UI below for why and how.

## Positioning

`BattleFloor.insert_unit_at(unit, position)` is the general insertion
operation: it clamps `position` to `[0, current size]` and uses
`Array.insert()`, which naturally shifts every unit from that index
onward — this is the "push" mechanic summon-into-a-slot relies on.
`add_unit(unit)` is just `insert_unit_at(unit, <current size>)`, i.e.
"insert after everyone" — the old default-summon behavior, now a thin
wrapper instead of its own `find_first_free_position()` logic (removed;
the formation is always compact, so "after everyone" and "first free
slot" were always the same slot anyway).

Both operations still refuse to add a unit past `max_units` for that
faction — pushing existing units aside doesn't create a new slot, it only
reorders the slots that already fit.

After removal, `reorder_units()` compacts the remaining formation (unchanged).

Not yet implemented: `move_unit(from, to)`, and any push/pull mechanics
that aren't summon-driven (e.g. a card that shoves an existing unit
without adding a new one).

### Summon-to-slot UI

Summon cards target `"selected_position"` (see Card targeting below), not
`"selected_floor"` — the player picks one of 3 fixed conceptual slots
(front/middle/rear = `position_index` 0/1/2) directly, in one interaction,
rather than picking a floor and then defaulting to the first free slot.

**Screen columns and `position_index` are not fixed to each other** — a
faction's occupied units anchor to the edge farthest from the center and
grow toward the center as more are added (see Battlefield and floors
above for why: `layout_slots()`/`preview_arrangement()`, not a fixed
`max_units`-wide mapping). A lone unit sits at the outermost slot,
not the front-most screen column; it only reaches the true front-most
column once the floor is full. Per explicit user feedback, this was
changed from an earlier version that always mapped `position_index` 0 to
a fixed screen column regardless of how many units existed — which made a
sparse floor's unit(s) crowd toward the center instead of the edge. The
hover-zone-to-insert-index translation
(`BattleFloorView.zone_index_to_insert_position()`) depends on this same
anchoring and therefore on live unit count, so — unlike the original
version — it can no longer be computed once and bound in `_ready()`; it's
recalculated on every hover/click.

Per an explicit user decision, this is inactive outside a pending summon —
`BattleFloorView` keeps showing only the present `UnitView`s day-to-day,
same as before this feature. What activates during placement mode
(`BattleFloorView.begin_placement(unit_data)`, called by
`Game.begin_placement_preview()` when a summon card's `TARGETING_POSITION`
starts; deactivated by `end_placement()`) is described below. A floor
that's already full for `ALLY` never activates (nothing to push into).

**Hover/click detection is deliberately decoupled from the visual content
it previews**, to avoid a real instability: if the thing you're hovering
to trigger a preview is also the thing that visually *moves* as a result
of that preview (e.g. hovering a unit's own `UnitView` to insert before
it, which then slides that same `UnitView` out from under a stationary
mouse), you get `mouse_exited` → preview reverts → the view slides back
under the mouse → `mouse_entered` → preview reapplies → infinite flicker.
This was tried and rejected during development for exactly that reason.

The fix: `AllyHoverZones` (3 invisible, always-equal-width `Button`s,
`Zone0`/`Zone1`/`Zone2` in `battle_floor.tscn`) sit in a `Control` overlay
(`AllyArea`) stacked on the exact same rect as `AllyContainer`, purely for
hit-testing. They are never reordered, never recreated, and their
`mouse_filter` toggles `IGNORE`↔`STOP` only in `begin_placement()`/
`end_placement()` — completely inert outside a pending summon. Content
underneath (`AllyContainer`'s real `UnitView`s, plus a lazily-created
ghost `Button`) can be freely reordered via `move_child()` in response to
a zone's hover, because the thing detecting the hover is a node that
itself never moves.

For the 3 ally hover zones (each `size_flags_horizontal = EXPAND_FILL`,
evenly splitting `AllyArea`'s width) to line up with the real content,
that content must divide the same width the same way. So every `UnitView`
— **both factions**, not just allies — gets `size_flags_horizontal =
EXPAND_FILL` (set once in `create_unit_view()`), and both `ally_container`
and `enemy_container` always hold exactly `battle_floor.max_units`
elements: real `UnitView`s plus invisible `Button` "spacers"
(`get_spacer_views_for_faction()`) filling out empty slots, kept in sync
by `sync_slots(faction)` on every add/remove of that faction, whether or
not placement is active. This went through two prior iterations: first,
units only switched to `EXPAND_FILL` *during* placement, visibly resizing
the instant a summon card was played (jarring); fixed by making ally
sizing permanent — which then made both factions' front lines flush
against each other at the center once ally content always filled its
whole half (see `CenterSpacer` below); finally, enemies got the same
always-`EXPAND_FILL` + spacer treatment as allies too, per user feedback,
purely for visual consistency between the two sides (enemies still have
no placement UI at all — `EnemyHoverZones` don't exist, only
`AllyHoverZones` does). `layout_slots(faction)` positions a faction's
`max_units` slots — front is position 0, rendered rightmost for `ALLY`
and leftmost for `ENEMY` (see Battlefield and floors above). Spacers are
invisible (`modulate` alpha 0) at all times for enemies, and for allies
outside placement; tinted visible (`EMPTY_SLOT_COLOR`, "Vazio" text) only
while `begin_placement()`/`end_placement()` toggle the ally ones — but
they exist permanently either way, so a real `UnitView`'s width truly
never changes for either faction. A floor with zero units of some faction
from the start (true for every floor's `ENEMY` side today, since
`EnemySpawner` populates it) never goes through `create_unit_view()` at
setup, so never calls `sync_slots()` on its own — see the guard in
`connect_to_floor()`, which now runs for both factions independently.

Making both `AllyContainer` and `EnemyContainer` always expand to fill
their half renders the two factions' front lines flush against each
other with no gap at the center, which is why `CenterSpacer` (a
fixed-width, non-expanding `Control`, `battle_floor.tscn`) sits between
`AllyArea` and `EnemyContainer` in the outer `HBoxContainer` — a
guaranteed minimum gap regardless of how either side's content behaves.

`BattleFloorView.preview_arrangement(target_position)` does the actual
hover-preview work: simulate the insert on a duplicated array (no real
`BattleFloor` mutation — a stat-preview ghost `Button` stands in for the
new unit, per explicit user decision to show name/ATK/HP, not just
highlight a slot), then apply that simulated order to `AllyContainer` via
`move_child()` — real `UnitView`s slide to their pushed-aside position,
the ghost appears exactly where the new unit would land, and spacers are
hidden/shown as needed to keep the row at a constant `max_units` elements.
`layout_slots(Unit.Faction.ALLY)` is the same placement without a ghost —
the "nothing hovered" resting arrangement, used both for normal
(non-placement) sync and on `mouse_exited`.

Card target flow (summon): `Card` played → `Game.get_required_target()`
returns `"position"` → `GameState.State.TARGETING_POSITION` →
`Game.begin_placement_preview()` activates every eligible floor → player
clicks a hover zone → `BattleFloorView.position_selected(floor_index,
position_index)` → `Game._on_position_selected()` → `Game.execute_card()`
with both `selected_floor` and `selected_position` → `EffectSystem`'s
`"summon"` branch calls `BattleFloor.insert_unit_at()` instead of
`add_unit()` whenever `selected_position >= 0`.

No cancel flow exists for `TARGETING_POSITION` (matching the pre-existing
gap for `TARGETING_UNIT`/`TARGETING_FLOOR` — once a summon card is played,
the player must complete it by clicking a slot on some floor with room).

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
          "id": "skeleton",
          "faction": "ally"
        }
      ]
    }
  ]
}
```

`test_battle.json` currently only lists `ally` units (the player's starting
party) per floor — no `enemy` entries. Enemies are no longer pre-placed in
the battle definition; they come from `EnemySpawner` instead (see Enemy
spawning below). A battle definition can still list `enemy` units directly
if a future battle wants specific hand-placed enemies (e.g. a boss) — the
schema supports it — but the default content going forward spawns enemies
dynamically. Keeping at least one `ally` per starting floor is deliberate:
`BattleState.is_defeat()` checks for zero allies across the whole
battlefield, so a battle with no starting allies and no way to summon one
before the first `Encerrar turno` would defeat the player immediately.

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
summon effect (target: selected_position)
 ↓
TARGETING_POSITION
 ↓
player selects a floor + slot (front/middle/rear)
 ↓
BattleState.create_unit()
 ↓
Faction.ALLY
 ↓
BattleFloor.insert_unit_at()
 ↓
unit_added
 ↓
UnitView
```

Before the card is even played, `Card` shows a stat preview for summon
cards: `CardData.get_summon_unit_id()` reads the `unit` id off the
`summon` effect (pure data derivation, same style as
`get_target_description()`), and `Card.update_summon_preview()` resolves
that id against `UnitDatabase` (passed into `Card.setup()` by
`Game.render_hand()`) to show base ATK/HP. Hidden for non-summon cards.

Summon no longer defaults to "first free slot" — the player always picks
the slot explicitly (see Positioning above). `BattleFloor.add_unit()` (append
after everyone) still exists as the general "no specific slot" fallback
and is what `EnemySpawner` uses, since enemy spawning has no per-slot UI.

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
selected_position
all_enemies
all_allies
...
```

`TargetSystem.get_card_targets(target_type, selected_unit, target_faction)` is
the single resolver for targets that are Units. `selected_floor` and
`selected_position` are consumed by effects that require a floor (or a
floor + slot) and are handled by the UI flow, not `TargetSystem`.

`selected_unit` means the Unit chosen by the UI. Use the optional
`target_faction` field to limit it to `ally` or `enemy`, without reintroducing
names such as `selected_enemy`.

`selected_position` carries both a floor index and a slot
(`position_index` 0/1/2, front/middle/rear) chosen together in one
interaction — see Positioning above. All 3 current summon cards use it;
`selected_floor` alone is still supported by `EffectSystem`/`GameState` for
any future effect that only needs a floor, but nothing currently uses it.

## GameState

Current interaction concepts include:

```text
PLAYER_ACTION
TARGETING_UNIT
TARGETING_FLOOR
TARGETING_POSITION
COMBAT_PHASE
SPAWN_PHASE
```

`TARGETING_POSITION` now drives the summon-to-slot flow (see Positioning
above) — `"selected_position"` card effects transition to it and it
resolves via `BattleFloorView.position_selected`, not just a unit or a
floor.

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
`BattleState.execute_combat_phase()`, checks `Game.check_battle_result()`,
then (if the battle isn't over) advances `Game.current_turn`, runs
`Game.spawn_enemies_if_needed()` (see Enemy spawning below — a no-op most
turns), and transitions back to `PLAYER_ACTION`. The phase currently
resolves synchronously (no per-attack animation/pacing yet — combat
feedback is still `print()`-based, consistent with `UnitView`'s current
debug-first display).

Not yet implemented: turn order within/across floors beyond
`BattleFloor.get_units()` order (allies then enemies, each in
`position_index` order).

## Enemy spawning

`EnemySpawner` (owned by `Game`, alongside `Deck`/`Mana`) automatically
populates the battlefield with enemies for the first
`EnemySpawner.MAX_SPAWN_TURNS` turns (currently 3) — battle definitions no
longer pre-place enemies (see Battle definitions above). Each spawning turn,
`EnemySpawner.spawn_wave()` tries to add one enemy `Unit` to every
`BattleFloor` that still has room (`BattleFloor.can_add_unit()`), picked
randomly from `EnemySpawner.ENEMY_POOL`. With the default 3-slot floors,
three spawning turns naturally fill every floor to capacity — that's a
deliberate consequence of `MAX_SPAWN_TURNS` matching `BattleFloor.max_units`,
not a coincidence to preserve blindly if either number changes.
`EnemySpawner.should_spawn(turn_number)` gates this — turns beyond the
window are a no-op.

`Game.current_turn` (1-indexed) drives this: `Game.spawn_enemies_if_needed()`
transitions `GameState` to `SPAWN_PHASE` and runs the wave only when
`EnemySpawner.should_spawn()` is true; otherwise it does nothing and the
caller moves straight to `PLAYER_ACTION`. It runs once at the very start of
the battle (`Game._ready()`, turn 1 — before the starting hand is drawn) and
once at the end of every `Game._on_end_turn_pressed()` after `current_turn`
is incremented.

`Dragão` is deliberately excluded from `ENEMY_POOL` — it's boss-tier
(100 HP / 10 ATK vs. everything else in the 12–50 HP range) and reserved
for a future explicit/special spawn, not the random early pool.

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
