extends Control

@onready var card_container: HBoxContainer = $Cards
@onready var floors_container: VBoxContainer = $Floors

var card_database: CardDatabase
var effect_system: EffectSystem
var battle_state: BattleState
var unit_database: UnitDatabase

var game_state: GameState
var pending_card: Card = null

func _ready():
	card_database = CardDatabase.new()
	card_database.load_cards()
	
	unit_database = UnitDatabase.new()
	unit_database.load_units()
	
	battle_state = BattleState.new(unit_database)
	effect_system = EffectSystem.new(battle_state)
	
	game_state = GameState.new()
	
	setup_enemies()

	for card_id in card_database.cards:
		var card_data = card_database.cards[card_id]
		var card = preload("res://scenes/card.tscn").instantiate()

		card_container.add_child(card)
		card.setup(card_data)
		card.played.connect(_on_card_played)

func _on_card_played(card: Card) -> void:
	if game_state.current != GameState.State.PLAYER_ACTION:
		return

	print("Carta jogada: ", card.data.name)

	var needs_target = false

	for effect in card.data.effects:
		if effect.get("target", "") == "selected_enemy":
			needs_target = true
			break

	if needs_target:
		game_state.change_to(GameState.State.TARGETING_ENEMY)
		pending_card = card
		print("Escolha um inimigo.")
		return

	execute_card(card)

func setup_enemies() -> void:
	for floor in battle_state.battlefield.floors:
		var floor_node = floors_container.get_child(floor.index)

		for unit in floor.units:
			var enemy = preload("res://scenes/enemy.tscn").instantiate()
			floor_node.add_child(enemy)
			enemy.setup(unit)
			enemy.selected.connect(_on_enemy_selected)

func _on_enemy_selected(enemy: Enemy) -> void:
	if game_state.current != GameState.State.TARGETING_ENEMY:
		return

	print("Inimigo selecionado: ", enemy.unit.name)

	if game_state.current == GameState.State.TARGETING_ENEMY:
		game_state.change_to(GameState.State.PLAYER_ACTION)
		var card = pending_card
		pending_card = null
		execute_card(card, enemy.unit)

func execute_card(card: Card, selected_target: Unit = null) -> void:
	for effect in card.data.effects:
		effect_system.execute_effect(
			effect,
			selected_target
		)
