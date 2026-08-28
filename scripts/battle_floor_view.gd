class_name BattleFloorView
extends PanelContainer

@onready var enemy_container: HBoxContainer = $Layout/HBoxContainer/EnemyContainer
@onready var ally_container: HBoxContainer = $Layout/HBoxContainer/AllyArea/AllyContainer

## Zonas de hover invisíveis, em ordem fixa da esquerda para a direita na
## tela — nunca são movidas ou recriadas. Ficam sobrepostas a
## ally_container (mesmo retângulo) só para detectar mouse/clique; o
## conteúdo visual embaixo (UnitViews reais + fantasma) pode ser
## livremente reordenado sem afetar essa detecção. Isso evita o problema
## de "a unidade sob o mouse se move e dispara hover/unhover em cascata"
## que existiria se o hover fosse detectado nos próprios UnitViews.
@onready var ally_hover_zones: Array[Button] = [
	$Layout/HBoxContainer/AllyArea/AllyHoverZones/Zone0,
	$Layout/HBoxContainer/AllyArea/AllyHoverZones/Zone1,
	$Layout/HBoxContainer/AllyArea/AllyHoverZones/Zone2,
]

const EMPTY_SLOT_COLOR = Color(1, 1, 1, 0.35)
const INVISIBLE_COLOR = Color(1, 1, 1, 0)
const GHOST_COLOR = Color(0.7, 1.0, 0.7, 0.85)

var floor_index: int
var battle_floor: BattleFloor

## Um "spacer" por slot sem unidade, em cada facção — sempre presentes,
## com a mesma largura de uma UnitView real (size_flags_horizontal =
## EXPAND_FILL), para que nenhum dos dois lados precise mudar de tamanho
## conforme unidades entram/saem (ou, no caso aliado, ao entrar/sair do
## modo de posicionamento). Ficam invisíveis o tempo todo, exceto os
## aliados durante uma invocação pendente (begin_placement()/
## end_placement() só alternam a aparência "Vazio", sem criar/destruir
## nada) — não existe UI de posicionamento para inimigos.
var ally_spacer_views: Array[Button] = []
var enemy_spacer_views: Array[Button] = []

## Só existem/valem durante uma invocação pendente (ver begin_placement()).
## Nada no jogo é afetado até o jogador clicar uma zona e o efeito da
## carta de fato criar a unidade.
var placement_active: bool = false
var pending_unit_data: UnitData = null
var ghost_view: Button = null

signal selected(floor_view: BattleFloorView)
signal unit_selected(unit: Unit)
signal position_selected(floor_index: int, position_index: int)

func setup(index: int) -> void:
	floor_index = index

func _ready() -> void:
	for zone_index in range(ally_hover_zones.size()):
		ally_hover_zones[zone_index].pressed.connect(_on_zone_pressed.bind(zone_index))
		ally_hover_zones[zone_index].mouse_entered.connect(_on_zone_hovered.bind(zone_index))
		ally_hover_zones[zone_index].mouse_exited.connect(_on_zone_unhovered)

## Traduz a zona de tela ativada (0 = mais à esquerda .. 2 = mais à
## direita) para o índice de inserção no array de aliados (0 = vira a
## nova frente, empurrando as demais; real_count = vira o novo fim, ou
## seja, a nova retaguarda). As unidades reais ficam ancoradas na borda
## mais afastada do centro (esquerda, para aliados) e crescem em direção
## ao centro conforme mais são adicionadas — por isso essa tradução
## depende de quantas já existem, e não pode ser fixada uma vez em
## _ready() como antes; é recalculada a cada hover/clique.
func zone_index_to_insert_position(zone_index: int) -> int:
	var real_count = battle_floor.get_units_for_faction(Unit.Faction.ALLY).size()

	return clampi(real_count - zone_index, 0, real_count)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			selected.emit(self)

