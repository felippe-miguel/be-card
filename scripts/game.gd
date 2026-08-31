extends Control

## Sandbox de playtest do grid 3x3 (docs/playtest_3x3.md). Duas formas de
## disparar a mesma coisa convivem de propósito: o painel de debug (spawn
## livre, botões de ação, sem custo — bom pra testar rápido) e agora
## também as cartas de verdade (Deck/Mana/hand, com custo e descarte —
## bom pra sentir o jogo "de verdade"). Uma carta de ação (reposicionar/
## flanquear/etc.) arma o MESMO pending_action que o botão de debug
## equivalente armaria; ver pending_card logo abaixo.

## Qualquer clique pendente (numa unidade ou numa célula vazia) só pode
## servir a UM propósito por vez. SPAWN reaproveita pending_spawn_unit_id
## (a unidade escolhida no painel); as demais agem sobre selected_unit.
enum PendingAction {
	NONE,
	SPAWN,
	REPOSITION,      ## Reposicionar — 1 célula ortogonal, em qualquer direção.
	FLANK,           ## Flanquear — lane adjacente, mesma row, +3 ATK.
	SWAP,            ## Troca — clique numa segunda unidade da mesma facção.
	TELEPORT,        ## Teleporte — qualquer célula vazia da própria facção.
	CONCENTRATION,   ## Concentração — clique escolhe a lane-alvo (+2 ATK pros aliados dela).
	EFFECT_UNIT,     ## Cartas de dano/cura/bloqueio com alvo "selected_unit" — clique escolhe o alvo.
}

@onready var turn_label: Label = $Layout/MainColumn/TurnLabel
@onready var run_turn_button: Button = $Layout/MainColumn/GlobalControls/RunTurnButton
@onready var preview_checkbox: CheckBox = $Layout/MainColumn/GlobalControls/PreviewCheckbox
@onready var reset_button: Button = $Layout/MainColumn/GlobalControls/ResetButton
@onready var random_button: Button = $Layout/MainColumn/GlobalControls/RandomButton
@onready var status_label: Label = $Layout/MainColumn/StatusLabel
@onready var attack_button: Button = $Layout/MainColumn/SelectionControls/AttackButton
@onready var remove_button: Button = $Layout/MainColumn/SelectionControls/RemoveButton
@onready var action_status_label: Label = $Layout/MainColumn/ActionPanel/ActionStatusLabel
@onready var reposition_button: Button = $Layout/MainColumn/ActionPanel/ActionButtons/RepositionButton
@onready var flank_button: Button = $Layout/MainColumn/ActionPanel/ActionButtons/FlankButton
@onready var advance_button: Button = $Layout/MainColumn/ActionPanel/ActionButtons/AdvanceButton
@onready var retreat_button: Button = $Layout/MainColumn/ActionPanel/ActionButtons/RetreatButton
@onready var swap_button: Button = $Layout/MainColumn/ActionPanel/ActionButtons/SwapButton
@onready var frontline_button: Button = $Layout/MainColumn/ActionPanel/ActionButtons/FrontlineButton
@onready var concentration_button: Button = $Layout/MainColumn/ActionPanel/ActionButtons/ConcentrationButton
@onready var teleport_button: Button = $Layout/MainColumn/ActionPanel/ActionButtons/TeleportButton
@onready var spawn_status_label: Label = $Layout/SpawnSidebar/SpawnStatusLabel
@onready var unit_buttons: VBoxContainer = $Layout/SpawnSidebar/UnitScroll/UnitButtons
@onready var floor_view: BattleFloorView = $Layout/MainColumn/BattleFloor1
@onready var deck_pile_view: CardPileView = $Layout/MainColumn/BottomBar/DeckPileView
@onready var card_container: Control = $Layout/MainColumn/BottomBar/Cards
@onready var discard_pile_view: CardPileView = $Layout/MainColumn/BottomBar/DiscardPileView
@onready var mana_label: Label = $Layout/MainColumn/BottomBar/ManaLabel

var unit_database: UnitDatabase
var battle_database: BattleDatabase
var card_database: CardDatabase

var battle_state: BattleState
var effect_system: EffectSystem
var deck: Deck
var mana: Mana

const STARTING_HAND_SIZE = 5
const STARTING_MANA = 3
const RANDOM_UNITS_PER_FACTION = 3

