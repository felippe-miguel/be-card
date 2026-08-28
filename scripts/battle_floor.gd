class_name BattleFloor
extends RefCounted

signal unit_added(unit: Unit)
signal unit_removed(unit: Unit)

var index: int
var max_units: int = 3
var allies: Array[Unit] = []
var enemies: Array[Unit] = []

func _init(floor_index: int, capacity: int = 3) -> void:
	index = floor_index
	max_units = capacity

func can_add_unit(faction: Unit.Faction) -> bool:
	return get_units_for_faction(faction).size() < max_units

## Adiciona a unidade no fim da formação da sua facção (comportamento
## default de summon, sem escolher posição). Equivale a inserir depois da
## última unidade presente.
func add_unit(unit: Unit) -> bool:
	return insert_unit_at(unit, get_units_for_faction(unit.faction).size())

## Insere a unidade na posição pedida da formação da sua facção,
## empurrando as unidades já presentes a partir dali (Array.insert() já
## desloca os elementos seguintes). position é fixado entre 0 e o total
## atual de unidades; index além do fim vira "inserir no fim". Falha se a
## facção já estiver no limite (max_units) — empurrar não abre espaço
## novo, só reorganiza o que já cabe.
func insert_unit_at(unit: Unit, position: int) -> bool:
	if not can_add_unit(unit.faction):
		return false

	var units = get_units_for_faction(unit.faction)
	var clamped_position = clampi(position, 0, units.size())

	units.insert(clamped_position, unit)
	unit.floor_index = index
	unit.changed.connect(_on_unit_changed.bind(unit))

	reorder_units(unit.faction)

	print(
		unit.name,
		" entrou no andar ", index,
		" na posição ", unit.position_index,
		" na facção ", unit.faction
	)

	unit_added.emit(unit)

	return true

func get_units_for_faction(faction: Unit.Faction) -> Array[Unit]:
	if faction == Unit.Faction.ALLY:
		return allies

	return enemies

func get_unit_at(faction: Unit.Faction, position: int) -> Unit:
	var units = get_units_for_faction(faction)
	
	for unit in units:
		if unit.position_index == position:
			return unit
	
	return null

func remove_unit(unit: Unit) -> void:
	var units = get_units_for_faction(unit.faction)
	
	if unit in units:
		var changed_callback = _on_unit_changed.bind(unit)

		if unit.changed.is_connected(changed_callback):
			unit.changed.disconnect(changed_callback)

		units.erase(unit)
		unit.position_index = -1
		unit.floor_index = -1
		
		reorder_units(unit.faction)
		
		unit_removed.emit(unit)

func get_units() -> Array[Unit]:
	var result: Array[Unit] = []
	
	result.append_array(allies)
	result.append_array(enemies)
	
	return result

func get_front_unit(faction: Unit.Faction) -> Unit:
	return get_unit_at(faction, 0)

func get_rear_unit(faction: Unit.Faction) -> Unit:
	var units = get_units_for_faction(faction)
	
	if units.is_empty():
		return null
	
	var rear_position = -1
	
	for unit in units:
		if unit.position_index > rear_position:
			rear_position = unit.position_index
	
	return get_unit_at(faction, rear_position)

func reorder_units(faction: Unit.Faction) -> void:
	var units = get_units_for_faction(faction)
	
	for i in range(units.size()):
		units[i].position_index = i
		units[i].changed.emit()

func _on_unit_changed(unit: Unit) -> void:
	if unit.is_dead():
		remove_unit(unit)
