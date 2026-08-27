extends Control

@onready var card_container: HBoxContainer = $Layout/BottomBar/Cards
@onready var floors_container: VBoxContainer = $Layout/Floors
@onready var end_turn_button: Button = $Layout/BottomBar/EndTurnButton
@onready var result_label: Label = $Layout/ResultLabel
@onready var game_state_label: Label = $Layout/GameStateLabel
@onready var deck_pile_view: CardPileView = $Layout/BottomBar/DeckPileView
@onready var discard_pile_view: CardPileView = $Layout/BottomBar/DiscardPileView

var card_database: CardDatabase
var unit_database: UnitDatabase
var battle_database: BattleDatabase

var effect_system: EffectSystem
var battle_state: BattleState
var game_state: GameState
var deck: Deck

var pending_card: Card = null

const STARTING_HAND_SIZE = 5
const CARDS_DRAWN_PER_TURN = 2

const GAME_STATE_LABELS = {
	GameState.State.PLAYER_ACTION: "Sua vez",
	GameState.State.TARGETING_UNIT: "Escolha uma unidade",
	GameState.State.TARGETING_FLOOR: "Escolha um andar",
	GameState.State.TARGETING_POSITION: "Escolha uma posição",
	GameState.State.COMBAT_PHASE: "Fase de combate...",
	GameState.State.BATTLE_OVER: "Batalha encerrada"
}

func _ready():
	card_database = CardDatabase.new()
	card_database.load_cards()
	
	unit_database = UnitDatabase.new()
	unit_database.load_units()
	
	battle_database = BattleDatabase.new()
	battle_database.load_battles()
	
	var battle_definition = battle_database.battles["test_battle"]
	
	battle_state = BattleState.new(battle_definition, unit_database)
	effect_system = EffectSystem.new(battle_state)
	
	game_state = GameState.new()
	game_state.changed.connect(_on_game_state_changed)
	_on_game_state_changed()

	setup_units()

	var all_cards: Array[CardData] = []

	for card_id in card_database.cards:
		all_cards.append(card_database.cards[card_id])

	deck = Deck.new(all_cards)
	deck.changed.connect(_on_deck_changed)

	deck_pile_view.setup("Baralho")
	discard_pile_view.setup("Descarte")

	deck.draw(STARTING_HAND_SIZE)

	end_turn_button.pressed.connect(_on_end_turn_pressed)

func _on_end_turn_pressed() -> void:
	if game_state.current != GameState.State.PLAYER_ACTION:
		return

	game_state.change_to(GameState.State.COMBAT_PHASE)

	battle_state.execute_combat_phase()

	if check_battle_result():
		return

	game_state.change_to(GameState.State.PLAYER_ACTION)

	deck.draw(CARDS_DRAWN_PER_TURN)

## Verifica se a batalha terminou e, se sim, encerra a partida. Retorna
## true quando a batalha acabou, para os chamadores pularem a volta ao
## estado PLAYER_ACTION.
func check_battle_result() -> bool:
	if battle_state.is_defeat():
		end_battle("Derrota...")
		return true

	if battle_state.is_victory():
		end_battle("Vitória!")
		return true

	return false

func end_battle(message: String) -> void:
	game_state.change_to(GameState.State.BATTLE_OVER)

	result_label.text = message
	result_label.visible = true
	end_turn_button.disabled = true

	print(message)

func _on_card_played(card: Card) -> void:
	if game_state.current != GameState.State.PLAYER_ACTION:
		return
	
	print("Carta jogada: ", card.data.name)
	
	var required_target = get_required_target(card)
	
	if required_target == "unit":
		game_state.change_to(GameState.State.TARGETING_UNIT)
		pending_card = card
		
		print("Escolha uma unidade.")
		return
	
	if required_target == "floor":
		game_state.change_to(GameState.State.TARGETING_FLOOR)
		
		pending_card = card
		
		print("Escolha um andar.")
		return
	
	execute_card(card)

func get_required_target(card: Card) -> String:
	for effect in card.data.effects:
		var target = effect.get("target", "")
		
		if target == "selected_unit":
			return "unit"
		
		if target == "selected_floor":
			return "floor"
	
	return ""

func _on_game_state_changed() -> void:
	game_state_label.text = GAME_STATE_LABELS.get(game_state.current, "")

func _on_deck_changed() -> void:
	render_hand()

	deck_pile_view.set_count(deck.draw_pile.size())
	discard_pile_view.set_count(deck.discard_pile.size())

## Reconstrói os cards visuais da mão a partir de deck.hand. A mão é
## pequena o suficiente para reconstruir por completo a cada mudança,
## em vez de sincronizar node a node.
func render_hand() -> void:
	for child in card_container.get_children():
		child.queue_free()

	for card_data in deck.hand:
		var card = preload("res://scenes/card.tscn").instantiate()

		card_container.add_child(card)
		card.setup(card_data)
		card.played.connect(_on_card_played)

func setup_units() -> void:
	for battle_floor in battle_state.battlefield.floors:
		var floor_view = floors_container.get_child(battle_floor.index)
		
		floor_view.setup(battle_floor.index)
		floor_view.connect_to_floor(battle_floor)
		
		floor_view.selected.connect(_on_floor_selected)
		floor_view.unit_selected.connect(_on_unit_selected)
		
		for unit in battle_floor.get_units():
			floor_view.create_unit_view(unit)

func _on_floor_selected(floor_view: BattleFloorView) -> void:
	if game_state.current != GameState.State.TARGETING_FLOOR:
		return
	
	print("Andar escolhido: ", floor_view.floor_index)
	
	game_state.change_to(GameState.State.PLAYER_ACTION)
	
	execute_card(pending_card, null, floor_view.floor_index)
	pending_card = null

func _on_unit_selected(unit: Unit) -> void:
	if game_state.current != GameState.State.TARGETING_UNIT:
		return

	if not can_select_unit_for_card(pending_card, unit):
		print("A unidade selecionada não é um alvo válido para esta carta.")
		return
	
	print(
		"Unit selecionada: ", unit.name,
		" | Faction: ", unit.faction,
		" | Floor: ", unit.floor_index,
		" | Pos: ", unit.position_index
	)
	
	if game_state.current == GameState.State.TARGETING_UNIT:
		game_state.change_to(GameState.State.PLAYER_ACTION)
		execute_card(pending_card, unit)
		pending_card = null

func can_select_unit_for_card(card: Card, unit: Unit) -> bool:
	for effect in card.data.effects:
		if not effect_system.can_target_selected_unit(effect, unit):
			return false

	return true

func execute_card(
	card: Card,
	selected_unit: Unit = null,
	selected_floor: int = -1
) -> void:
	for effect in card.data.effects:
		effect_system.execute_effect(
			effect,
			selected_unit,
			selected_floor
		)

	deck.discard(card.data)

	check_battle_result()