## Layout da mão — ver docs/ARCHITECTURE.md (Hand layout). Cards é um
## Control simples posicionado manualmente por layout_hand(), não um
## HBoxContainer, pra poder sobrepor cartas quando a mão não cabe toda
## separada. HAND_CARD_WIDTH deve bater com custom_minimum_size.x do
## card.tscn.
const HAND_CARD_WIDTH = 220.0
const HAND_CARD_GAP = 20.0
const HAND_AREA_WIDTH = 900.0

var pending_action: PendingAction = PendingAction.NONE

## Id da UnitData escolhida no painel de spawn — só é relevante enquanto
## pending_action == SPAWN. A facção é decidida pela própria célula
## clicada (grid ALIADOS ou INIMIGOS), não por um seletor separado.
var pending_spawn_unit_id: String = ""

## Carta jogada aguardando a mesma sequência de clique(s) que o botão de
## debug equivalente pediria (ver PendingAction) — null enquanto a ação
## em curso veio de um botão de debug (grátis, sem carta envolvida).
## Quando a ação resolve com sucesso, gasta mana e descarta a carta (ver
## finish_card_play()); se for cancelada (Esc) ou o clique for inválido,
## a carta só volta ao normal na mão — nada é cobrado.
var pending_card: Card = null

## Última unidade clicada num UnitView (fora de um pending_action que
## espera um clique com outro sentido — ver _on_unit_selected()). Alvo do
## AttackButton e das ações de reposicionamento. Continua válida
## (RefCounted) mesmo depois de morta/removida; is_dead() é checado antes
## de atacar.
var selected_unit: Unit = null

## 1-indexado, só avança quando o debug "executar turno dos inimigos" é
## usado — não é um sistema de turnos de verdade (ver docs/playtest_3x3.md
## seção 8), só o contador que a seção 7 pede pra mostrar.
var current_turn: int = 1

func _ready() -> void:
	unit_database = UnitDatabase.new()
	unit_database.load_units()

	battle_database = BattleDatabase.new()
	battle_database.load_battles()

	card_database = CardDatabase.new()
	card_database.load_cards()

	## Só uma vez: são sinais do próprio floor_view (não do BattleFloor,
	## que é recriado a cada reset — ver _on_reset_button_pressed()), então
	## conectar de novo a cada reset daria erro de "signal already
	## connected".
	floor_view.unit_selected.connect(_on_unit_selected)
	floor_view.cell_selected.connect(_on_cell_selected)
	floor_view.unit_hover_started.connect(_on_unit_hover_started)
	floor_view.unit_hover_ended.connect(_on_unit_hover_ended)

	start_new_battle_state(battle_database.battles["test_battle"])
	setup_deck_and_mana()

	setup_spawn_panel()
	setup_action_panel()
	setup_global_controls()

	update_turn_label()

## Cria (ou recria, no reset) o Deck e a Mana, e compra a mão inicial.
## Deck/Mana são RefCounted recriados do zero a cada chamada (ao
## contrário de floor_view, que é o mesmo node sempre), então conectar
## .changed de novo aqui nunca duplica conexão — cada objeto novo começa
## sem nenhuma.
func setup_deck_and_mana() -> void:
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

func _on_mana_changed() -> void:
	mana_label.text = "Mana: %d/%d" % [mana.current, mana.max_mana]

func _on_deck_changed() -> void:
	render_hand()

	deck_pile_view.set_count(deck.draw_pile.size())
	discard_pile_view.set_count(deck.discard_pile.size())

## Reconstrói os cards visuais da mão a partir de deck.hand — a mão é
## pequena o suficiente para reconstruir por completo a cada mudança.
func render_hand() -> void:
	for child in card_container.get_children():
		child.queue_free()

	## A carta pendente nunca chama Card.set_pending(false) sozinha
	## quando é descartada (seu nó é destruído junto); zera aqui pra
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

## Cartas da esquerda para a direita, sobrepondo-as quando não há espaço
## suficiente pra separá-las por completo (ver docs/ARCHITECTURE.md).
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

