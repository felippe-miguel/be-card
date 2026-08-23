class_name TargetSystem
extends RefCounted


var battle_state: BattleState


func _init(state: BattleState) -> void:
	battle_state = state


func get_targets(target_type: String) -> Array[Unit]:
	match target_type:
		"enemy":
			return _get_all_enemies()

		"all_enemies":
			return _get_all_enemies()

		"player":
			return [battle_state.player]

		_:
			print("Tipo de alvo desconhecido: ", target_type)
			return []


func _get_all_enemies() -> Array[Unit]:
	var targets: Array[Unit] = []

	for floor in battle_state.battlefield.floors:
		for unit in floor.units:
			targets.append(unit)

	return targets
