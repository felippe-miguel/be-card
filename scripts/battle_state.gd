class_name BattleState
extends RefCounted


var battlefield: Battlefield

var player: Unit


func _init(unit_database: UnitDatabase) -> void:
	battlefield = Battlefield.new(3)

	player = Unit.new(
		"player",
		"Jogador",
		50
	)
	
	var slime_data = unit_database.units["slime"]
	var skeleton_data = unit_database.units["skeleton"]
	var orc_data = unit_database.units["orc"]

	battlefield.get_floor(0).add_unit(
		Unit.new(
			slime_data.id,
			slime_data.name,
			slime_data.max_hp
		)
	)

	battlefield.get_floor(0).add_unit(
		Unit.new(
			slime_data.id + "_2",
			slime_data.name,
			slime_data.max_hp
		)
	)

	battlefield.get_floor(1).add_unit(
		Unit.new(
			skeleton_data.id,
			skeleton_data.name,
			skeleton_data.max_hp
		)
	)

	battlefield.get_floor(2).add_unit(
		Unit.new(
			orc_data.id,
			orc_data.name,
			orc_data.max_hp
		)
	)


func get_enemy() -> Unit:
	for floor in battlefield.floors:
		for unit in floor.units:
			return unit

	return null