## Cria (ou recria, no reset/random) o BattleState a partir de
## battle_definition e prende floor_view a ele. Separado de _ready() pra
## poder ser chamado de novo em _on_reset_button_pressed()/_on_random_
## button_pressed() sem duplicar as conexões dos sinais do próprio
## floor_view (essas são feitas uma única vez acima). battle_definition
## já vem pronta de quem chama — test_battle.json (reset) ou
## BattleDefinition.empty() (random, populado depois por
## spawn_random_units()).
func start_new_battle_state(battle_definition: BattleDefinition) -> void:
	battle_state = BattleState.new(battle_definition, unit_database)
	effect_system = EffectSystem.new(battle_state)

	var battle_floor = battle_state.battlefield.get_floor(0)

	floor_view.setup(battle_floor.index)
	floor_view.connect_to_floor(battle_floor)

	## battle_floor (ao contrário de floor_view) é recriado a cada reset,
	## então essa conexão precisa ser refeita aqui, não em _ready(). Mantém
	## o preview do checkbox em dia com QUALQUER mudança no andar — ver
	## refresh_turn_preview_if_active().
	battle_floor.battlefield_changed.connect(refresh_turn_preview_if_active)

	## O roster inicial (test_battle.json) é populado dentro de
	## BattleState.new() acima, antes da conexão logo acima existir —
	## sem isto, um reset com o checkbox já ligado deixaria o preview
	## defasado (mostrando a batalha anterior) até a próxima mudança.
	refresh_turn_preview_if_active()

## Um botão por UnitData carregada (todo data/units/*.json) — clicar
## arma pending_spawn_unit_id. Não distingue "unidade de aliado" de
## "unidade de inimigo": qualquer id pode ser spawnado em qualquer grid,
## já que este é só um sandbox de posicionamento.
func setup_spawn_panel() -> void:
	var ids = unit_database.units.keys()

	ids.sort()

	for unit_id in ids:
		var unit_data: UnitData = unit_database.units[unit_id]
		var button = Button.new()

		button.text = "%s (ATK %d / HP %d)" % [unit_data.name, unit_data.attack, unit_data.max_hp]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_spawn_unit_button_pressed.bind(unit_id))

		unit_buttons.add_child(button)

	update_spawn_status()

func setup_global_controls() -> void:
	run_turn_button.pressed.connect(_on_run_turn_button_pressed)
	preview_checkbox.toggled.connect(_on_preview_checkbox_toggled)
	reset_button.pressed.connect(_on_reset_button_pressed)
	random_button.pressed.connect(_on_random_button_pressed)

func _on_preview_checkbox_toggled(_pressed: bool) -> void:
	update_turn_preview()

## Mostra, no mesmo formato do preview de efeito de carta (UnitView.
## render_display() — HP/Block coloridos, indicador de morte), o
## resultado de rodar o turno agora mesmo (BattleState.simulate_full_
## turn(), que não mexe no estado real). Uma unidade ausente das
## previsões (ver simulate_full_turn()) é tratada como "vai morrer".
func update_turn_preview() -> void:
	if not preview_checkbox.button_pressed:
		clear_turn_preview()
		return

	var predictions = battle_state.simulate_full_turn()

	for view in floor_view.get_all_unit_views():
		var prediction = predictions.get(view.unit)

		if prediction == null:
			view.render_display(0, 0)
		else:
			view.render_display(prediction.hp, prediction.block)

func clear_turn_preview() -> void:
	for view in floor_view.get_all_unit_views():
		view.update_display()

## Chamado a cada mudança no andar (BattleFloor.battlefield_changed) —
## só recalcula o preview se o checkbox estiver ligado; do contrário não
## faz nada (nem existe preview pra manter em dia).
func refresh_turn_preview_if_active() -> void:
	if preview_checkbox.button_pressed:
		update_turn_preview()

func setup_action_panel() -> void:
	attack_button.pressed.connect(_on_attack_button_pressed)
	remove_button.pressed.connect(_on_remove_button_pressed)
	reposition_button.pressed.connect(_on_reposition_button_pressed)
	flank_button.pressed.connect(_on_flank_button_pressed)
	advance_button.pressed.connect(_on_advance_button_pressed)
	retreat_button.pressed.connect(_on_retreat_button_pressed)
	swap_button.pressed.connect(_on_swap_button_pressed)
	frontline_button.pressed.connect(_on_frontline_button_pressed)
	concentration_button.pressed.connect(_on_concentration_button_pressed)
	teleport_button.pressed.connect(_on_teleport_button_pressed)

## Nenhum botão/carta que arma um pending_action pode pisar num que já
## esteja em andamento (de outro botão OU de uma carta — ver
## pending_card) — sem isso, o pending_card de uma ação em curso ficaria
## "órfão", associado ao tipo de ação errado.
func can_start_new_pending_action() -> bool:
	if pending_action == PendingAction.NONE:
		return true

	status_label.text = "Termine a ação em andamento antes de começar outra."

	return false

func _on_spawn_unit_button_pressed(unit_id: String) -> void:
	if not can_start_new_pending_action():
		return

	pending_action = PendingAction.SPAWN
	pending_spawn_unit_id = unit_id
	update_spawn_status()
	update_action_status()

