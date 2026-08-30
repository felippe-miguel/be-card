class_name BattleFloor
extends RefCounted

## Sandbox 3x3 (docs/playtest_3x3.md): cada facção tem seu próprio grid
## LANES x ROWS. Cada unidade ocupa exatamente uma célula (lane, row);
## não há mais formação linear nem push/compactação — uma célula vazia
## continua vazia até alguém a preencher de propósito.
signal unit_added(unit: Unit)
signal unit_removed(unit: Unit, old_lane: int, old_row: int)
signal unit_moved(unit: Unit, old_lane: int, old_row: int)

const LANES = 3
const ROWS = 3

## row: 0 = Front, 1 = Middle, 2 = Back.
enum Row { FRONT = 0, MIDDLE = 1, BACK = 2 }

var index: int
var allies: Array[Unit] = []
var enemies: Array[Unit] = []

func _init(floor_index: int = 0) -> void:
	index = floor_index

	allies.resize(LANES * ROWS)
	enemies.resize(LANES * ROWS)

## Índice único de uma célula dentro do array plano de uma facção.
## static para BattleFloorView poder usar a mesma fórmula sem precisar de
## uma instância.
static func cell_index(lane: int, row: int) -> int:
	return row * LANES + lane

static func is_valid_cell(lane: int, row: int) -> bool:
	return lane >= 0 and lane < LANES and row >= 0 and row < ROWS

## Lanes vizinhas válidas de "lane" (1 se for lane de borda, 2 se for a
## lane central). Base do padrão de ataque do Assassino/Mago — ver
## TargetSystem.get_pattern_attack_targets().
static func adjacent_lanes(lane: int) -> Array[int]:
	var result: Array[int] = []

	if lane - 1 >= 0:
		result.append(lane - 1)

	if lane + 1 < LANES:
		result.append(lane + 1)

	return result

## Unidades ortogonalmente adjacentes a (lane, row) na mesma facção — as 4
## células vizinhas (lane±1 mesma row, row±1 mesma lane), sem diagonais,
## ignorando as que não existem/estão vazias. Base da passiva do Guardião
## — ver BattleState.recalculate_auras().
func get_adjacent_units(faction: Unit.Faction, lane: int, row: int) -> Array[Unit]:
	var result: Array[Unit] = []
	var offsets = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]

	for offset in offsets:
		var unit = get_unit_at(faction, lane + offset.x, row + offset.y)

		if unit != null:
			result.append(unit)

	return result

func get_grid(faction: Unit.Faction) -> Array[Unit]:
	if faction == Unit.Faction.ALLY:
		return allies

	return enemies

func get_unit_at(faction: Unit.Faction, lane: int, row: int) -> Unit:
	if not is_valid_cell(lane, row):
		return null

	return get_grid(faction)[cell_index(lane, row)]

func can_place_at(faction: Unit.Faction, lane: int, row: int) -> bool:
	return is_valid_cell(lane, row) and get_unit_at(faction, lane, row) == null

func has_empty_cell(faction: Unit.Faction) -> bool:
	return get_grid(faction).has(null)

## Alias mantido para compatibilidade com código que ainda pensa em "tem
## espaço pra mais uma unidade" (ex: EnemySpawner) — equivale a
## has_empty_cell() já que não existe mais limite separado de "unidades
## na formação" vs "células do grid".
func can_add_unit(faction: Unit.Faction) -> bool:
	return has_empty_cell(faction)

## Primeira célula vazia, varrendo row por row (Front..Back) e, dentro de
## cada row, lane por lane (esquerda a direita). Usado por quem não se
## importa com a célula exata (add_unit(), EnemySpawner).
func find_first_empty_cell(faction: Unit.Faction) -> Vector2i:
	for row in range(ROWS):
		for lane in range(LANES):
			if can_place_at(faction, lane, row):
				return Vector2i(lane, row)

	return Vector2i(-1, -1)

## Coloca a unidade na primeira célula vazia disponível, sem escolher
## onde. Equivalente ao antigo "adicionar no fim da formação" — usado
## quando quem chama não oferece escolha de célula (EnemySpawner, fallback
## de summon sem posição escolhida).
func add_unit(unit: Unit) -> bool:
	var cell = find_first_empty_cell(unit.faction)

	if cell.x < 0:
		return false

	return place_unit_at(unit, cell.x, cell.y)

