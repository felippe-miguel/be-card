class_name EffectSystem
extends RefCounted


var battle_state: BattleState
var target_system: TargetSystem


func _init(state: BattleState) -> void:
	battle_state = state
	target_system = TargetSystem.new(state)


func execute_effect(effect: Dictionary, selected_target: Unit = null) -> void:
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

		_:
			print("Efeito desconhecido: ", type)