func update_spawn_status() -> void:
	if pending_action != PendingAction.SPAWN:
		spawn_status_label.text = "Clique numa unidade abaixo para escolher o que spawnar."
		return

	var unit_data: UnitData = unit_database.units.get(pending_spawn_unit_id)

	spawn_status_label.text = "Spawnando %s — clique numa célula vazia (Esc cancela)." % unit_data.name

## Descreve a espera de clique de cada pending_action, quando houver uma
## ativa — util pra saber o que vai acontecer no próximo clique sem
## precisar advinhar.
func update_action_status() -> void:
	match pending_action:
		PendingAction.REPOSITION:
			action_status_label.text = "Reposicionar %s — clique numa célula vazia adjacente (Esc cancela)." % selected_unit.name
		PendingAction.FLANK:
			action_status_label.text = "Flanquear %s — clique numa célula vazia na lane adjacente, mesma row (Esc cancela)." % selected_unit.name
		PendingAction.SWAP:
			action_status_label.text = "Troca de %s — clique noutro aliado da mesma facção (Esc cancela)." % selected_unit.name
		PendingAction.TELEPORT:
			action_status_label.text = "Teleportar %s — clique em qualquer célula vazia da mesma facção (Esc cancela)." % selected_unit.name
		PendingAction.CONCENTRATION:
			action_status_label.text = "Concentração — clique numa unidade ou célula pra escolher a lane (Esc cancela)."
		PendingAction.EFFECT_UNIT:
			action_status_label.text = "%s — clique na unidade alvo (passe o mouse pra ver o preview; Esc cancela)." % pending_card.data.name
		_:
			action_status_label.text = "Selecione uma unidade e escolha uma ação abaixo."

## Esc cancela qualquer ação pendente (spawn ou reposicionamento), mesmo
## padrão usado no resto do projeto para cancelar uma carta pendente (ver
## docs/ARCHITECTURE.md).
func _input(event: InputEvent) -> void:
	if pending_action == PendingAction.NONE:
		return

	if event.is_action_pressed("ui_cancel"):
		cancel_pending_action()
		get_viewport().set_input_as_handled()

## Encerra o pending_action atual, com ou sem sucesso — quem já jogou a
## carta correspondente com sucesso (ver finish_card_play()) chama isso
## DEPOIS de gastar a mana/descartar; aqui só sobra "devolver a carta ao
## normal visualmente" pros casos de cancelamento/clique inválido, já que
## nesses ela nunca chega a ser descartada.
func cancel_pending_action() -> void:
	if pending_card != null:
		pending_card.set_pending(false)
		pending_card = null

	## Sem custo checar: é um no-op nas UnitViews que não têm nenhum
	## preview armado (só EFFECT_UNIT arma algum). disarm_effect_preview()
	## força update_display() (valores reais) nas unidades que tinham
	## preview de carta armado — por isso o refresh_turn_preview_if_
	## active() logo abaixo, senão essas unidades ficariam mostrando o
	## valor real "preso" em vez do preview do turno, mesmo com o
	## checkbox ligado (o bug relatado: preview "para de funcionar" depois
	## de cancelar uma carta ou clicar um alvo inválido).
	disarm_all_unit_effect_previews()

	pending_action = PendingAction.NONE
	pending_spawn_unit_id = ""
	update_spawn_status()
	update_action_status()
	refresh_turn_preview_if_active()

func get_main_floor() -> BattleFloor:
	return battle_state.battlefield.get_floor(0)

## Clicar numa unidade normalmente só a seleciona (alvo do AttackButton e
## das ações de reposicionamento); durante SWAP/CONCENTRATION o clique
## tem outro sentido (ver comentário do enum PendingAction).
func _on_unit_selected(unit: Unit) -> void:
	match pending_action:
		PendingAction.SWAP:
			var moved = get_main_floor().swap_units(selected_unit, unit)
			var card = pending_card

			if not moved:
				status_label.text = "Troca inválida (facções diferentes ou mesma unidade)."
			elif card != null:
				finish_card_play(card)

			cancel_pending_action()
			return

		PendingAction.CONCENTRATION:
			apply_concentration(unit.lane)

			if pending_card != null:
				finish_card_play(pending_card)

			cancel_pending_action()
			return

		PendingAction.EFFECT_UNIT:
			var effect = pending_card.data.effects[0]
			var card = pending_card

			if not effect_system.can_target_selected_unit(effect, unit):
				status_label.text = "Alvo inválido para %s." % card.data.name
			else:
				effect_system.execute_effect(effect, unit)
				finish_card_play(card)

			cancel_pending_action()
			return

		## Clicar numa unidade (em vez da célula vazia esperada) enquanto
		## essas ações aguardam um alvo desiste da ação, em vez de mover a
		## unidade errada — só troca a seleção.
		PendingAction.REPOSITION, PendingAction.FLANK, PendingAction.TELEPORT:
			cancel_pending_action()

	select_unit(unit)