## Coloca a unidade exatamente na célula (lane, row) pedida. Falha se a
## célula não existir ou já estiver ocupada — ao contrário do sistema
## antigo, não existe "empurrar" unidades para abrir espaço.
func place_unit_at(unit: Unit, lane: int, row: int) -> bool:
	if not can_place_at(unit.faction, lane, row):
		return false

	get_grid(unit.faction)[cell_index(lane, row)] = unit
	unit.lane = lane
	unit.row = row
	unit.changed.connect(_on_unit_changed.bind(unit))

	print(unit.name, " posicionado em Lane ", lane, " Row ", row, " (", Unit.Faction.keys()[unit.faction], ")")

	unit_added.emit(unit)

	return true

func remove_unit(unit: Unit) -> void:
	var grid = get_grid(unit.faction)

	if not is_valid_cell(unit.lane, unit.row):
		return

	var idx = cell_index(unit.lane, unit.row)

	if grid[idx] != unit:
		return

	var changed_callback = _on_unit_changed.bind(unit)

	if unit.changed.is_connected(changed_callback):
		unit.changed.disconnect(changed_callback)

	grid[idx] = null

	var old_lane = unit.lane
	var old_row = unit.row

	unit.lane = -1
	unit.row = -1

	unit_removed.emit(unit, old_lane, old_row)

## Move a unidade para outra célula vazia da mesma facção. Falha (sem
## nenhum efeito) se a célula de destino não existir ou já estiver
## ocupada. Usado pelas cartas de reposicionamento (Reposicionar,
## Flanquear, Avançar, Recuar, Teleporte).
func move_unit(unit: Unit, new_lane: int, new_row: int) -> bool:
	if not can_place_at(unit.faction, new_lane, new_row):
		return false

	var grid = get_grid(unit.faction)
	var old_lane = unit.lane
	var old_row = unit.row

	grid[cell_index(old_lane, old_row)] = null
	grid[cell_index(new_lane, new_row)] = unit

	unit.lane = new_lane
	unit.row = new_row

	unit_moved.emit(unit, old_lane, old_row)

	return true

## Troca duas unidades aliadas de célula (carta "Troca"). As duas
## precisam ser da mesma facção — não existe troca entre lados opostos.
func swap_units(unit_a: Unit, unit_b: Unit) -> bool:
	if unit_a.faction != unit_b.faction or unit_a == unit_b:
		return false

	var grid = get_grid(unit_a.faction)
	var lane_a = unit_a.lane
	var row_a = unit_a.row
	var lane_b = unit_b.lane
	var row_b = unit_b.row

	grid[cell_index(lane_a, row_a)] = unit_b
	grid[cell_index(lane_b, row_b)] = unit_a

	unit_a.lane = lane_b
	unit_a.row = row_b
	unit_b.lane = lane_a
	unit_b.row = row_a

	unit_moved.emit(unit_a, lane_a, row_a)
	unit_moved.emit(unit_b, lane_b, row_b)

	return true

func get_units_for_faction(faction: Unit.Faction) -> Array[Unit]:
	var result: Array[Unit] = []

	for unit in get_grid(faction):
		if unit != null:
			result.append(unit)

	return result

## Unidades de uma lane, ordenadas de Front (row 0) para Back (row 2),
## sem células vazias. Base dos padrões de ataque (ver
## docs/playtest_3x3.md seção 3/4).
func get_lane_units(faction: Unit.Faction, lane: int) -> Array[Unit]:
	var result: Array[Unit] = []

	for row in range(ROWS):
		var unit = get_unit_at(faction, lane, row)

		if unit != null:
			result.append(unit)

	return result

func get_units() -> Array[Unit]:
	var result: Array[Unit] = []

	result.append_array(get_units_for_faction(Unit.Faction.ALLY))
	result.append_array(get_units_for_faction(Unit.Faction.ENEMY))

	return result

func _on_unit_changed(unit: Unit) -> void:
	if unit.is_dead():
		remove_unit(unit)
