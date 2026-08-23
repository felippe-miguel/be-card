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

		_:
			print("Tipo de alvo desconhecido: ", target_type)
			return []

func _get_all_enemies() -> Array[Unit]:
	return get_enemies()

func get_enemies() -> Array[Unit]:
	return get_units_by_faction(Unit.Faction.ENEMY)

func get_allies() -> Array[Unit]:
	return get_units_by_faction(Unit.Faction.ALLY)

func get_units_by_faction(faction: Unit.Faction) -> Array[Unit]:
	var targets: Array[Unit] = []

	for floor in battle_state.battlefield.floors:
		for unit in floor.units:
			if unit.faction == faction:
				targets.append(unit)

	return targets
