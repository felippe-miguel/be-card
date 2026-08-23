class_name TargetSystem
extends RefCounted


var battle_state: BattleState


func _init(state: BattleState) -> void:
	battle_state = state


func get_targets(target_type: String) -> Array[Unit]:
	match target_type:

		"enemy":
			return get_enemies()

		"all_enemies":
			return get_enemies()

		"ally":
			return get_allies()

		"all_allies":
			return get_allies()

		"player":
			return [battle_state.player]

		"front_enemy":
			return get_front_units(
				Unit.Faction.ENEMY
			)

		"rear_enemy":
			return get_rear_units(
				Unit.Faction.ENEMY
			)

		_:
			print(
				"Tipo de alvo desconhecido: ",
				target_type
			)

			return []


func get_enemies() -> Array[Unit]:
	return get_units_by_faction(
		Unit.Faction.ENEMY
	)


func get_allies() -> Array[Unit]:
	return get_units_by_faction(
		Unit.Faction.ALLY
	)


func get_units_by_faction(
	faction: Unit.Faction
) -> Array[Unit]:

	var targets: Array[Unit] = []

	for floor in battle_state.battlefield.floors:
		var units = floor.get_units_for_faction(faction)

		for unit in units:
			targets.append(unit)

	return targets


func get_front_units(
	faction: Unit.Faction
) -> Array[Unit]:

	var targets: Array[Unit] = []

	for floor in battle_state.battlefield.floors:
		var unit = floor.get_front_unit(faction)

		if unit != null:
			targets.append(unit)

	return targets


func get_rear_units(
	faction: Unit.Faction
) -> Array[Unit]:

	var targets: Array[Unit] = []

	for floor in battle_state.battlefield.floors:
		var unit = floor.get_rear_unit(faction)

		if unit != null:
			targets.append(unit)

	return targets

func get_targets_for_unit(
	unit: Unit,
	target_type: String
) -> Array[Unit]:

	match target_type:

		"front_enemy":
			return get_front_enemies_for_unit(unit)

		"rear_enemy":
			return get_rear_enemies_for_unit(unit)

		_:
			return get_targets(target_type)

func get_front_enemies_for_unit(
	unit: Unit
) -> Array[Unit]:

	var target_faction = Unit.Faction.ENEMY

	if unit.faction == Unit.Faction.ENEMY:
		target_faction = Unit.Faction.ALLY

	return get_front_units(target_faction)

func get_rear_enemies_for_unit(
	unit: Unit
) -> Array[Unit]:

	var target_faction = Unit.Faction.ENEMY

	if unit.faction == Unit.Faction.ENEMY:
		target_faction = Unit.Faction.ALLY

	return get_rear_units(target_faction)
