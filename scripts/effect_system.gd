class_name EffectSystem
extends RefCounted


var battle_state: BattleState
var target_system: TargetSystem


func _init(state: BattleState) -> void:
	battle_state = state
	target_system = TargetSystem.new(state)


func execute_effect(
	effect: Dictionary,
	selected_target: Unit = null,
	selected_floor: int = -1
) -> void:
	var type = effect.get("type", "")
	var target_type = effect.get("target", "")

	var targets: Array[Unit] = []

	if target_type == "selected_enemy":
		if selected_target != null:
			targets.append(selected_target)
		else:
			print("Efeito precisa de um alvo!")
			return
	else:
		targets = target_system.get_targets(target_type)

	match type:
		"damage":
			var amount = effect.get("amount", 0)

			for target in targets:
				target.take_damage(amount)

		"block":
			var amount = effect.get("amount", 0)

			for target in targets:
				target.add_block(amount)

		"heal":
			var amount = effect.get("amount", 0)

			for target in targets:
				target.heal(amount)

		"summon":
			var unit_id = effect.get("unit", "")

			if selected_floor < 0:
				print("Summon precisa de um andar.")
				return

			var unit_data = battle_state.unit_database.units.get(unit_id)

			if unit_data == null:
				print("Unidade não encontrada: ", unit_id)
				return

			var unit = battle_state.create_unit(
				unit_id,
				Unit.Faction.ALLY
			)

			var floor = battle_state.battlefield.get_floor(
				selected_floor
			)

			if floor == null:
				return

			if not floor.add_unit(unit):
				print("Andar cheio!")
				return

			print(
				"Invocado: ",
				unit.name,
				" no andar ",
				selected_floor
			)

		_:
			print("Efeito desconhecido: ", type)
