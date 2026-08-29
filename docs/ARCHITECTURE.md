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
- `CardPileView` → `Control`

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
│   ├── battle_floor.tscn
│   └── game.tscn
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
├── cards/    (15 example cards)
├── units/    (9 unit types)
└── battles/  (1 test battle)
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

## Card visual states

`Card`'s border color has three states — `normal_style` (default),
`pending_style` (this card is `Game.pending_card`, waiting on a target), and
a transient `hover_style`. `Card.set_pending(true/false)` is called by
`Game` whenever `pending_card` changes.

While pending, a card is also locked into the hovered scale/position/z-index
(not just the border), and — via a shared `static var
Card.any_card_pending` — every card in hand stops reacting to real mouse
hover, since only one card can ever be pending at a time. There's no
explicit "un-pending" call when a card resolves normally: its node is
destroyed as part of the hand rebuild `Deck.discard()` triggers, so
`Game.render_hand()` unconditionally resets `Card.any_card_pending = false`
at the start of every rebuild as a safety net.

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
- Hand size is capped at `Deck.MAX_HAND_SIZE` (currently 7): drawing beyond
  that is a no-op, the card stays in `draw_pile` until there's room.

`Deck` does not distinguish `CardData.type` (`attack`/`skill`/`unit`) —
every card is drawn from the same pile and discarded to the same pile.
Type-based deck rules (e.g. separate piles, deck-building/composition
screens) are a future feature, not implemented.

`CardPileView` (`Control`, `res://scenes/card_pile_view.tscn`) is a
generic visual for a pile: it only shows a title and a card count, no
individual cards. `Game` owns two instances, `DeckPileView` and
`DiscardPileView`, updated whenever `Deck.changed` fires.

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
Hovering a card raises it to `Card.HOVERED_Z_INDEX` temporarily; it always
drops back to its own `rest_z_index` on mouse-exit — hovering never
permanently changes the resting stacking order.

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
that affect the Pyre must use a distinct target type — no such effect exists
yet, and no combat outcome depends on the Pyre yet either.

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

`UnitView` represents either faction — never use `Enemy`/`EnemyView`
terminology for it (see `AGENTS.md`'s Naming section for the full rule):

```text
UnitView
 └── Unit
      ├── ALLY
      └── ENEMY
```

Visual structure (`unit_view.tscn`):

```text
UnitView (Button)
├── Content (VBoxContainer)
│   ├── NameLabel
│   ├── FactionLabel
│   ├── HpLabel
│   ├── AtkLabel
│   ├── BlockLabel
│   └── PositionLabel
└── DeathIndicator (Label, "X", overlay, hidden by default)
```

One `Label` per field — not a single combined multi-line `Button.text` —
specifically so `HpLabel`/`BlockLabel` can have independent `font_color`
overrides for the effect preview (below). `DeathIndicator` overlays the
whole view and is shown whenever previewed HP would hit 0.

`UnitView.size_flags_vertical = EXPAND_FILL` (and the same on its parent
chain — `Content`, the `HBoxContainer` inside `battle_floor.tscn`'s
`Layout`) so a unit's box fills the floor's full height rather than sitting
at a fixed minimum with blank space below it. If units ever look short
again, check every ancestor between `UnitView` and `BattleFloor` for a
missing `size_flags_vertical`/`size_flags_horizontal` fill flag — a single
non-expanding link anywhere in that chain caps everything below it.

## Unit effect preview

While a card with a `"selected_unit"` effect is pending
(`GameState.State.TARGETING_UNIT`), hovering a `UnitView` previews that
effect's result on it: `HpLabel`/`BlockLabel` recolor red (worse) or green
(better) via `UnitView.get_delta_color()`, simulating the effect
(`CombatMath.apply_block()` for `damage`, clamped arithmetic for
`heal`/`block`) without touching the real `Unit`.

`Game.begin_unit_effect_preview(card_data)` arms only units that are
actually legal targets, reusing `EffectSystem.can_target_selected_unit()`
— the same check the real click uses — so preview eligibility can never
disagree with what clicking would do.

Cards with `"all_enemies"`/`"all_allies"` (no specific target to choose)
show this preview immediately on every affected unit instead of
hover-gated — see Confirming a no-specific-target card below.
`UnitView.arm_effect_preview(effects, show_now)` controls which;
`show_now = true` also sets `persistent_preview` so `mouse_exited` doesn't
revert it the way a hover-only preview does.

`Game.disarm_all_unit_previews()` clears the preview for both cases, once
the card resolves or is canceled.

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

Visual orientation, when a formation is full, is:

```text
Enemies: [0] [1] [2] [3]
          ↑ front

Allies:  [3] [2] [1] [0]
                      ↑ front
```

Do not change logical indexes to compensate for visual orientation. Below
a full formation, screen columns don't map 1:1 to `position_index` — see
Positioning below for the actual (occupancy-dependent) rule.

## Positioning

`BattleFloor.insert_unit_at(unit, position)` is the general insertion
operation: it clamps `position` to `[0, current size]` and uses
`Array.insert()`, which shifts every unit from that index onward — this is
the "push" mechanic summon-into-a-slot relies on. `add_unit(unit)` is just
`insert_unit_at(unit, <current size>)` — append after everyone; this is
what `EnemySpawner` uses (no per-slot UI for enemies) and the general
"no specific slot" fallback. Both refuse to add a unit past `max_units` for
that faction — pushing existing units aside doesn't create a new slot, it
only reorders the slots that already fit.

After removal, `reorder_units()` compacts the remaining formation.

Not yet implemented: `move_unit(from, to)`, and any push/pull mechanics
that aren't summon-driven (e.g. a card that shoves an existing unit
without adding a new one).