func select_unit(unit: Unit) -> void:
	selected_unit = unit

	status_label.text = "Selecionada: %s | %s | Lane %d | Row %d | HP %d/%d | ATK %d | Padrão: %s" % [
		unit.name,
		Unit.Faction.keys()[unit.faction],
		unit.lane,
		unit.row,
		unit.hp,
		unit.max_hp,
		unit.attack,
		unit.attack_pattern
	]

	attack_button.disabled = false
	attack_button.text = "Atacar com %s" % unit.name
	remove_button.disabled = false

func update_turn_label() -> void:
	turn_label.text = "Turno: %d" % current_turn

func clear_selection() -> void:
	selected_unit = null
	attack_button.disabled = true
	attack_button.text = "Atacar (selecione uma unidade)"
	remove_button.disabled = true

## Hover de combate: destaca em vermelho quem seria atingido pelo padrão
## de ataque de unit, em verde quem recebe a aura dela (só o Guardião tem
## uma, por enquanto), e mostra a explicação do padrão no painel ao lado
## do grid aliado (ver show_pattern_info()). Independe de seleção/
## pending_action — funciona sempre, mesmo com uma ação em andamento.
func _on_unit_hover_started(unit: Unit) -> void:
	for target in battle_state.target_system.get_pattern_attack_targets(unit):
		var target_view = floor_view.get_unit_view(target)

		if target_view != null:
			target_view.set_highlight(UnitView.TARGET_HIGHLIGHT_COLOR)

	if unit.aura_adjacent_ally_max_hp_bonus > 0:
		for neighbor in get_main_floor().get_adjacent_units(unit.faction, unit.lane, unit.row):
			var neighbor_view = floor_view.get_unit_view(neighbor)

			if neighbor_view != null:
				neighbor_view.set_highlight(UnitView.BUFF_HIGHLIGHT_COLOR)

	show_pattern_info(unit)

## Preenche o painel de explicação (título + regra do padrão de ataque,
## mais a aura, se houver) — o texto em si vem de
## TargetSystem.describe_pattern(), que fica perto da própria
## implementação de cada padrão.
func show_pattern_info(unit: Unit) -> void:
	var title = "%s (%s) — %s" % [
		unit.name,
		Unit.Faction.keys()[unit.faction],
		unit.attack_pattern
	]
	var body = battle_state.target_system.describe_pattern(unit.attack_pattern, unit.attack_pattern_count)

	if unit.aura_adjacent_ally_max_hp_bonus > 0:
		body += "\n\nPassiva: aliados ortogonalmente adjacentes recebem +%d de HP máximo enquanto esta unidade estiver viva e posicionada aqui." % unit.aura_adjacent_ally_max_hp_bonus

	floor_view.set_pattern_info(title, body)

## Limpa todo highlight, sem tentar adivinhar quais views foram
## destacadas por _on_unit_hover_started() — mais simples e à prova de
## unidades que morreram/sumiram enquanto o mouse ainda estava em cima.
func _on_unit_hover_ended(_unit: Unit) -> void:
	for view in floor_view.get_all_unit_views():
		view.clear_highlight()

	floor_view.clear_pattern_info()

## Só é chamado com uma célula VAZIA (ver BattleFloorView.cell_selected).
func _on_cell_selected(faction: Unit.Faction, lane: int, row: int) -> void:
	match pending_action:
		PendingAction.SPAWN:
			spawn_unit_at(faction, lane, row)

		PendingAction.REPOSITION:
			if faction != selected_unit.faction or not is_orthogonally_adjacent(selected_unit.lane, selected_unit.row, lane, row):
				status_label.text = "Célula inválida para Reposicionar (precisa ser adjacente, mesma facção)."
			elif not get_main_floor().move_unit(selected_unit, lane, row):
				status_label.text = "Não deu pra mover pra lá."
			else:
				select_unit(selected_unit)

				if pending_card != null:
					finish_card_play(pending_card)

			cancel_pending_action()

		PendingAction.FLANK:
			var same_row = row == selected_unit.row
			var adjacent_lane = absi(lane - selected_unit.lane) == 1

			if faction != selected_unit.faction or not same_row or not adjacent_lane:
				status_label.text = "Célula inválida para Flanquear (precisa ser lane vizinha, mesma row)."
			elif not get_main_floor().move_unit(selected_unit, lane, row):
				status_label.text = "Não deu pra mover pra lá."
			else:
				selected_unit.modify_attack(3)
				select_unit(selected_unit)

				if pending_card != null:
					finish_card_play(pending_card)

			cancel_pending_action()

		PendingAction.TELEPORT:
			if faction != selected_unit.faction:
				status_label.text = "Teleporte só entre células da mesma facção."
			elif not get_main_floor().move_unit(selected_unit, lane, row):
				status_label.text = "Não deu pra mover pra lá."
			else:
				select_unit(selected_unit)

				if pending_card != null:
					finish_card_play(pending_card)

			cancel_pending_action()

		PendingAction.CONCENTRATION:
			apply_concentration(lane)

			if pending_card != null:
				finish_card_play(pending_card)

			cancel_pending_action()

