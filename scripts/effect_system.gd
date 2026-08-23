class_name EffectSystem
extends RefCounted


var battle_state: BattleState


func _init(state: BattleState) -> void:
	battle_state = state


func execute_effect(effect: Dictionary) -> void:
	var type = effect.get("type", "")

	match type:
		"damage":
			var amount = effect.get("amount", 0)
			var enemy = battle_state.get_enemy()

			if enemy != null:
				enemy.take_damage(amount)

		"block":
			var amount = effect.get("amount", 0)
			battle_state.player.add_block(amount)

		"heal":
			var amount = effect.get("amount", 0)
			battle_state.player.heal(amount)

		_:
			print("Efeito desconhecido: ", type)