### Summon-to-slot UI

Summon cards target `"selected_position"` (see Card targeting below), not
`"selected_floor"` — the player picks one of 3 conceptual slots
(front/middle/rear = `position_index` 0/1/2) directly, in one interaction.

This UI is inactive outside a pending summon — `BattleFloorView` shows only
the present `UnitView`s day-to-day, same as when no card is pending. It
activates via `BattleFloorView.begin_placement(unit_data)` (called by
`Game.begin_placement_preview()` when a summon card's `TARGETING_POSITION`
starts) and deactivates via `end_placement()`. A floor that's already full
for `ALLY` never activates (nothing to push into).

**Occupied slots anchor to the edge farthest from the center and grow
toward it as more units are added** — a lone unit sits at the outermost
slot, not the front-most screen column, and only reaches the true
front-most column once the floor is full. `position_index` 0 (front) is
unchanged as a domain concept — still "the most-central of whatever's
present", still what `TargetSystem.get_front_unit()` reads — only the
screen-column mapping is occupancy-dependent. `layout_slots(faction)`
computes it; the hover-zone-to-insert-index translation
(`BattleFloorView.zone_index_to_insert_position()`) depends on the same
live unit count, so it's recalculated on every hover/click rather than
bound once in `_ready()`.

**Hover/click detection is deliberately decoupled from the visual content
it previews.** If the thing you're hovering to trigger a preview is also
the thing that visually *moves* as a result of that preview, you get
`mouse_exited` → preview reverts → the view slides back under the mouse →
`mouse_entered` → preview reapplies → infinite flicker. `AllyHoverZones`
(3 invisible, always-equal-width `Button`s, `Zone0`/`Zone1`/`Zone2` in
`battle_floor.tscn`) sit in a `Control` overlay (`AllyArea`) stacked on the
exact same rect as `AllyContainer`, purely for hit-testing. They are never
reordered or recreated; their `mouse_filter` toggles `IGNORE`↔`STOP` only
in `begin_placement()`/`end_placement()`. Content underneath
(`AllyContainer`'s real `UnitView`s, plus a lazily-created ghost `Button`)
can be freely reordered via `move_child()` in response to a zone's hover,
because the thing detecting the hover is a node that itself never moves.

For the hover zones to line up with the real content, every `UnitView` —
both factions, not just allies, purely for visual consistency (enemies
have no placement UI of their own — no `EnemyHoverZones`) — always has
`size_flags_horizontal = EXPAND_FILL`, and both `ally_container` and
`enemy_container` always hold exactly `battle_floor.max_units` elements:
real `UnitView`s plus invisible `Button` "spacers"
(`get_spacer_views_for_faction()`), kept in sync by `sync_slots(faction)`
on every add/remove of that faction, whether or not placement is active —
this is what keeps a `UnitView`'s width constant regardless of hand/summon
activity. `layout_slots(faction)` positions a faction's `max_units` slots;
spacers are invisible (`modulate` alpha 0) except the ally ones while
`begin_placement()`/`end_placement()` toggle them visible
(`EMPTY_SLOT_COLOR`, "Vazio" text). `CenterSpacer` (a fixed-width,
non-expanding `Control` between `AllyArea` and `EnemyContainer`) guarantees
a minimum gap at the center, since both sides always fill their whole half.

A floor with zero units of some faction from the start (true for every
floor's `ENEMY` side today, since `EnemySpawner` populates it) never goes
through `create_unit_view()` at setup, so never calls `sync_slots()` on its
own — see the guard in `connect_to_floor()`, which runs for both factions
independently.

`BattleFloorView.preview_arrangement(target_position)` does the actual
hover-preview work: simulate the insert on a duplicated array (no real
`BattleFloor` mutation — a stat-preview ghost `Button` stands in for the
new unit, showing name/ATK/HP), then apply that simulated order to
`AllyContainer` via `move_child()` — real `UnitView`s slide to their
pushed-aside position, the ghost appears exactly where the new unit would
land, and spacers are hidden/shown as needed to keep the row at a constant
`max_units` elements. `layout_slots(Unit.Faction.ALLY)` is the same
placement without a ghost — the "nothing hovered" resting arrangement.

Card target flow (summon): `Card` played → `Game.get_required_target()`
returns `"position"` → `GameState.State.TARGETING_POSITION` →
`Game.begin_placement_preview()` activates every eligible floor → player
clicks a hover zone → `BattleFloorView.position_selected(floor_index,
position_index)` → `Game._on_position_selected()` → `Game.execute_card()`
with both `selected_floor` and `selected_position` → `EffectSystem`'s
`"summon"` branch calls `BattleFloor.insert_unit_at()` instead of
`add_unit()` whenever `selected_position >= 0`.

## Confirming a no-specific-target card

Cards whose effect targets `"all_enemies"`/`"all_allies"` go pending like
every other card, via `GameState.State.CONFIRM_EFFECT`
(`Game.get_required_target()` returns `"confirm"` for them).

`Game.begin_aoe_effect_preview(card_data)` shows the effect preview on
every `UnitView` of the affected faction *immediately*, not hover-gated the
way `"selected_unit"` previews are: with `"selected_unit"` the player is
choosing among several possible targets, so comparing them one at a time
via hover makes sense; with `"all_enemies"`/`"all_allies"` there's no
choice at all, every matching unit will be hit, so showing the result on
all of them at once is more useful.

Confirming actually plays the card: any left click anywhere while
`CONFIRM_EFFECT` calls `Game.confirm_pending_card()` (via `Game._input()`
— see Canceling a pending card below for why `_input()` and not
`_gui_input()`), which mirrors what the other 3 targeting states'
resolution handlers do — disarm previews, un-pend the card, return to
`PLAYER_ACTION`, then `execute_card()`.

## Canceling a pending card

`Esc` (the built-in `"ui_cancel"` action) or a right mouse click cancel
whichever card is `Game.pending_card`, from any of the 4 targeting states
(`TARGETING_UNIT`/`TARGETING_FLOOR`/`TARGETING_POSITION`/
`CONFIRM_EFFECT`) — no mana spent, no `EffectSystem.execute_effect()`
call, the card simply becomes playable again.

Both this and confirming (above) are implemented in `Game._input(event)`,
not `_gui_input()`. `_input()` runs before the SceneTree's GUI system
routes a click to whatever `Control` is under the cursor, so it intercepts
a click anywhere on screen — including on top of another `Card`, a
`UnitView`, or an `AllyHoverZones` zone (all `mouse_filter = STOP`, which
would otherwise absorb the click first). This also means a left click on,
say, another `Card` in hand while `CONFIRM_EFFECT` is active confirms the
pending card instead of reaching that other card's own click handler —
the click is a global "confirm"/"cancel" gesture, not aimed at a specific
element. `Game.is_targeting_state()` gates all of this to the 4 targeting
states, so none of it does anything during
`PLAYER_ACTION`/`COMBAT_PHASE`/`SPAWN_PHASE`/`BATTLE_OVER`.

`Game.cancel_pending_card()` undoes exactly whatever the matching
`begin_*_preview()` armed for the current state —
`Game.disarm_all_unit_previews()` for `TARGETING_UNIT`/`CONFIRM_EFFECT`
(shared between the `"selected_unit"` and AOE preview paths),
`end_placement_preview()` for `TARGETING_POSITION`, nothing extra for
`TARGETING_FLOOR` (nothing is armed for it) — then calls
`pending_card.set_pending(false)`, clears `pending_card`, and returns
`GameState` to `PLAYER_ACTION`.

## BattleFloor signals

```gdscript
signal unit_added(unit: Unit)
signal unit_removed(unit: Unit)
```

Summon flow:

```text
EffectSystem
 ↓
BattleFloor.add_unit() / insert_unit_at()
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

Current visual structure (`battle_floor.tscn`):

```text
BattleFloor (PanelContainer)
└── Layout (VBoxContainer)
    └── HBoxContainer
        ├── AllyArea (Control)
        │   ├── AllyContainer (HBoxContainer — real UnitViews + spacers)
        │   └── AllyHoverZones (HBoxContainer — 3 invisible hit-test zones)
        ├── CenterSpacer (Control)
        └── EnemyContainer (HBoxContainer — real UnitViews + spacers)
```

Both `AllyContainer`/`EnemyContainer` hold `UnitView` instances (plus
spacers — see Positioning above). When `unit_removed` fires,
`BattleFloorView` removes the matching view; `sync_slots()`/
`layout_slots()` keep the remaining formation compact and correctly
ordered.

Every node in this chain needs a fill/expand size flag in the direction
that matters (see the note at the end of the UnitView section above) — a
missing one anywhere caps everything below it from filling the floor.

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
party) per floor — no `enemy` entries; those come from `EnemySpawner`
instead (see Enemy spawning below). A battle definition can still list
`enemy` units directly if a future battle wants specific hand-placed
enemies (e.g. a boss) — the schema supports it. Keeping at least one
`ally` per starting floor is deliberate: `BattleState.is_defeat()` checks
for zero allies across the whole battlefield, so a battle with no starting
allies and no way to summon one before the first `Encerrar turno` would
defeat the player immediately.

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

`BattleFloor.add_unit()` (append after everyone, no specific slot) still
exists as the general fallback and is what `EnemySpawner` uses, since
enemy spawning has no per-slot UI.

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

Current interaction concepts:

```text
PLAYER_ACTION
TARGETING_UNIT
TARGETING_FLOOR
TARGETING_POSITION
CONFIRM_EFFECT
COMBAT_PHASE
SPAWN_PHASE
BATTLE_OVER
```

`TARGETING_POSITION` drives the summon-to-slot flow (see Positioning
above) — `"selected_position"` card effects transition to it and it
resolves via `BattleFloorView.position_selected`. `CONFIRM_EFFECT` drives
the no-specific-target flow (see Confirming a no-specific-target card
above).

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
`BattleState.execute_combat_phase()`, checks `Game.check_battle_result()`
(`BattleState.is_victory()`/`is_defeat()`, unit counts per faction across
all floors — Pyre not included yet), then (if the battle isn't over)
advances `Game.current_turn`, runs `Game.spawn_enemies_if_needed()` (see
Enemy spawning below — a no-op most turns), and transitions back to
`PLAYER_ACTION`. The phase currently resolves synchronously (no per-attack
animation/pacing yet — combat feedback is still `print()`-based, consistent
with `UnitView`'s current debug-first display).

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
