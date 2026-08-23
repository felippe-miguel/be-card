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
			battle_state.damage_enemy(amount)

		"block":
			var amount = effect.get("amount", 0)
			battle_state.add_player_block(amount)

		"heal":
			var amount = effect.get("amount", 0)
			battle_state.heal_player(amount)

		_:
			print("Efeito desconhecido: ", type)
