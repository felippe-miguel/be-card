extends Control

## Sandbox de playtest do grid 3x3 (docs/playtest_3x3.md). Ainda sem o
## painel de debug completo da etapa 8 — por enquanto só o necessário
## pra testar cada etapa: spawn livre (etapa 3), disparar o ataque da
## unidade selecionada (etapa 4) e as cartas de reposicionamento (etapa
## 6, implementadas como botões de ação em vez do sistema de Card/Deck/
## Mana — ver docs/playtest_3x3.md seção 9, que não lista Card/Deck/Mana
## entre o que precisa ser reaproveitado).

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
}

@onready var status_label: Label = $Layout/MainColumn/StatusLabel
@onready var attack_button: Button = $Layout/MainColumn/AttackButton
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

var unit_database: UnitDatabase
var battle_database: BattleDatabase

var battle_state: BattleState
var effect_system: EffectSystem

var pending_action: PendingAction = PendingAction.NONE

## Id da UnitData escolhida no painel de spawn — só é relevante enquanto
## pending_action == SPAWN. A facção é decidida pela própria célula
## clicada (grid ALIADOS ou INIMIGOS), não por um seletor separado.
var pending_spawn_unit_id: String = ""

## Última unidade clicada num UnitView (fora de um pending_action que
## espera um clique com outro sentido — ver _on_unit_selected()). Alvo do
## AttackButton e das ações de reposicionamento. Continua válida
## (RefCounted) mesmo depois de morta/removida; is_dead() é checado antes
## de atacar.
var selected_unit: Unit = null

func _ready() -> void:
	unit_database = UnitDatabase.new()
	unit_database.load_units()

	battle_database = BattleDatabase.new()
	battle_database.load_battles()

	var battle_definition = battle_database.battles["test_battle"]

	battle_state = BattleState.new(battle_definition, unit_database)
	effect_system = EffectSystem.new(battle_state)

	setup_floor()
	setup_spawn_panel()
	setup_action_panel()

func setup_floor() -> void:
	var battle_floor = battle_state.battlefield.get_floor(0)

	floor_view.setup(battle_floor.index)
	floor_view.connect_to_floor(battle_floor)
	floor_view.unit_selected.connect(_on_unit_selected)
	floor_view.cell_selected.connect(_on_cell_selected)

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

func setup_action_panel() -> void:
	attack_button.pressed.connect(_on_attack_button_pressed)
	reposition_button.pressed.connect(_on_reposition_button_pressed)
	flank_button.pressed.connect(_on_flank_button_pressed)
	advance_button.pressed.connect(_on_advance_button_pressed)
	retreat_button.pressed.connect(_on_retreat_button_pressed)
	swap_button.pressed.connect(_on_swap_button_pressed)
	frontline_button.pressed.connect(_on_frontline_button_pressed)
	concentration_button.pressed.connect(_on_concentration_button_pressed)
	teleport_button.pressed.connect(_on_teleport_button_pressed)

func _on_spawn_unit_button_pressed(unit_id: String) -> void:
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

func cancel_pending_action() -> void:
	pending_action = PendingAction.NONE
	pending_spawn_unit_id = ""
	update_spawn_status()
	update_action_status()

func get_main_floor() -> BattleFloor:
	return battle_state.battlefield.get_floor(0)

