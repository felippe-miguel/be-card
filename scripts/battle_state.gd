class_name BattleState
extends RefCounted


var battlefield: Battlefield
var player: Unit
var unit_database: UnitDatabase

func _init(
	battle_definition: BattleDefinition,
	unit_database: UnitDatabase
) -> void:
	self.unit_database = unit_database

	battlefield = Battlefield.new(
		battle_definition.floors.size()
	)

	player = Unit.new(
		"player",
		"Jogador",
		50
	)

	for floor_index in range(battle_definition.floors.size()):

		var floor_definition = battle_definition.floors[floor_index]

		var floor = battlefield.get_floor(floor_index)

		for unit_id in floor_definition.get("units", []):

			var unit_data = unit_database.units.get(unit_id)

			if unit_data == null:
				print(
					"Unidade não encontrada: ",
					unit_id
				)
				continue

			var unit = Unit.new(
				unit_data.id,
				unit_data.name,
				unit_data.max_hp
			)

			floor.add_unit(unit)


func get_enemy() -> Unit:
	for floor in battlefield.floors:
		for unit in floor.units:
			return unit

	return null
