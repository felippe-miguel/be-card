extends Control

@onready var card_container: Control = $Layout/BottomBar/Cards
@onready var floors_container: VBoxContainer = $Layout/Floors
@onready var end_turn_button: Button = $Layout/BottomBar/EndTurnButton
@onready var result_label: Label = $Layout/ResultLabel
@onready var game_state_label: Label = $Layout/GameStateLabel
@onready var deck_pile_view: CardPileView = $Layout/BottomBar/DeckPileView
@onready var discard_pile_view: CardPileView = $Layout/BottomBar/DiscardPileView
@onready var mana_label: Label = $Layout/BottomBar/ManaLabel

var card_database: CardDatabase
var unit_database: UnitDatabase
var battle_database: BattleDatabase

var effect_system: EffectSystem
var battle_state: BattleState
var game_state: GameState
var deck: Deck
var mana: Mana
var enemy_spawner: EnemySpawner

var pending_card: Card = null
var floor_views: Array[BattleFloorView] = []

## Turno atual (1-indexado). Avança a cada vez que o combate automático
## termina e o jogo volta para PLAYER_ACTION.
var current_turn: int = 1

const STARTING_HAND_SIZE = 5
const CARDS_DRAWN_PER_TURN = 2
const STARTING_MANA = 3

## Layout da mão (Cards é um Control simples, não um HBoxContainer, para
## poder sobrepor cartas em vez de deixá-las vazar da tela quando a mão
## está cheia). HAND_CARD_WIDTH deve bater com custom_minimum_size.x do
## card.tscn. HAND_AREA_WIDTH é o espaço que Cards recebe dentro de
## BottomBar (ajustado à mão para o layout atual dessa barra — reveja se
## outro irmão de Cards em BottomBar mudar de tamanho).
const HAND_CARD_WIDTH = 220.0
const HAND_CARD_GAP = 20.0
const HAND_AREA_WIDTH = 900.0