## Clicar numa unidade normalmente só a seleciona (alvo do AttackButton e
## das ações de reposicionamento); durante SWAP/CONCENTRATION o clique
## tem outro sentido (ver comentário do enum PendingAction).
func _on_unit_selected(unit: Unit) -> void:
	match pending_action:
		PendingAction.SWAP:
			var moved = get_main_floor().swap_units(selected_unit, unit)

			if not moved:
				status_label.text = "Troca inválida (facções diferentes ou mesma unidade)."

			cancel_pending_action()
			return

		PendingAction.CONCENTRATION:
			apply_concentration(unit.lane)
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

	status_label.text = "Selecionada: %s | %s | Lane %d | Row %d | Padrão: %s | ATK %d" % [
		unit.name,
		Unit.Faction.keys()[unit.faction],
		unit.lane,
		unit.row,
		unit.attack_pattern,
		unit.attack
	]

	attack_button.disabled = false
	attack_button.text = "Atacar com %s" % unit.name

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

			cancel_pending_action()

		PendingAction.TELEPORT:
			if faction != selected_unit.faction:
				status_label.text = "Teleporte só entre células da mesma facção."
			elif not get_main_floor().move_unit(selected_unit, lane, row):
				status_label.text = "Não deu pra mover pra lá."
			else:
				select_unit(selected_unit)

			cancel_pending_action()

		PendingAction.CONCENTRATION:
			apply_concentration(lane)
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

	cancel_pending_action()

## Aliados na lane, +2 ATK (Concentração — docs/playtest_3x3.md seção 5).
## Nunca afeta inimigos, mesmo que a lane tenha sido escolhida clicando
## numa unidade/célula do lado inimigo.
func apply_concentration(lane: int) -> void:
	var units = get_main_floor().get_lane_units(Unit.Faction.ALLY, lane)

	for unit in units:
		unit.modify_attack(2)

	status_label.text = "Concentração aplicada na Lane %d (%d aliado(s))." % [lane, units.size()]

## Só dispara o ataque da unidade selecionada — nada de fase de combate
## automática ainda (isso é a etapa 8, "executar turno de todos os
## inimigos"). O resultado (quem foi atingido, dano causado) aparece no
## console, e o HP/Block de cada UnitView atingida já atualiza sozinho
## via Unit.changed (mesmo mecanismo de sempre).
func _on_attack_button_pressed() -> void:
	if selected_unit == null:
		return

	if selected_unit.is_dead():
		status_label.text = "A unidade selecionada já está morta."
		return

	battle_state.execute_unit_attack(selected_unit)

func _on_reposition_button_pressed() -> void:
	if selected_unit == null:
		return

	pending_action = PendingAction.REPOSITION
	update_action_status()

func _on_flank_button_pressed() -> void:
	if selected_unit == null:
		return

	pending_action = PendingAction.FLANK
	update_action_status()

## Avançar/Recuar têm direção fixa (Front = row 0 pras duas facções, ver
## docs/ARCHITECTURE.md/playtest_3x3.md — não são espelhadas entre
## aliados/inimigos neste sandbox), então executam na hora, sem esperar
## clique nenhum.
func _on_advance_button_pressed() -> void:
	move_selected_unit_by_row(-1, "Avançar")

func _on_retreat_button_pressed() -> void:
	move_selected_unit_by_row(1, "Recuar")

func move_selected_unit_by_row(row_delta: int, action_name: String) -> void:
	if selected_unit == null:
		return

	var target_row = selected_unit.row + row_delta

	if not get_main_floor().move_unit(selected_unit, selected_unit.lane, target_row):
		status_label.text = "%s: não deu (fora do grid ou célula ocupada)." % action_name
		return

	select_unit(selected_unit)

func _on_swap_button_pressed() -> void:
	if selected_unit == null:
		return

	pending_action = PendingAction.SWAP
	update_action_status()

func _on_teleport_button_pressed() -> void:
	if selected_unit == null:
		return

	pending_action = PendingAction.TELEPORT
	update_action_status()

## Linha de Frente afeta todo mundo na Front na hora — não precisa de
## unidade selecionada nem de clique nenhum.
func _on_frontline_button_pressed() -> void:
	var units = get_main_floor().get_units_for_faction(Unit.Faction.ALLY)
	var affected = 0

	for unit in units:
		if unit.row == 0:
			unit.modify_attack(3)
			affected += 1

	status_label.text = "Linha de Frente aplicada (%d aliado(s) na Front)." % affected

func _on_concentration_button_pressed() -> void:
	pending_action = PendingAction.CONCENTRATION
	update_action_status()