func connect_to_floor(battleFloor: BattleFloor) -> void:
	battle_floor = battleFloor
	battleFloor.unit_added.connect(_on_unit_added)
	battleFloor.unit_removed.connect(_on_unit_removed)

	## Um andar que já começa sem nenhuma unidade de uma facção (ex: os 3
	## andares hoje, do lado inimigo, já que quem povoa é o EnemySpawner)
	## nunca passa pelo create_unit_view() em Game.setup_units(), então
	## nunca chamaria sync_slots() sozinho — sem isso, o primeiro
	## add_unit()/insert_unit_at() nele encontraria a lista de spacers
	## vazia. Seguro chamar aqui só quando não há unidade real ainda
	## (nenhuma UnitView pra achar); o caso com unidades pré-existentes é
	## resolvido pelo próprio create_unit_view() logo a seguir.
	if battle_floor.get_units_for_faction(Unit.Faction.ALLY).is_empty():
		sync_slots(Unit.Faction.ALLY)

	if battle_floor.get_units_for_faction(Unit.Faction.ENEMY).is_empty():
		sync_slots(Unit.Faction.ENEMY)

func _on_unit_added(unit: Unit) -> void:
	create_unit_view(unit)

func _on_unit_removed(unit: Unit) -> void:
	var container = get_container_for_faction(unit.faction)

	for child in container.get_children():
		var unit_view = child as UnitView

		if unit_view != null and unit_view.unit == unit:
			container.remove_child(unit_view)
			unit_view.queue_free()
			break

	sync_slots(unit.faction)

## Cria a UnitView e a mantém com a mesma largura de sempre (1/3 da área)
## para as duas facções — nunca muda ao entrar em modo de posicionamento
## nem conforme unidades são adicionadas/removidas, só o que está ao redor
## dela muda.
func create_unit_view(unit: Unit) -> void:
	var unit_view  = preload("res://scenes/unit_view.tscn").instantiate()
	var container = get_container_for_faction(unit.faction)

	container.add_child(unit_view)

	unit_view.setup(unit)
	unit_view.selected.connect(_on_unit_selected)
	unit_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	sync_slots(unit.faction)

func get_container_for_faction(faction: Unit.Faction) -> HBoxContainer:
	if faction == Unit.Faction.ENEMY:
		return enemy_container

	return ally_container

func get_spacer_views_for_faction(faction: Unit.Faction) -> Array[Button]:
	if faction == Unit.Faction.ENEMY:
		return enemy_spacer_views

	return ally_spacer_views

func _on_unit_selected(unit: Unit) -> void:
	unit_selected.emit(unit)

## Garante exatamente battle_floor.max_units elementos no container da
## facção (UnitViews reais + spacers) e os reordena. Chamada sempre que
## uma unidade é adicionada/removida, de qualquer facção.
func sync_slots(faction: Unit.Faction) -> void:
	var container = get_container_for_faction(faction)
	var spacer_views = get_spacer_views_for_faction(faction)
	var real_count = battle_floor.get_units_for_faction(faction).size()
	var needed_spacers = battle_floor.max_units - real_count

	while spacer_views.size() < needed_spacers:
		spacer_views.append(create_spacer(container))

	while spacer_views.size() > needed_spacers:
		spacer_views.pop_back().queue_free()

	layout_slots(faction)

func create_spacer(container: HBoxContainer) -> Button:
	var spacer = Button.new()

	spacer.custom_minimum_size = Vector2(160, 80)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.disabled = true
	spacer.text = "Vazio"
	spacer.modulate = INVISIBLE_COLOR

	container.add_child(spacer)

	return spacer

## Posiciona os slots da facção (unidades reais + spacers) em ordem
## visual correta. As unidades reais ficam ancoradas na borda mais
## afastada do centro (esquerda para aliados, direita para inimigos) e
## ocupam um bloco contínuo que cresce em direção ao centro conforme mais
## são adicionadas — a frente (position_index 0) é sempre a mais central
## dentre as presentes, não uma coluna fixa. Os spacers preenchem o
## restante, do lado mais central. É a disposição "em repouso"; para
## aliados, também serve de base antes de qualquer preview de invocação
## (sem fantasma, tamanho normal).
func layout_slots(faction: Unit.Faction) -> void:
	var container = get_container_for_faction(faction)
	var spacer_views = get_spacer_views_for_faction(faction)
	var current_units = battle_floor.get_units_for_faction(faction)
	var real_count = current_units.size()
	var is_ally = faction == Unit.Faction.ALLY

	for unit in current_units:
		var visual_index = (
			(real_count - 1 - unit.position_index) if is_ally
			else (battle_floor.max_units - real_count + unit.position_index)
		)
		var view = find_unit_view(container, unit)

		view.visible = true
		container.move_child(view, visual_index)

	for i in range(spacer_views.size()):
		var visual_index = (real_count + i) if is_ally else i

		spacer_views[i].visible = true
		container.move_child(spacer_views[i], visual_index)