const GAME_STATE_LABELS = {
	GameState.State.PLAYER_ACTION: "Sua vez",
	GameState.State.TARGETING_UNIT: "Escolha uma unidade",
	GameState.State.TARGETING_FLOOR: "Escolha um andar",
	GameState.State.TARGETING_POSITION: "Escolha uma posição",
	GameState.State.CONFIRM_EFFECT: "Clique em qualquer lugar para confirmar",
	GameState.State.COMBAT_PHASE: "Fase de combate...",
	GameState.State.SPAWN_PHASE: "Invocando inimigos...",
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
	enemy_spawner = EnemySpawner.new(battle_state)

	game_state = GameState.new()
	game_state.changed.connect(_on_game_state_changed)
	_on_game_state_changed()

	setup_units()

	spawn_enemies_if_needed()
	game_state.change_to(GameState.State.PLAYER_ACTION)

	var all_cards: Array[CardData] = []

	for card_id in card_database.cards:
		all_cards.append(card_database.cards[card_id])

	deck = Deck.new(all_cards)
	deck.changed.connect(_on_deck_changed)

	mana = Mana.new(STARTING_MANA)
	mana.changed.connect(_on_mana_changed)
	_on_mana_changed()

	deck_pile_view.setup("Baralho")
	discard_pile_view.setup("Descarte")

	deck.draw(STARTING_HAND_SIZE)

	end_turn_button.pressed.connect(_on_end_turn_pressed)

## ESC ("ui_cancel") ou clique direito cancelam a carta pendente; em
## CONFIRM_EFFECT, clique esquerdo em qualquer lugar confirma. Usa
## _input() (não _gui_input()) de propósito: roda antes do sistema de
## GUI despachar o clique para o que estiver sob o mouse (ex: outra
## carta, uma UnitView), então funciona em qualquer lugar da tela, não
## só em áreas "vazias" sem Controls por cima.
func _input(event: InputEvent) -> void:
	if not is_targeting_state():
		return

	if event.is_action_pressed("ui_cancel"):
		cancel_pending_card()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_pending_card()
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_LEFT and game_state.current == GameState.State.CONFIRM_EFFECT:
			confirm_pending_card()
			get_viewport().set_input_as_handled()

func is_targeting_state() -> bool:
	return (
		game_state.current == GameState.State.TARGETING_UNIT
		or game_state.current == GameState.State.TARGETING_FLOOR
		or game_state.current == GameState.State.TARGETING_POSITION
		or game_state.current == GameState.State.CONFIRM_EFFECT
	)

## Desiste da carta pendente sem jogá-la: nenhuma mana gasta, nenhum
## efeito executado, a carta continua na mão normalmente.
func cancel_pending_card() -> void:
	if pending_card == null:
		return

	print("Cancelado: ", pending_card.data.name)

	match game_state.current:
		GameState.State.TARGETING_UNIT, GameState.State.CONFIRM_EFFECT:
			disarm_all_unit_previews()
		GameState.State.TARGETING_POSITION:
			end_placement_preview()

	pending_card.set_pending(false)
	pending_card = null

	game_state.change_to(GameState.State.PLAYER_ACTION)

## Confirma a carta pendente sem alvo específico (efeito "all_enemies"/
## "all_allies"): joga de fato, como um clique de alvo válido faria nos
## outros fluxos de targeting.
func confirm_pending_card() -> void:
	if pending_card == null:
		return

	var card = pending_card

	print("Confirmado: ", card.data.name)

	disarm_all_unit_previews()
	card.set_pending(false)
	pending_card = null

	game_state.change_to(GameState.State.PLAYER_ACTION)

	execute_card(card)

func _on_end_turn_pressed() -> void:
	if game_state.current != GameState.State.PLAYER_ACTION:
		return

	game_state.change_to(GameState.State.COMBAT_PHASE)

	battle_state.execute_combat_phase()

	if check_battle_result():
		return

	current_turn += 1

	spawn_enemies_if_needed()
	game_state.change_to(GameState.State.PLAYER_ACTION)

	mana.refill()
	deck.draw(CARDS_DRAWN_PER_TURN)

## Passa pela fase de spawn (EnemySpawner.MAX_SPAWN_TURNS primeiros
## turnos) se ainda estiver dentro da janela de spawn; do contrário não
## faz nada. Não volta para PLAYER_ACTION sozinha — quem chama decide
## isso, para funcionar tanto no início da batalha quanto ao fim de um
## turno.
func spawn_enemies_if_needed() -> void:
	if not enemy_spawner.should_spawn(current_turn):
		return

	game_state.change_to(GameState.State.SPAWN_PHASE)

	enemy_spawner.spawn_wave(current_turn)

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

	if not mana.can_afford(card.data.cost):
		print("Mana insuficiente para jogar ", card.data.name, ".")
		return

	print("Carta jogada: ", card.data.name)
	
	var required_target = get_required_target(card)
	
	if required_target == "unit":
		game_state.change_to(GameState.State.TARGETING_UNIT)
		pending_card = card
		pending_card.set_pending(true)
		begin_unit_effect_preview(card.data)

		print("Escolha uma unidade.")
		return

	if required_target == "floor":
		game_state.change_to(GameState.State.TARGETING_FLOOR)

		pending_card = card
		pending_card.set_pending(true)

		print("Escolha um andar.")
		return

	if required_target == "position":
		game_state.change_to(GameState.State.TARGETING_POSITION)

		pending_card = card
		pending_card.set_pending(true)
		begin_placement_preview(card.data)

		print("Escolha uma posição.")
		return

	if required_target == "confirm":
		game_state.change_to(GameState.State.CONFIRM_EFFECT)

		pending_card = card
		pending_card.set_pending(true)
		begin_aoe_effect_preview(card.data)

		print("Clique em qualquer lugar para confirmar.")
		return

	execute_card(card)

func get_required_target(card: Card) -> String:
	for effect in card.data.effects:
		var target = effect.get("target", "")

		if target == "selected_unit":
			return "unit"

		if target == "selected_floor":
			return "floor"

		if target == "selected_position":
			return "position"

		if target == "all_enemies" or target == "all_allies":
			return "confirm"

	return ""

func _on_game_state_changed() -> void:
	game_state_label.text = GAME_STATE_LABELS.get(game_state.current, "")

func _on_mana_changed() -> void:
	mana_label.text = "Mana: %d/%d" % [mana.current, mana.max_mana]

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

	## A carta pendente nunca chama Card.set_pending(false) sozinha (seu
	## nó é destruído junto, no queue_free() acima); zera aqui pra
	## garantir que a flag estática nunca fique travada em true.
	Card.any_card_pending = false

	var card_views: Array[Card] = []

	for card_data in deck.hand:
		var card = preload("res://scenes/card.tscn").instantiate()

		card_container.add_child(card)
		card.setup(card_data, unit_database)
		card.set_affordable(mana.can_afford(card_data.cost))
		card.played.connect(_on_card_played)

		card_views.append(card)

	layout_hand(card_views)

## Posiciona as cartas da mão da esquerda para a direita, sobrepondo-as
## quando não há espaço suficiente para separá-las por completo. A carta
## mais à direita fica com o maior z_index (por cima) em repouso; passar
## o mouse sobre qualquer carta a traz para o topo enquanto o cursor
## estiver sobre ela (ver Card._on_mouse_entered/_exited()).
func layout_hand(card_views: Array[Card]) -> void:
	var count = card_views.size()

	if count == 0:
		return

	var step = HAND_CARD_WIDTH + HAND_CARD_GAP

	if count > 1:
		var max_step = (HAND_AREA_WIDTH - HAND_CARD_WIDTH) / float(count - 1)
		step = min(step, max_step)

	for i in range(count):
		card_views[i].set_hand_position(Vector2(i * step, 0), i)

func setup_units() -> void:
	for battle_floor in battle_state.battlefield.floors:
		var floor_view = floors_container.get_child(battle_floor.index)

		floor_view.setup(battle_floor.index)
		floor_view.connect_to_floor(battle_floor)

		floor_view.selected.connect(_on_floor_selected)
		floor_view.unit_selected.connect(_on_unit_selected)
		floor_view.position_selected.connect(_on_position_selected)

		for unit in battle_floor.get_units():
			floor_view.create_unit_view(unit)

		floor_views.append(floor_view)

func _on_floor_selected(floor_view: BattleFloorView) -> void:
	if game_state.current != GameState.State.TARGETING_FLOOR:
		return

	print("Andar escolhido: ", floor_view.floor_index)

	game_state.change_to(GameState.State.PLAYER_ACTION)

	execute_card(pending_card, null, floor_view.floor_index)
	pending_card = null

func _on_position_selected(floor_index: int, position_index: int) -> void:
	if game_state.current != GameState.State.TARGETING_POSITION:
		return

	print("Posição escolhida: andar ", floor_index, " slot ", position_index)

	end_placement_preview()
	game_state.change_to(GameState.State.PLAYER_ACTION)

	execute_card(pending_card, null, floor_index, position_index)
	pending_card = null

## Mostra os marcadores de slot (frente/meio/fundo) em todo andar, para o
## jogador escolher onde a unidade da carta pendente vai entrar.
func begin_placement_preview(card_data: CardData) -> void:
	var unit_id = card_data.get_summon_unit_id()
	var unit_data: UnitData = unit_database.units.get(unit_id)

	if unit_data == null:
		return

	for floor_view in floor_views:
		floor_view.begin_placement(unit_data)

func end_placement_preview() -> void:
	for floor_view in floor_views:
		floor_view.end_placement()

## Arma, em cada UnitView que for um alvo válido para algum efeito
## "selected_unit" da carta, um preview do resultado desse efeito
## (HP/block resultante) ao passar o mouse — ver UnitView.arm_effect_
## preview(). Reaproveita EffectSystem.can_target_selected_unit(), a
## mesma checagem usada para validar o clique de fato. Não mostra nada
## até o jogador passar o mouse: faz sentido aqui, já que ele está
## escolhendo entre várias unidades possíveis.
func begin_unit_effect_preview(card_data: CardData) -> void:
	for floor_view in floor_views:
		for unit_view in floor_view.get_all_unit_views():
			var eligible_effects: Array[Dictionary] = []

			for effect in card_data.effects:
				if effect.get("target", "") != "selected_unit":
					continue

				if effect_system.can_target_selected_unit(effect, unit_view.unit):
					eligible_effects.append(effect)

			if not eligible_effects.is_empty():
				unit_view.arm_effect_preview(eligible_effects)

## Mostra, imediatamente e sem precisar de hover, o preview de um efeito
## "all_enemies"/"all_allies" em toda unidade da facção afetada — ao
## contrário do preview de "selected_unit", aqui não há escolha: todas as
## unidades daquela facção serão atingidas, então já mostra o resultado
## em todas de uma vez.
func begin_aoe_effect_preview(card_data: CardData) -> void:
	var enemy_effects: Array[Dictionary] = []
	var ally_effects: Array[Dictionary] = []

	for effect in card_data.effects:
		match effect.get("target", ""):
			"all_enemies":
				enemy_effects.append(effect)
			"all_allies":
				ally_effects.append(effect)

	if enemy_effects.is_empty() and ally_effects.is_empty():
		return

	for floor_view in floor_views:
		for unit_view in floor_view.get_all_unit_views():
			var effects = enemy_effects if unit_view.unit.faction == Unit.Faction.ENEMY else ally_effects

			if not effects.is_empty():
				unit_view.arm_effect_preview(effects, true)

## Desarma qualquer preview de efeito de unidade, veio ele de
## begin_unit_effect_preview() ou begin_aoe_effect_preview().
func disarm_all_unit_previews() -> void:
	for floor_view in floor_views:
		for unit_view in floor_view.get_all_unit_views():
			unit_view.disarm_effect_preview()

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
		disarm_all_unit_previews()
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
	selected_floor: int = -1,
	selected_position: int = -1
) -> void:
	for effect in card.data.effects:
		effect_system.execute_effect(
			effect,
			selected_unit,
			selected_floor,
			selected_position
		)

	mana.spend(card.data.cost)
	deck.discard(card.data)

	check_battle_result()
