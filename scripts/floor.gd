class_name BattleFloor
extends RefCounted

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

	units.append(unit)

	print(
		unit.name,
		" entrou no andar ",
		index
	)

	return true

func remove_unit(unit: Unit) -> void:
	units.erase(unit)

func get_units() -> Array[Unit]:
	return units
