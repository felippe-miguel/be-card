class_name BattleFloorView
extends PanelContainer

## Sandbox 3x3 (docs/playtest_3x3.md): cada célula do grid é um Control
## fixo, criado uma vez em _ready() e nunca destruído/reordenado — ao
## contrário do antigo sistema de formação linear (push/spacers/hover
## zones), aqui uma célula sempre representa a mesma (lane, row) pelo
## resto da partida. Ocupar/esvaziar uma célula só troca o que está
## dentro dela (nada some visualmente, só o conteúdo muda).
@onready var enemy_grid: GridContainer = $Layout/EnemySection/EnemyGrid
@onready var ally_grid: GridContainer = $Layout/AllySection/AllyGrid
@onready var pattern_info_title: Label = $Layout/PatternInfoPanel/PatternInfoTitle
@onready var pattern_info_body: Label = $Layout/PatternInfoPanel/PatternInfoBody

const PATTERN_INFO_PLACEHOLDER = "Passe o mouse sobre uma unidade para ver os detalhes do ataque."

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

## Repassados do hover_started/hover_ended de cada UnitView — ver
## Game._on_unit_hover_started()/_ended() (highlight de alvos de ataque
## e de aura no hover).
signal unit_hover_started(unit: Unit)
signal unit_hover_ended(unit: Unit)

func setup(index: int) -> void:
	floor_index = index

func _ready() -> void:
	for row in range(BattleFloor.ROWS):
		for lane in range(BattleFloor.LANES):
			ally_cells.append(create_cell(Unit.Faction.ALLY, lane, row))
			enemy_cells.append(create_cell(Unit.Faction.ENEMY, lane, row))

	for cell in ally_cells:
		ally_grid.add_child(cell)

	## Grid dos inimigos fica verticalmente invertido (Back em cima, Front
	## embaixo) — pensado pra quando os dois tabuleiros forem empilhados
	## um embaixo do outro no futuro, "se encarando" pela Front. Lane
	## continua esquerda->direita igual o lado aliado; só a ORDEM em que
	## as células viram filhas da GridContainer muda (isso é só visual —
	## enemy_cells continua indexado por cell_index(lane, row) normalmente,
	## get_cell()/refresh_cell() etc. não sabem nem precisam saber disso).
	for row in range(BattleFloor.ROWS - 1, -1, -1):
		for lane in range(BattleFloor.LANES):
			enemy_grid.add_child(enemy_cells[BattleFloor.cell_index(lane, row)])

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
	unit_view.hover_started.connect(_on_unit_hover_started)
	unit_view.hover_ended.connect(_on_unit_hover_ended)

func _on_unit_added(unit: Unit) -> void:
	refresh_cell(unit.faction, unit.lane, unit.row)

func _on_unit_removed(unit: Unit, old_lane: int, old_row: int) -> void:
	refresh_cell(unit.faction, old_lane, old_row)

func _on_unit_moved(unit: Unit, old_lane: int, old_row: int) -> void:
	refresh_cell(unit.faction, old_lane, old_row)
	refresh_cell(unit.faction, unit.lane, unit.row)

func _on_unit_selected(unit: Unit) -> void:
	unit_selected.emit(unit)

func _on_unit_hover_started(unit: Unit) -> void:
	unit_hover_started.emit(unit)

func _on_unit_hover_ended(unit: Unit) -> void:
	unit_hover_ended.emit(unit)

## Painel ao lado do grid de aliados explicando o padrão de ataque (e a
## aura, se houver) da unidade em hover — preenchido por
## Game._on_unit_hover_started()/show_pattern_info(), já que o texto em
## si (o que cada padrão faz) é conhecimento de TargetSystem, não deste
## node visual.
func set_pattern_info(title: String, body: String) -> void:
	pattern_info_title.text = title
	pattern_info_body.text = body

func clear_pattern_info() -> void:
	pattern_info_title.text = ""
	pattern_info_body.text = PATTERN_INFO_PLACEHOLDER

## A UnitView de uma Unit ainda posicionada no grid, ou null se ela não
## estiver (removida, ou lane/row inválidos). O(1): a célula certa já é
## conhecida a partir de unit.faction/lane/row, sem precisar buscar.
func get_unit_view(unit: Unit) -> UnitView:
	if not BattleFloor.is_valid_cell(unit.lane, unit.row):
		return null

	return get_cell(unit.faction, unit.lane, unit.row).get_node_or_null("UnitView") as UnitView

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
