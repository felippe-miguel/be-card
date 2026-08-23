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


func add_unit(unit: Unit) -> bool:
	if not can_add_unit(unit.faction):
		return false

	var units = get_units_for_faction(unit.faction)

	var position = find_first_free_position(unit.faction)

	if position == -1:
		return false

	unit.position_index = position
	unit.floor_index = index

	units.append(unit)

	print(
		unit.name,
		" entrou no andar ",
		index,
		" na posição ",
		position,
		" na facção ",
		unit.faction
	)

	unit_added.emit(unit)

	return true


func get_units_for_faction(
	faction: Unit.Faction
) -> Array[Unit]:

	if faction == Unit.Faction.ALLY:
		return allies

	return enemies


func find_first_free_position(
	faction: Unit.Faction
) -> int:

	for position in range(max_units):
		if get_unit_at(faction, position) == null:
			return position

	return -1


func get_unit_at(
	faction: Unit.Faction,
	position: int
) -> Unit:

	var units = get_units_for_faction(faction)

	for unit in units:
		if unit.position_index == position:
			return unit

	return null


func remove_unit(unit: Unit) -> void:
	var units = get_units_for_faction(unit.faction)

	if unit in units:
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