## Ativa a escolha de slot de invocação (frente/meio/fundo) para
## unit_data, se este andar ainda tiver espaço para mais um aliado.
## Chamado pelo Game quando uma carta de invocação fica pendente.
func begin_placement(unit_data: UnitData) -> void:
	pending_unit_data = unit_data
	placement_active = battle_floor.can_add_unit(Unit.Faction.ALLY)

	for zone in ally_hover_zones:
		zone.mouse_filter = MOUSE_FILTER_STOP if placement_active else MOUSE_FILTER_IGNORE

	if not placement_active:
		return

	for spacer in ally_spacer_views:
		spacer.modulate = EMPTY_SLOT_COLOR

	layout_slots(Unit.Faction.ALLY)

func end_placement() -> void:
	placement_active = false
	pending_unit_data = null

	for zone in ally_hover_zones:
		zone.mouse_filter = MOUSE_FILTER_IGNORE

	clear_ghost_view()

	for spacer in ally_spacer_views:
		spacer.modulate = INVISIBLE_COLOR

	layout_slots(Unit.Faction.ALLY)

func _on_zone_pressed(zone_index: int) -> void:
	if not placement_active:
		return

	position_selected.emit(floor_index, zone_index_to_insert_position(zone_index))

func _on_zone_hovered(zone_index: int) -> void:
	if not placement_active:
		return

	preview_arrangement(zone_index_to_insert_position(zone_index))

func _on_zone_unhovered() -> void:
	if not placement_active:
		return

	if ghost_view != null:
		ghost_view.visible = false

	layout_slots(Unit.Faction.ALLY)

func ensure_ghost_view() -> void:
	if ghost_view != null:
		return

	ghost_view = Button.new()

	ghost_view.custom_minimum_size = Vector2(160, 80)
	ghost_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ghost_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_view.disabled = true
	ghost_view.modulate = GHOST_COLOR

	ally_container.add_child(ghost_view)

func clear_ghost_view() -> void:
	if ghost_view == null:
		return

	ghost_view.queue_free()
	ghost_view = null

func find_unit_view(container: HBoxContainer, unit: Unit) -> UnitView:
	for child in container.get_children():
		var unit_view = child as UnitView

		if unit_view != null and unit_view.unit == unit:
			return unit_view

	return null

## Simula (sem mexer no BattleFloor de verdade) inserir pending_unit_data
## na posição passada e reorganiza de fato os elementos visuais dentro de
## ally_container para mostrar o resultado: o bloco ocupado (unidades
## reais + fantasma) continua ancorado na borda esquerda, crescendo em
## direção ao centro — mesma regra de layout_slots(), só que contando o
## fantasma como mais um ocupante. A detecção de hover que chamou esta
## função (ally_hover_zones) não faz parte desse reflow, então nada aqui
## afeta o que o mouse está sobre.
func preview_arrangement(target_position: int) -> void:
	var current_units = battle_floor.get_units_for_faction(Unit.Faction.ALLY)
	var real_count = current_units.size()
	var clamped_position = clampi(target_position, 0, real_count)

	ensure_ghost_view()

	var arrangement: Array = []
	arrangement.append_array(current_units)
	arrangement.insert(clamped_position, ghost_view)

	var occupied_count = arrangement.size()

	for slot in range(occupied_count):
		var entry = arrangement[slot]
		var visual_index = (occupied_count - 1) - slot
		var element = ghost_view if entry == ghost_view else find_unit_view(ally_container, entry)

		element.visible = true
		ally_container.move_child(element, visual_index)

	var spacer_count = battle_floor.max_units - occupied_count

	for i in range(ally_spacer_views.size()):
		var spacer_visible = i < spacer_count

		ally_spacer_views[i].visible = spacer_visible

		if spacer_visible:
			ally_container.move_child(ally_spacer_views[i], occupied_count + i)

	ghost_view.text = (
		"★ " + pending_unit_data.name
		+ "\nATK " + str(pending_unit_data.attack)
		+ " / HP " + str(pending_unit_data.max_hp)
	)
