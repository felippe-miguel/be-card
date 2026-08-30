class_name BattleFloorView
extends PanelContainer

## Sandbox 3x3 (docs/playtest_3x3.md): cada célula do grid é um Control
## fixo, criado uma vez em _ready() e nunca destruído/reordenado — ao
## contrário do antigo sistema de formação linear (push/spacers/hover
## zones), aqui uma célula sempre representa a mesma (lane, row) pelo
## resto da partida. Ocupar/esvaziar uma célula só troca o que está
## dentro dela (nada some visualmente, só o conteúdo muda).
@onready var enemy_grid: GridContainer = $Layout/EnemyGrid
@onready var ally_grid: GridContainer = $Layout/AllyGrid

const CELL_MIN_SIZE = Vector2(118, 92)
const ROW_NAMES = ["Front", "Middle", "Back"]

var floor_index: int
var battle_floor: BattleFloor

## Uma célula por (lane, row), no mesmo índice de BattleFloor.cell_index()
## — array plano de tamanho LANES * ROWS por facção. Cada célula é um
## Button (não um PanelContainer) para poder ser clicada quando vazia —
## ver _on_cell_pressed()/cell_selected.
var ally_cells: Array[Button] = []
var enemy_cells: Array[Button] = []

signal unit_selected(unit: Unit)

## Emitido quando uma célula VAZIA é clicada (uma célula ocupada nunca
## chega a emitir isto — o clique é capturado antes pela UnitView, que
## cobre a célula inteira e tem mouse_filter = STOP por ser um Button).
## Usado pelo sandbox de posicionamento livre (Game.pending_spawn_unit_id)
## para escolher em qual célula colocar a próxima unidade spawnada.
signal cell_selected(faction: Unit.Faction, lane: int, row: int)

func setup(index: int) -> void:
	floor_index = index

func _ready() -> void:
	for row in range(BattleFloor.ROWS):
		for lane in range(BattleFloor.LANES):
			ally_cells.append(create_cell(Unit.Faction.ALLY, lane, row))
			enemy_cells.append(create_cell(Unit.Faction.ENEMY, lane, row))

	for cell in enemy_cells:
		enemy_grid.add_child(cell)

	for cell in ally_cells:
		ally_grid.add_child(cell)

func connect_to_floor(battleFloor: BattleFloor) -> void:
	battle_floor = battleFloor

	battleFloor.unit_added.connect(_on_unit_added)
	battleFloor.unit_removed.connect(_on_unit_removed)
	battleFloor.unit_moved.connect(_on_unit_moved)

	render_all_cells()

## Constrói o estado visual das 18 células (2 facções x 9 células) a
## partir do BattleFloor real — usado ao conectar e serve de base para
## qualquer refresh pontual (refresh_cell reaproveita a mesma lógica).
func render_all_cells() -> void:
	for row in range(BattleFloor.ROWS):
		for lane in range(BattleFloor.LANES):
			refresh_cell(Unit.Faction.ALLY, lane, row)
			refresh_cell(Unit.Faction.ENEMY, lane, row)

## Cada célula é um Button para poder ser clicada enquanto vazia
## (_on_cell_pressed()). Quando ocupada, a UnitView instanciada dentro
## dela (também um Button, mouse_filter = STOP, cobrindo o retângulo
## inteiro) captura o clique primeiro — então _on_cell_pressed() só
## dispara de fato para células vazias, sem precisar desabilitar nada
## manualmente ao ocupar/esvaziar.
func create_cell(faction: Unit.Faction, lane: int, row: int) -> Button:
	var cell = Button.new()

	cell.custom_minimum_size = CELL_MIN_SIZE
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.focus_mode = Control.FOCUS_NONE
	cell.pressed.connect(_on_cell_pressed.bind(faction, lane, row))

	var empty_label = Label.new()

	empty_label.name = "EmptyLabel"
	empty_label.text = "Lane %d\n%s\n(vazio)" % [lane, ROW_NAMES[row]]
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.modulate = Color(1, 1, 1, 0.5)
	empty_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	cell.add_child(empty_label)

	return cell

func get_cells_for_faction(faction: Unit.Faction) -> Array[Button]:
	if faction == Unit.Faction.ENEMY:
		return enemy_cells

	return ally_cells

func get_cell(faction: Unit.Faction, lane: int, row: int) -> Button:
	return get_cells_for_faction(faction)[BattleFloor.cell_index(lane, row)]

## Só é alcançado quando a célula está vazia — ver o comentário de
## create_cell(). A checagem de is_valid_cell/get_unit_at aqui é só uma
## rede de segurança.
func _on_cell_pressed(faction: Unit.Faction, lane: int, row: int) -> void:
	if battle_floor.get_unit_at(faction, lane, row) != null:
		return

	cell_selected.emit(faction, lane, row)

## Redesenha uma única célula a partir do estado atual (real) do
## BattleFloor — sempre reconsulta get_unit_at() em vez de tentar manter
## a UnitView "no lugar certo" incrementalmente. Torna add/remove/move/
## swap todos idempotentes e sem depender de ordem de eventos (ver
## _on_unit_moved(), onde uma troca dispara isso duas vezes seguidas).
func refresh_cell(faction: Unit.Faction, lane: int, row: int) -> void:
	var cell = get_cell(faction, lane, row)
	var empty_label: Label = cell.get_node("EmptyLabel")
	var existing_view = cell.get_node_or_null("UnitView")

	if existing_view != null:
		cell.remove_child(existing_view)
		existing_view.queue_free()

	var unit = battle_floor.get_unit_at(faction, lane, row)

	if unit == null:
		empty_label.visible = true
		return

	empty_label.visible = false

	var unit_view = preload("res://scenes/unit_view.tscn").instantiate()

	unit_view.name = "UnitView"
	cell.add_child(unit_view)
	unit_view.setup(unit)
	unit_view.selected.connect(_on_unit_selected)

func _on_unit_added(unit: Unit) -> void:
	refresh_cell(unit.faction, unit.lane, unit.row)

func _on_unit_removed(unit: Unit, old_lane: int, old_row: int) -> void:
	refresh_cell(unit.faction, old_lane, old_row)

func _on_unit_moved(unit: Unit, old_lane: int, old_row: int) -> void:
	refresh_cell(unit.faction, old_lane, old_row)
	refresh_cell(unit.faction, unit.lane, unit.row)

func _on_unit_selected(unit: Unit) -> void:
	unit_selected.emit(unit)

## Todas as UnitViews reais deste andar, das duas facções — usado por
## Game para armar/desarmar preview de efeito de carta.
func get_all_unit_views() -> Array[UnitView]:
	var views: Array[UnitView] = []

	for cell in ally_cells:
		var view = cell.get_node_or_null("UnitView") as UnitView

		if view != null:
			views.append(view)

	for cell in enemy_cells:
		var view = cell.get_node_or_null("UnitView") as UnitView

		if view != null:
			views.append(view)

	return views