func is_orthogonally_adjacent(lane_a: int, row_a: int, lane_b: int, row_b: int) -> bool:
	var lane_diff = absi(lane_a - lane_b)
	var row_diff = absi(row_a - row_b)

	return (lane_diff + row_diff) == 1

func spawn_unit_at(faction: Unit.Faction, lane: int, row: int) -> void:
	var unit = battle_state.create_unit(pending_spawn_unit_id, faction)

	if unit == null:
		cancel_pending_action()
		return

	if not get_main_floor().place_unit_at(unit, lane, row):
		print("Célula ocupada!")
	elif pending_card != null:
		finish_card_play(pending_card)

	cancel_pending_action()

## Aliados na lane, +2 ATK (Concentração — docs/playtest_3x3.md seção 5).
## Nunca afeta inimigos, mesmo que a lane tenha sido escolhida clicando
## numa unidade/célula do lado inimigo.
func apply_concentration(lane: int) -> void:
	var units = get_main_floor().get_lane_units(Unit.Faction.ALLY, lane)

	for unit in units:
		unit.modify_attack(2)

	status_label.text = "Concentração aplicada na Lane %d (%d aliado(s))." % [lane, units.size()]

## Jogar uma carta arma o MESMO pending_action que o botão de debug
## equivalente armaria (ver enum PendingAction) — a diferença é só o
## custo de mana e o descarte ao resolver (finish_card_play()), feitos
## via pending_card. "advance"/"retreat"/"frontline" não têm uma etapa de
## clique própria (mesma lógica dos botões de debug correspondentes),
## então resolvem e descartam na hora.
func _on_card_played(card: Card) -> void:
	if not can_start_new_pending_action():
		return

	if not mana.can_afford(card.data.cost):
		status_label.text = "Mana insuficiente para jogar %s." % card.data.name
		return

	var effect = card.data.effects[0] if not card.data.effects.is_empty() else {}
	var action_type: String = effect.get("type", "")

	match action_type:
		"summon":
			pending_spawn_unit_id = card.data.get_summon_unit_id()
			pending_action = PendingAction.SPAWN
			begin_pending_card(card)

		"reposition":
			if require_selected_unit_for_card(card):
				pending_action = PendingAction.REPOSITION
				begin_pending_card(card)

		"flank":
			if require_selected_unit_for_card(card):
				pending_action = PendingAction.FLANK
				begin_pending_card(card)

		"teleport":
			if require_selected_unit_for_card(card):
				pending_action = PendingAction.TELEPORT
				begin_pending_card(card)

		"swap":
			if require_selected_unit_for_card(card):
				pending_action = PendingAction.SWAP
				begin_pending_card(card)

		"concentration":
			pending_action = PendingAction.CONCENTRATION
			begin_pending_card(card)

		"advance":
			if require_selected_unit_for_card(card) and resolve_move_by_row(-1, "Avançar"):
				finish_card_play(card)

		"retreat":
			if require_selected_unit_for_card(card) and resolve_move_by_row(1, "Recuar"):
				finish_card_play(card)

		"frontline":
			apply_frontline()
			finish_card_play(card)

		"damage", "heal", "block":
			begin_effect_card(card, effect)

		_:
			status_label.text = "Carta sem ação reconhecida: %s" % action_type

