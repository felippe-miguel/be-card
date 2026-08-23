class_name BattleFloor
extends RefCounted

signal unit_added(unit: Unit)
signal unit_removed(unit: Unit)

var index: int
var max_units: int = 3
var units: Array[Unit] = []

func _init(floor_index: int, capacity: int = 3) -> void:
	index = floor_index
	max_units = capacity

func can_add_unit() -> bool:
	return units.size() < max_units

func add_unit(unit: Unit) -> bool:
	if not can_add_unit():
		return false

	var position = find_first_free_position()

	if position == -1:
		return false

	unit.position_index = position
	units.append(unit)

	print(
		unit.name,
		" entrou no andar ",
		index,
		" na posição ",
		position
	)
	
	unit_added.emit(unit)

	return true

func find_first_free_position() -> int:
	for position in range(max_units):
		if get_unit_at(position) == null:
			return position

	return -1

func get_unit_at(position: int) -> Unit:
	for unit in units:
		if unit.position_index == position:
			return unit

	return null

func remove_unit(unit: Unit) -> void:
	if unit in units:
		units.erase(unit)
		unit.position_index = -1
		unit_removed.emit(unit)

func get_units() -> Array[Unit]:
	return units
