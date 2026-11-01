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
(raw overworld) is implemented: the game opens on a main menu, and
"Continuar"/"Nova campanha" lead to an overworld that draws the world map
graph from JSON, where the player travels between connected points (see
Scene flow and Overworld below). Entering a combat point opens the battle,
which returns to the map when it ends. Merchant and event points open
their own screens (see Gold and merchants, Events); the campaign autosaves
to disk (see Save and load). A point whose merchant/event data is missing
falls back to a "coming soon" placeholder.

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
  visited points, won combats, resolved unique events and the card collection (`card_id ->
  copies`) and the player's deck lists plus which one is active.
  gold and owned artifacts. Store ids, not catalog objects, so it serializes
  cleanly to a save file.
- **Battle state** (`BattleState`, `Battlefield`, `BattleFloor`, `Unit`,
  plus `Deck`/`Mana` owned by `Game`): exists only during one combat.

## Node vs RefCounted

Nodes (presentation/input):

- `Main` (`Node`, `main.tscn`): the project's main scene. Owns the current
  screen (see Scene flow).
- `MainMenu` (`Control`, `main_menu.tscn`), `Overworld` (`Control`,
  `overworld.tscn`), `Merchant` (`Control`, `merchant.tscn`),
  `DeckBuilder` (`Control`, `deck_builder.tscn`), `Event` (`Control`,
  `event.tscn`), `PointPlaceholder` (`Control`, `point_placeholder.tscn`): screens
  instantiated by `Main`.
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
- `MerchantData`, `MerchantDatabase` (merchant stock catalog: cards and/or artifacts)
- `ArtifactData`, `ArtifactDatabase` (artifact catalog)
- `EventData`, `EventDatabase` (event catalog)
- `CampaignSave` (reads/writes the save file)
- `DeckList` (a campaign deck built from the collection)
- `Deck` (in-combat draw pile / hand / discard / graveyard)
- `Mana`
- `WorldMapData`, `WorldPointData` (overworld graph catalog)
- `CampaignState`

## Directory structure

```text
res://
├── data/
│   ├── cards/     (61 cards)
│   ├── units/     (42 unit types, stats at player scale)
│   ├── battles/   (test_battle.json)
│   ├── world/     (overworld.json)
│   ├── merchants/ (merchant stock: village_market.json, wandering_trader.json)
│   ├── artifacts/ (4 artifacts)
│   ├── keywords/  (glossary: 14 keywords, statuses and trigger events)
│   ├── events/    (ancient_shrine.json, abandoned_chest.json, deserter_duel.json)
│   └── campaign/  (starting_collection.json, starting_decks.json, starting_resources.json)
├── resources/
│   ├── audio/     (music, sfx + SfxSheet .tres)
│   └── images/    (cards/<card_id>.png, artifacts/<artifact_id>.png art, frames)
├── scenes/        (main, main_menu, overworld, merchant, deck_builder, point_placeholder, game, battle_floor, unit_view, card, artifact_card, keyword_tooltip, card_pile_view, sfx_player)
├── scripts/
└── docs/
    ├── ARCHITECTURE.md              (this file)
    ├── CAMPAIGN_EXECUTION_PLAN.md   (next phase: campaign/world map/collection)
    ├── MECHANICS_EXECUTION_PLAN.md  (completed: status/triggers/etc.)
    ├── CARDS_EXECUTION_PLAN.md      (card archetypes)
    ├── MERCHANT_CARDS_EXECUTION_PLAN.md (real cards in merchant/deck builder, keyword glossary)
    └── playtest_3x3.md              (completed: original 3x3 sandbox spec)
```

The exact list may evolve; preserve responsibilities rather than filenames.

## Data-driven design

JSON is the content layer. Code is the engine. Avoid hardcoding
content-specific behavior into generic systems.

Card art is resolved by convention, `res://resources/images/cards/<card_id>.png`
(`Card.ART_PATH_FORMAT`). A card without art simply shows none. Artifact art
follows the same rule with `res://resources/images/artifacts/<artifact_id>.png`
(`ArtifactCard.ART_PATH_FORMAT`).