## Cartas de dano/cura/bloqueio. "all_enemies"/"all_allies" resolvem na
## hora (mesmo padrão de Linha de Frente); "selected_unit" pede um clique
## de alvo (EFFECT_UNIT) — ao contrário das cartas de reposicionamento,
## aqui o clique ESCOLHE o alvo, não exige uma unidade já selecionada
## antes de jogar a carta.
func begin_effect_card(card: Card, effect: Dictionary) -> void:
	match effect.get("target", ""):
		"selected_unit":
			pending_action = PendingAction.EFFECT_UNIT
			begin_pending_card(card)
			arm_effect_preview_for_card(effect)

		"all_enemies", "all_allies":
			effect_system.execute_effect(effect)
			finish_card_play(card)

		_:
			status_label.text = "Carta com alvo desconhecido: %s" % card.data.name

## Mostra, ao passar o mouse (ver UnitView.arm_effect_preview()), o
## resultado hipotético do efeito em cada unidade elegível como alvo —
## só nas que EffectSystem.can_target_selected_unit() aceitaria de
## verdade, a mesma checagem usada pelo clique real.
func arm_effect_preview_for_card(effect: Dictionary) -> void:
	var effects: Array[Dictionary] = []

	effects.append(effect)

	for view in floor_view.get_all_unit_views():
		if effect_system.can_target_selected_unit(effect, view.unit):
			view.arm_effect_preview(effects)

func disarm_all_unit_effect_previews() -> void:
	for view in floor_view.get_all_unit_views():
		view.disarm_effect_preview()

## Precondição de toda carta de reposicionamento/troca/teleporte: o
## sandbox pede a mesma coisa que os botões de debug — selecione a
## unidade no campo primeiro, depois jogue a carta.
func require_selected_unit_for_card(card: Card) -> bool:
	if selected_unit != null and not selected_unit.is_dead():
		return true

	status_label.text = "Selecione uma unidade no campo antes de jogar %s." % card.data.name

	return false

## Entra no mesmo estado de espera de clique que o botão de debug
## equivalente armaria, só que com uma carta anexada — ver pending_card.
func begin_pending_card(card: Card) -> void:
	pending_card = card
	card.set_pending(true)

	update_action_status()
	update_spawn_status()

## Gasta a mana e descarta a carta — chamado só nos caminhos de sucesso
## (ver os "if pending_card != null" espalhados por _on_cell_selected()/
## _on_unit_selected(), e diretamente nos casos imediatos acima).
func finish_card_play(card: Card) -> void:
	mana.spend(card.data.cost)
	deck.discard(card.data)

	## A maioria dos efeitos de carta já dispara battlefield_changed
	## sozinha (dano/cura/bloqueio/ATK emitem Unit.changed; mover/invocar/
	## trocar mexem direto no BattleFloor) — mas chamar aqui também
	## garante que TODA carta jogada recalcula o preview do turno, sem
	## depender de cada efeito lembrar de propagar a mudança certinho.
	refresh_turn_preview_if_active()

## Dispara só o ataque da unidade selecionada (aliada ou inimiga) — para
## resolver o turno inteiro de uma vez, ver _on_run_turn_button_pressed().
## O resultado (quem foi atingido, dano causado) aparece no console, e o
## HP/Block de cada UnitView atingida já atualiza sozinho via
## Unit.changed (mesmo mecanismo de sempre).
func _on_attack_button_pressed() -> void:
	if selected_unit == null:
		return

	if selected_unit.is_dead():
		status_label.text = "A unidade selecionada já está morta."
		return

	battle_state.execute_unit_attack(selected_unit)

func _on_reposition_button_pressed() -> void:
	if selected_unit == null or not can_start_new_pending_action():
		return

	pending_action = PendingAction.REPOSITION
	update_action_status()

func _on_flank_button_pressed() -> void:
	if selected_unit == null or not can_start_new_pending_action():
		return

	pending_action = PendingAction.FLANK
	update_action_status()

## Avançar/Recuar têm direção fixa (Front = row 0 pras duas facções, ver
## docs/ARCHITECTURE.md/playtest_3x3.md — não são espelhadas entre
## aliados/inimigos neste sandbox), então executam na hora, sem esperar
## clique nenhum.
func _on_advance_button_pressed() -> void:
	if selected_unit != null:
		resolve_move_by_row(-1, "Avançar")

func _on_retreat_button_pressed() -> void:
	if selected_unit != null:
		resolve_move_by_row(1, "Recuar")

## Move selected_unit row_delta linhas (mesma lane). Retorna se moveu de
## fato — usado tanto pelos botões de debug (ignoram o retorno) quanto
## pelas cartas Avançar/Recuar (só descartam a carta se isto for true).
func resolve_move_by_row(row_delta: int, action_name: String) -> bool:
	var target_row = selected_unit.row + row_delta

	if not get_main_floor().move_unit(selected_unit, selected_unit.lane, target_row):
		status_label.text = "%s: não deu (fora do grid ou célula ocupada)." % action_name
		return false

	select_unit(selected_unit)

	return true

