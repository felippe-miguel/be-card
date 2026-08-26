class_name EffectSystem
extends RefCounted

var battle_state: BattleState
var target_system: TargetSystem

func _init(state: BattleState) -> void:
	battle_state = state
	target_system = TargetSystem.new(state)

func execute_effect(
	effect: Dictionary,
	selected_unit: Unit = null,
	selected_floor: int = -1
) -> void:
	var type = effect.get("type", "")
	var target_type = effect.get("target", "")
	var target_faction: String = effect.get("target_faction", "")
	var targets: Array[Unit] = []
	
	if type != "summon":
		targets = target_system.get_card_targets(
			target_type,
			selected_unit,
			target_faction
		)

		if target_type == "selected_unit" and targets.is_empty():
			print("Efeito precisa de uma unidade selecionada!")
			return
	
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
			
			var unit = battle_state.create_unit(unit_id, Unit.Faction.ALLY)
			var battle_floor = battle_state.battlefield.get_floor(selected_floor)
			
			if battle_floor == null:
				return
			
			if not battle_floor.add_unit(unit):
				print("Andar cheio!")
				return
			
			print("Invocado: ", unit.name, " no andar ", selected_floor)
		
		_:
			print("Efeito desconhecido: ", type)

func can_target_selected_unit(effect: Dictionary, selected_unit: Unit) -> bool:
	if effect.get("target", "") != "selected_unit":
		return true

	var target_faction: String = effect.get("target_faction", "")
	var targets = target_system.get_card_targets(
		"selected_unit",
		selected_unit,
		target_faction
	)

	return not targets.is_empty()