**Content language rule:** all player-facing text (card/artifact/event/unit
descriptions) is Portuguese, but mechanic terms the player uses in English
stay in English, spelled exactly like the glossary names in
`data/keywords/` (Strength, Weakness, Poison, Burn, Stun, Block, Cleanse,
On Hit, On Death, On Kill, On Summon, On Move, On Attack, On Card Played).
Card and unit *names* stay as authored (some English like "Poison Dart",
some Portuguese like "Fortificar"). Ids and JSON keys are always English.
Highlighting matches by name, so a term spelled differently in a
description is not highlighted.

**Unit and summon card text:** a unit's `description` lists only its own
effects (triggers, passives, special stats), e.g. "On Death: cura 5 de HP
dos aliados da própria lane."; a unit with no effect gets a one-line summary
of its attack pattern. Unit names are character names ("Mártir",
"Porta-Estandarte"), never the name of the effect. Summon cards leave
`description` empty: `CardData.get_display_description()` then shows the
summoned unit's description on the card, so each effect is written once.
A summon card with a rule of its own can still set its `description`, which
wins.

## Scene flow

```text
Main (main.tscn, run/main_scene)
 ├── MainMenu   — "Continuar" (only with a save) / "Nova campanha" →
 │                Overworld, "Sair" → quit
 ├── Overworld        — world map; enter current point → Game (combat),
 │                      Merchant (card/artifact merchant), Event, or
 │                      PointPlaceholder (fallback); deck panel "Editar"/"Criar novo deck"
 │                      → DeckBuilder; "Voltar ao menu"/Esc → MainMenu
 ├── Game             — battle; battle_finished(victory) → Overworld
 ├── Merchant         — buy cards/artifacts; "Voltar ao mapa"/Esc → Overworld
 ├── DeckBuilder      — edit a deck; Salvar/Apagar/Cancelar/Esc → Overworld
 ├── Event            — choices; "Voltar"/Esc → Overworld; a battle choice
 │                      → Game, then Overworld
 └── PointPlaceholder — fallback "em breve"; "Voltar ao mapa"/Esc → Overworld
```