func _on_swap_button_pressed() -> void:
	if selected_unit == null or not can_start_new_pending_action():
		return

	pending_action = PendingAction.SWAP
	update_action_status()

func _on_teleport_button_pressed() -> void:
	if selected_unit == null or not can_start_new_pending_action():
		return

	pending_action = PendingAction.TELEPORT
	update_action_status()

## Linha de Frente afeta todo mundo na Front na hora — não precisa de
## unidade selecionada nem de clique nenhum.
func _on_frontline_button_pressed() -> void:
	apply_frontline()

func apply_frontline() -> void:
	var units = get_main_floor().get_units_for_faction(Unit.Faction.ALLY)
	var affected = 0

	for unit in units:
		if unit.row == 0:
			unit.modify_attack(3)
			affected += 1

	status_label.text = "Linha de Frente aplicada (%d aliado(s) na Front)." % affected

func _on_concentration_button_pressed() -> void:
	if not can_start_new_pending_action():
		return

	pending_action = PendingAction.CONCENTRATION
	update_action_status()

func _on_remove_button_pressed() -> void:
	if selected_unit == null:
		return

	var removed_name = selected_unit.name

	get_main_floor().remove_unit(selected_unit)
	clear_selection()

	status_label.text = "%s removida do campo." % removed_name

## Resolve o turno inteiro (BattleState.execute_full_turn): inimigos
## atacam, depois os aliados — debug pedido pela seção 7 do documento.
## Também reabastece a mana e renova a mão inteira (descarta tudo que
## sobrou e compra STARTING_HAND_SIZE cartas novas, em vez de só somar
## mais algumas às que já estavam na mão) — "Rodar turno" faz tudo de
## uma vez neste sandbox, já que não há mais uma fase separada de ação
## do jogador vs. combate.
func _on_run_turn_button_pressed() -> void:
	battle_state.execute_full_turn()

	current_turn += 1
	update_turn_label()

	mana.refill()
	deck.discard_hand()
	deck.draw(STARTING_HAND_SIZE)

	status_label.text = "Turno resolvido — inimigos e aliados atacaram (turno %d)." % current_turn

## Recria o BattleState do zero a partir de test_battle.json, descartando
## qualquer spawn/movimento/dano feito até aqui — cancela qualquer ação
## pendente e limpa a seleção antes, pra não referenciar uma Unit de uma
## batalha que não existe mais. Também recria Deck/Mana do zero (nova
## mão inicial, mana cheia).
func _on_reset_button_pressed() -> void:
	cancel_pending_action()
	clear_selection()

	start_new_battle_state(battle_database.battles["test_battle"])
	setup_deck_and_mana()

	current_turn = 1
	update_turn_label()

	status_label.text = "Combate resetado."

## Igual "Resetar combate" (baralho novo embaralhado, mão inicial, mana
## cheia, turno 1), mas troca a formação fixa de test_battle.json por um
## andar vazio (BattleDefinition.empty()) e sorteia RANDOM_UNITS_PER_
## FACTION unidades pra cada lado, em células aleatórias.
func _on_random_button_pressed() -> void:
	cancel_pending_action()
	clear_selection()

	start_new_battle_state(BattleDefinition.empty())
	setup_deck_and_mana()

	spawn_random_units(Unit.Faction.ALLY, RANDOM_UNITS_PER_FACTION)
	spawn_random_units(Unit.Faction.ENEMY, RANDOM_UNITS_PER_FACTION)

	current_turn = 1
	update_turn_label()

	status_label.text = "Batalha aleatória gerada."

## Sorteia count unidades (qualquer id de data/units/*.json, sem
## restrição de facção — mesma liberdade do painel de spawn) em células
## vazias distintas, sorteadas entre as 9 do grid dessa facção.
func spawn_random_units(faction: Unit.Faction, count: int) -> void:
	var battle_floor = get_main_floor()
	var cells: Array[Vector2i] = []

	for row in range(BattleFloor.ROWS):
		for lane in range(BattleFloor.LANES):
			cells.append(Vector2i(lane, row))

	cells.shuffle()

	var unit_ids = unit_database.units.keys()

	for i in range(min(count, cells.size())):
		var unit_id: String = unit_ids[randi() % unit_ids.size()]
		var unit = battle_state.create_unit(unit_id, faction)

		if unit != null:
			battle_floor.place_unit_at(unit, cells[i].x, cells[i].y)