`Main` holds exactly one screen at a time (`current_screen`,
`switch_to()` frees the previous one with `queue_free()`, since the switch
usually happens inside a signal emitted by that very screen). Screens never
change scenes themselves. They only emit signals (`new_campaign_pressed`,
`quit_pressed`, `back_to_menu_pressed`), and `Main` decides what comes
next. `Main` also owns the `CampaignState` (a fresh one on "Nova
campanha", or one rebuilt from the save on "Continuar"), with no global
autoload. `Main` only passes the battle a `battle_id` (`Game.setup_battle()`), not
the whole `CampaignState`. The battle reports back through
`battle_finished(victory)`. `Main` records it on the current point
(`CampaignState.record_current_combat_result()`, which also pays the gold
reward) and returns to the overworld at the same point, with a one-line
notice ("Vitória em X: +N ouro") passed through `Overworld.setup()`.

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
real size depends on the theme font and the two-line text. Point types
(`WorldPointData.TYPE_NAMES`, which also holds their display names):
`camp` (neutral, nothing to enter), `combat`, `card_merchant`,
`artifact_merchant`, `event`. Each type gets a raw visual: a font color
(`Overworld.POINT_TYPE_COLORS`, every font state overridden so hover
doesn't lose it, dimmed when disabled). Color goes on the text, not on
`modulate`, because `modulate` already marks current/visited points.

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

Esc on the overworld (`_unhandled_input`) climbs one level: it closes the
open side panel (collection or decks) if any, otherwise goes back to the
main menu (same as "Voltar ao menu").

## Card collection

`CampaignState.collection` is `card_id -> copies` (always >= 1, missing =
not owned). It is what the player **owns**, not what they bring to a
battle (that's a `DeckList`, see Deck lists below).

- A new campaign starts from `data/campaign/starting_collection.json`
  (`{"cards": {"<card_id>": <copies>}}`, meant to be hand-edited).
  `CampaignState.load_starting_collection()` validates it against the
  `CardDatabase`: unknown card ids and non-positive/non-numeric counts are
  skipped with a console warning. JSON numbers come back as floats, so
  counts are converted with `int()`.
- `Main` loads its own `CardDatabase` and the starting collection once in
  `_ready()`, and copies the collection into every new `CampaignState`
  (`duplicate()`, so a campaign never mutates the starting data). `Game`
  still loads its own catalog, which is fine because it only receives card
  ids.
- `CampaignState.add_card(card_id, copies)` is the **only** way to grow
  the collection. Merchants, combat rewards and events must all go through
  it.
- The overworld has a raw read-only "Coleção" panel (top bar button):
  total count + "Name ×N" lines sorted by display name, refreshed on
  `CampaignState.changed`. The real collection UI is the DeckBuilder
  (Etapa 5).

## Deck lists

A `DeckList` (`RefCounted`) is a deck the player built outside combat:
`name` + `cards` (`card_id -> copies`, same shape as the collection). It is
**not** the in-combat `Deck` (draw/hand/discard). A battle's `Deck` is
built from a `DeckList`.

- `CampaignState.deck_lists` + `active_deck_index`. The active deck is
  chosen **on the overworld** and used for every battle until changed
  (user decision: no per-combat deck prompt).
- Rules are deliberately permissive (user decision): no min/max size and no
  per-card copy limit. `CampaignState.is_deck_valid()` only requires at
  least one card and no card using more copies than the collection owns.
  `select_deck()` refuses invalid decks. A new campaign's active deck is
  the first valid one.
- Starting decks come from `data/campaign/starting_decks.json`
  (`{"decks": [{"name": ..., "cards": {...}}]}`, hand-editable; the first
  one starts active). `DeckList.from_dict()` validates card ids/counts
  like the collection loader. `Main` loads them once, and each campaign
  gets copies (`DeckList.duplicate_list()`).
- Overworld UI: a "Deck: <name>" top-bar button opens a side panel (same
  corner as the collection panel; opening one closes the other) with one
  row per deck: a select button ("✔" on the active one, disabled with
  "— inválido" if invalid; click = `select_deck()`) and an "Editar" button
  (invalid decks stay editable so they can be fixed), plus "Criar novo
  deck". Edit/new emit `Overworld.deck_edit_requested(index)` (-1 = new),
  and `Main` opens the `DeckBuilder`.

## DeckBuilder

A full screen (user decision: the side panel is too small for editing).
Collection on the left as a 3-column grid of real `Card`s (each with
"no deck: X / owned" and a "+" disabled once every owned copy is in the
deck; **clicking the card also adds a copy**, via `Card.played`), deck on
the right as a compact list ("Name ×N", "−") in a fixed-width (400 px)
column, plus a name field, card count, Salvar / Cancelar / Apagar deck.

- The collection grid is built **once** in `_ready()`
  (`build_collection()`): the collection can't change while the builder is
  open. `refresh()` only updates the "no deck" labels and "+" buttons
  (`collection_usage_labels`/`collection_add_buttons`, by card id) and
  rebuilds the deck column, so Cards aren't recreated under the mouse
  (hover would flicker). Each tile is a holder `Control` + `Card`
  (`mouse_filter = PASS`, `rest_position = ZERO`, same pattern as the
  merchant tile) + footer; a `HoverMargin` `MarginContainer` in the scene
  keeps the lifted card from being clipped by the `ScrollContainer`.
- Cards get `Card.setup(data, unit_database, keyword_database)`, so they
  have their own keyword tooltip. Deck rows share a single
  `KeywordTooltip` owned by the builder (`row_tooltip`): row
  `mouse_entered` fills it (keywords + summoned unit block, same logic as
  `Card`) and shows it beside the row; `mouse_exited` and every
  `refresh()` hide it, so a rebuilt row never leaves a stale tooltip.
- `Main` passes `UnitDatabase` and `KeywordDatabase` to
  `DeckBuilder.setup()`.
- The equipped artifact is shown as an `ArtifactCard` under the "Deck"
  title (hidden for "Nenhum"), scaled to `ARTIFACT_PREVIEW_SCALE` (0.65)
  inside a holder of the scaled size. Its hover grows from
  `ArtifactCard.base_scale`, not from full size.

- All editing happens on a **copy** (`working_deck =
  DeckList.duplicate_list()`, or a new `DeckList` named "Novo deck N").
  Nothing touches `CampaignState` until Salvar. Cancelar/Esc discard (with
  the name field focused, the first Esc only unfocuses it).
- `DeckList.add_copy()`/`remove_copy()` edit the copy (an entry is erased
  at zero, keeping the "copies >= 1" invariant). The builder blocks going
  over owned copies, and Salvar is disabled while
  `CampaignState.is_deck_valid()` is false (empty deck).
- `CampaignState.save_deck(index, deck)` (-1 = append) refuses invalid
  decks, turns a blank name into "Sem nome" (`normalize_deck_name()`), and
  makes the saved deck active only if there was no active deck.
- Deck names are unique (user decision): `is_deck_name_taken(name,
  except_index)` compares trimmed, case-insensitive names, ignoring the
  deck being edited. `save_deck()` refuses a taken name, and the builder
  shows "Já existe um deck com esse nome" and disables Salvar as you type
  (`refresh_save_state()`). Editing the active deck keeps
  it active.
- `CampaignState.delete_deck(index)`: the last remaining deck can't be
  deleted (`can_delete_deck()`, so there's always something to fight
  with). Deleting the active deck activates the first valid remaining one,
  and deleting a deck before the active one shifts the index.
- Closing emits `closed(message)` ("Deck \"X\" salvo"/"apagado", or ""
  on cancel). `Main` returns to the overworld with it as the notice.
- Into battle: `Main.show_battle()` passes
  `active_deck.get_card_ids()` (one id per copy) to
  `Game.setup_battle(battle_id, card_ids)`. With no valid active deck, the
  battle isn't started (console warning).

## Gold and merchants

`CampaignState.gold` starts from `data/campaign/starting_resources.json`
(`{"gold": N, "artifacts": [...]}`, `CampaignState.load_starting_gold()`/
`load_starting_artifacts()`; a separate file from the collection because
it's where non-card starting resources go).

- Earning: each `combat` point has a `gold` value in the map JSON
  (`WorldPointData.gold_reward`). `record_current_combat_result(victory,
  gold_reward)` pays the full value on the first win and
  `REPEAT_COMBAT_GOLD_FACTOR` (0.5, rounded down) on repeats, and returns
  the amount earned. Defeat/flee pays nothing.
- Spending: `card_merchant`/`artifact_merchant` points have a `merchant`
  id pointing at `data/merchants/<file>.json` (`{"id": ..., "cards":
  {"<card_id>": <price>}, "artifacts": {"<artifact_id>": <price>}}`, both
  sections optional), loaded by `MerchantDatabase` into
  `MerchantData.card_prices`/`artifact_prices` (unknown ids/invalid prices
  skipped with a warning). Stock is fixed and infinite in this raw version.
  Cards can be bought repeatedly; an artifact only once, since you own one
  of each.
- `CampaignState.buy_card(card_id, price)` refuses without enough gold,
  otherwise subtracts the price and calls `add_card()` (the single way to
  grow the collection), which emits `changed` once.
- `CampaignState.buy_artifact(id, price)` also refuses an already owned
  artifact, then calls `add_artifact()` (the single way to gain one).
- One `Merchant` screen serves both merchant types: an "Artefatos" section
  and/or a "Cartas" section depending on the stock, each a 3-column
  `GridContainer` of real `ArtifactCard`s/`Card`s, sorted by price then
  name. Each tile (`create_tile()`) is a holder `Control` of the card's
  size + the card + a footer with "Você tem: N" / "Já possui" and
  "Comprar — P ouro". Buy buttons are disabled when unaffordable (or the
  artifact is owned); the card itself isn't clickable (no accidental
  buy). It refreshes on `CampaignState.changed`. The overworld top bar
  shows "Ouro: N".
- Why the holder: `Card` positions itself (`position` is animated on
  hover from `rest_position`), which would fight a `Container`'s layout.
  The holder is a plain `Control` that ignores the mouse; the card inside
  uses `mouse_filter = PASS` (hover works, and the mouse wheel still
  scrolls the `ScrollContainer`, which the default STOP would swallow).
  The grid sits in a margin (`GRID_MARGIN_*`) so the lifted/scaled
  hovered card isn't clipped by the scroll area; a hovered card draws
  over neighbours through its `z_index`.
- `Main` loads `UnitDatabase` and `KeywordDatabase` once (next to
  `CardDatabase`/`ArtifactDatabase`) and passes them to `Merchant.setup()`
  and `DeckBuilder.setup()` (summon preview and tooltips). `Game` still
  loads its own copies, since it also runs standalone from the editor.

## Artifacts

Artifacts are a separate collectible (user decision: **per deck**, max 1
equipped per deck), not global passives.

- Catalog: `data/artifacts/*.json` (`{"id", "name", "description",
  "effect": {"type", "amount"}}`) → `ArtifactDatabase` → `ArtifactData`.
  Effect types (`ArtifactData.EFFECT_TYPES`) each map onto something the
  battle already does: `max_mana` (added to `Mana.max_mana`), `hand_size`
  (added to cards drawn at start and every turn, `Game.get_hand_size()`),
  `ally_max_hp`/`ally_attack` (added to every ally created in the battle,
  roster and summons, in `BattleState.create_unit()`; allies use the JSON
  stats as-is and enemies are divided by `ENEMY_STAT_DIVISOR`, which the
  bonus does not go through).
- Ownership: `CampaignState.artifacts` (`id -> true` set). The same
  artifact can be equipped in several decks at once. A new campaign starts
  with `starting_resources.json`'s `artifacts`.
- Equipping: `DeckList.artifact_id` ("" = none; a single field because the
  rule is max 1). `is_deck_valid()` also requires the artifact to be
  owned. Starting decks can set `"artifact"` in `starting_decks.json`. The
  DeckBuilder has an "Artefato:" `OptionButton` (Nenhum + owned artifacts)
  with an `ArtifactCard` preview (see DeckBuilder), and the overworld deck panel shows each deck's
  artifact. The collection panel lists owned artifacts too.
- Into battle: `Main.show_battle()` passes the active deck's
  `ArtifactData` (or null) to `Game.setup_battle()`. `Game` only reads
  bonuses via `get_artifact_bonus(type)` and passes the ally bonuses into
  `BattleState.new(...)`, which also copies them into simulation clones.
  The equipped artifact is shown next to the turn counter.
- Presentation: `ArtifactCard` (`artifact_card.tscn`) mirrors `Card`'s size
  and frame but has no cost/target/summon preview, a small gold "Artefato"
  marker in the footer, and no `played` signal. Its hover (lift/scale/
  z-index) is a minimal copy of `Card`'s, from `rest_position` and
  `base_scale` (resting scale, so a shrunk preview doesn't jump to full
  size). `setup(artifact, keyword_database = null)` creates a
  `KeywordTooltip` from `ArtifactData.get_keyword_ids()`, which is empty
  for today's four effects (none is a glossary mechanic), so no tooltip
  shows yet. `set_description_bbcode()` is the single place that writes
  the description.

Entering: arriving at a point never enters it (you can pass through a
combat point without fighting). Clicking the **current** point emits
`point_entered(point_id)` if `WorldPointData.can_enter()` (`combat` with a
`battle` id, or any merchant/event; shown with a "— entrar" hint). `Main`
opens the battle for `combat`, the `Merchant` for a card/artifact merchant
with a known `merchant` id, the `Event` screen for an `event` point whose
`event` id exists (Etapa 7, see Events), and a `PointPlaceholder` for
everything else (a merchant/event point with missing data).
`PointPlaceholder` only shows the point name and "<tipo> — em breve", and
returns to the map without recording anything.

This is a deliberately raw clickable-graph map (no camera, scroll or art).
If the map later becomes a free-walking character map, only this
presentation should change, not the graph data or campaign state.

## Events

An `event` point has `"event": "<id>"` pointing at
`data/events/<id>.json`: `{"id", "name", "text", "repeatable", "choices":
[{"label", "result_text"?, "effects": [...]}]}`. `EventDatabase` loads them
into `EventData` (same pattern as merchants). Effect types: `gold`
(`amount`, negative = cost), `card` (`card_id`, `count`), `artifact`
(`artifact_id`), `battle` (`battle_id`, `gold` paid on victory). Unknown
card/artifact/battle ids and malformed effects are skipped with a warning
(`EventData.parse_effect()`), a choice without a label too. No branching
dialogue: choosing applies the effects and ends the event.

- `CampaignState.apply_event_choice(event, index)` applies the effects
  through the existing operations (`add_gold()`, `add_card()`,
  `add_artifact()`) and returns `{"applied", "battle"}`. It refuses a choice
  the player can't pay for or that grants an already owned artifact
  (`can_choose_event_choice()`; the screen disables those buttons and says
  why), and a unique event already resolved.
- Unique events (`repeatable: false`, the default) are recorded in
  `CampaignState.completed_event_ids` (by event id) **when a choice is
  made**; repeatable events are never recorded. The overworld marks a
  resolved event point with the same "✔" as a won combat, and re-entering it
  shows "Você já resolveu este evento." with only "Voltar".
- The `Event` screen shows the title, text and one button per choice; after
  choosing it shows `result_text` (or a generated summary) and "Voltar"
  (Esc = Voltar). A choice with a `battle` effect emits
  `battle_requested(battle_id, gold)` instead: `Main` stores
  `event_battle_gold` and opens the normal battle with the active deck.
  `Main._on_battle_finished()` routes to `finish_event_battle()` while that
  is set: victory pays the gold through `add_gold()`, defeat/flee pays
  nothing, both return to the overworld, and the event point is **not**
  marked as a won combat. The event counts as resolved at choice time even
  if the battle is lost.

## Save and load

`CampaignState.to_dict()` serializes only ids and numbers (`"version"`
(`CampaignState.SAVE_VERSION`, 1), `current_point`, `gold`, `collection`,
`artifacts`, `decks` (`DeckList.to_dict()`: name, cards, optional artifact),
`active_deck`, `visited_points`, `won_combats`, `completed_events`). The
file is `user://campaign_save.json`; `CampaignSave` writes it atomically
(temp file + rename) and `read()` returns `{}` for a missing, unparseable or
unknown-version file, so a bad save simply counts as "no save".

- `CampaignState.from_dict(data, world_map, card_db, artifact_db,
  event_db, fallback_decks)` rebuilds the state tolerantly, warning with
  `push_warning`: unknown card/artifact/point/event ids are dropped; deck
  copies are clamped to the collection; a deck artifact that isn't owned is
  unequipped; a deck that ends up empty is dropped; an unknown current point
  becomes the start point; an invalid active deck becomes the first one; no
  deck left means the starting decks (raising the collection to cover them).
  Catalog changes therefore never break an old save.
- **Autosave** is owned by `Main`: `set_campaign_state()` connects
  `CampaignState.changed` to `save_campaign()` (travel, purchases, deck
  save/delete/select, event choices and combat results all emit it), and
  `show_overworld()` saves too. The battle never touches `CampaignState`, so
  there is no mid-battle save (leaving mid-battle or an event battle loses
  that battle, not earlier progress).
- Main menu: "Continuar" is shown only when `CampaignSave.exists()`;
  "Nova campanha" asks for confirmation (`ConfirmationDialog` in
  `MainMenu`) when a save exists, then replaces it on the next autosave.
  `Main.save_path` defaults to `CampaignSave.SAVE_PATH` and exists so tests
  can use another file.

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
`BattleState.ENEMY_STAT_DIVISOR = 2` (enemies spawn with half the JSON
ATK/HP) are temporary sandbox tuning, not settled design. They should become
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
It copies data from `UnitData`, divides enemy ATK/HP by `ENEMY_STAT_DIVISOR`
(min 1, rounded down), adds the artifact bonuses to allies,
applies `initial_statuses`, and wires the death event
(`wire_unit_events()`).

**Stats are at player scale**: `attack`/`max_hp` in `data/units/` are what
the player sees on the card's summon preview and on the ally in combat
(allies use them unchanged). Enemies use half (`ENEMY_STAT_DIVISOR = 2`),
so the same unit data serves both sides.

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
choice. `lane_enemies` and `adjacent_allies` fall back to the owner's own
lane/cell when the context has none (`on_card_played`, `on_summon`).

## Effects

`EffectSystem.execute_effect(effect, selected_unit, selected_lane,
selected_row)` handles card effects. Non-summon effects resolve targets
via `TargetSystem`, then go through the static
`EffectSystem.apply_basic_effect(type, targets, effect)`: `damage`,
`block`, `heal`, `apply_status`, `remove_status`, `cleanse`,
`modify_attack`, `double_status` (doubles the stacks of `status`; 0 stacks
does nothing) and `detonate_poison` (damage equal to the target's Poison
through `take_damage()`, then removes the Poison). Trigger effects reuse
the same `apply_basic_effect()`.

`shield_bash` (Golpe de Escudo) needs a derived target, so
`execute_effect()` routes it to `execute_shield_bash()`: the chosen ally
deals damage equal to its current Block (not consumed) to the first enemy
of its lane (`TargetSystem`/`BattleFloor.get_lane_units()`). It is plain
`take_damage()`, not attributed to the ally, so the ally's `on_kill` does
not fire.

`raise_dead` (Reerguer) is a card flow, not an `EffectSystem` effect:
`BattleState.dead_ally_ids` is a stack of ally `UnitData` ids pushed by
`on_unit_died()` (copied into `clone_for_simulation()`). `Game` plays it
like a summon (`PendingAction.SPAWN` on an empty **ally** cell), pops the
stack and creates the unit through `create_unit()`, so the x2 multiplier,
artifact bonuses and `on_summon` apply. With an empty stack the card is not
played.

`summon` is not a basic effect: `execute_summon_effect()` creates an ally
via `BattleState.create_unit()` and places it at the chosen cell
(`add_unit()` fallback).

`EffectSystem` reuses `BattleState.target_system`. There is only ever one
`TargetSystem` per `BattleState`.

## Events and triggers

Each `Unit` carries `triggers` copied from `UnitData`.
`BattleState.fire_event(unit, event, context)` runs every trigger of that
unit listening to the event (if `trigger_condition_met(unit, condition,
context)`, which knows two keys: `row`, and `card_type` compared with
`context["card_type"]`, where the special value `"spell"` means any card
whose type is not `unit`). `fire_event_all(event, context, only_faction)`
fires it for every unit on the floor, optionally only one faction.

Events: `on_summon`, `on_move` (from `BattleFloor` signals, suppressed
during simulation rebuild), `on_attack`, `on_hit` (context: `target`,
`damage_dealt`), `on_kill`, `on_death` (context: lane/row/faction captured
before removal), `on_turn_start`, `on_turn_end`, `on_card_played` (fired by
`Game.finish_card_play()` only for ALLY units, context `card_type` = the
played card's `type`; never during simulation).

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
`type`; `damage`/`heal`/`block`/`apply_status`/`cleanse`/`remove_status`/
`modify_attack`/`double_status`/`detonate_poison`/`shield_bash` go through
`begin_effect_card()` (click-a-unit or confirm-all). `CardData.get_summon_unit_id()` lets `Card` show the summoned
unit's ATK/HP preview. `Card` shows `CardData.get_display_description()`
(the unit's description for summon cards with an empty one), and then the
tooltip's unit block skips the description so it isn't shown twice
(`KeywordTooltip.set_unit(..., show_description)`).

### Keywords and tooltips

The mechanics glossary is content: `data/keywords/<id>.json` →
`KeywordDatabase` → `KeywordData` (`id`, `name` in English, `aliases`,
`color`/`has_color`, `description` in Portuguese). The 14 entries are the
statuses (strength, weakness, poison, burn, stun, block, cleanse) and the
trigger events (on_hit, on_death, on_kill, on_summon, on_move, on_attack,
on_card_played). Descriptions state the rule as the code implements it
(Poison ticks at end of turn and loses 1 stack, Burn is consumed whole,
Block never expires...). An invalid `color` warns and leaves the keyword
uncolored. `KeywordDatabase.get_keywords(ids)` skips unknown ids silently,
so new content without a glossary entry degrades gracefully.

Keywords come from the **data, never the description text**:
`CardData.keywords_of_effect(effect)` (static) maps an effect to ids
(`apply_status`/`remove_status`/`double_status` → their `status`,
`detonate_poison` → poison, `block`/`shield_bash` → block, `cleanse` →
cleanse); `CardData.get_keyword_ids(unit_database)` walks the card's
effects and, for `summon` with a `UnitDatabase`, also the unit's
`initial_statuses` and each trigger's event id + effect keywords,
deduplicated in first-appearance order. `ArtifactData.get_keyword_ids()`
reuses the same mapping. This is domain code; nothing in it touches UI.

`KeywordTooltip` (`keyword_tooltip.tscn`, a `VBoxContainer`) is the
presentation: one block per keyword (bold title in its color, explanation
below), preceded by a unit block for summon cards (`set_unit()`: name,
ATK/HP, `TargetSystem.describe_pattern()` and the unit description).
`Card.setup(card_data, unit_database = null, keyword_database = null)`:
with a `keyword_database` the card owns a tooltip child, shown on hover
and hidden on exit, when pending, when leaving and on `_exit_tree`.
`show_beside(target)` places it right of the target (left if it would
cross the viewport edge), top-aligned and clamped to the viewport; with no
content it shows nothing. It is `top_level` (doesn't inherit the card's
hover scale/position and isn't clipped by a `ScrollContainer`) with a very
high `z_index` and `z_as_relative = false`, so it draws over hovered
neighbours (`HOVERED_Z_INDEX = 100`). Its size is only right after the
autowrapping `RichTextLabel`s lay out, so it stays transparent for a
couple of frames and repositions at the end. Used by the hand (`Game`
loads a `KeywordDatabase` for `render_hand()`), the merchant and the
DeckBuilder.

Highlighting: `KeywordText.to_bbcode(text, keyword_database)` wraps each
colored keyword (name + aliases) found in a description with
`[b][color]`, in a single pass, case-insensitive, accent-aware at word
boundaries and including a following number ("Poison 3"). Its patterns are
cached per database. The card description (`DescriptionLabel`, now a
`RichTextLabel` with BBCode, centered), `KeywordTooltip` texts and
`ArtifactCard` descriptions all go through it. Highlighting is independent
of the tooltip: it paints any description that names the term, even if the
effect doesn't derive it.

### Deck, hand, discard, graveyard

`Deck` is owned by `Game`, not `BattleState`. It is the **in-combat**
shuffle: `draw_pile`, `hand`, `discard_pile`, `graveyard_pile`.

- `setup_deck_and_mana()` builds it via `build_deck_cards()`: from
  `deck_card_ids` (the active `DeckList`, set by `setup_battle()`), or from
  every card in `CardDatabase` (one copy each) when the scene is opened
  directly in the editor. Every copy is a **new** `CardData` instance
  (`CardData.copy()`), see Hand layout below for why. Don't confuse `Deck`
  with the campaign `DeckList`. "Resetar combate" rebuilds from the same
  ids.
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
reference is used as identity (as is `Deck`'s `hand.erase()`), which is
why `build_deck_cards()` gives every copy its own instance: two copies
sharing one instance would be treated as a single card. Existing views tween to their new slot, new ones animate in from
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
