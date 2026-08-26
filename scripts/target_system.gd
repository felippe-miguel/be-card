class_name TargetSystem
extends RefCounted

var battle_state: BattleState

func _init(state: BattleState) -> void:
	battle_state = state

# ==========================================
# UNIT ATTACK TARGETING
# ==========================================
func get_attack_targets(attacker: Unit, shape: TargetRule.Shape) -> Array[Unit]:
	var target_faction = get_opposite_faction(
		attacker.faction
	)
	
	match shape:
		TargetRule.Shape.FRONT:
			return get_front_units(
				target_faction,
				attacker.floor_index
			)
		
		TargetRule.Shape.REAR:
			return get_rear_units(
				target_faction,
				attacker.floor_index
			)
		
		TargetRule.Shape.ALL:
			return get_units_on_floor(
				target_faction,
				attacker.floor_index
			)
		
		_:
			return []

func get_opposite_faction(faction: Unit.Faction) -> Unit.Faction:
	if faction == Unit.Faction.ALLY:
		return Unit.Faction.ENEMY
	
	return Unit.Faction.ALLY

func get_front_units(faction: Unit.Faction, floor_index: int) -> Array[Unit]:
	var targets: Array[Unit] = []
	var battle_floor = battle_state.battlefield.get_floor(floor_index)
	
	if battle_floor == null:
		return targets
	
	var unit = battle_floor.get_front_unit(faction)
	
	if unit != null:
		targets.append(unit)
	
	return targets

func get_rear_units(faction: Unit.Faction, floor_index: int) -> Array[Unit]:
	var targets: Array[Unit] = []
	var battle_floor = battle_state.battlefield.get_floor(floor_index)
	
	if battle_floor == null:
		return targets
	
	var unit = battle_floor.get_rear_unit(faction)
	
	if unit != null:
		targets.append(unit)
	
	return targets

func get_units_on_floor(faction: Unit.Faction, floor_index: int) -> Array[Unit]:
	var targets: Array[Unit] = []
	var battle_floor = battle_state.battlefield.get_floor(floor_index)
	
	if battle_floor == null:
		return targets
	
	var units = battle_floor.get_units_for_faction(faction)
	
	targets.append_array(units)
	
	return targets

# ==========================================
# CARD TARGETING
# ==========================================
func get_card_targets(
	target_type: String,
	selected_unit: Unit = null,
	target_faction: String = ""
) -> Array[Unit]:
	match target_type:
		"selected_unit":
			if selected_unit == null:
				return []

			if not matches_target_faction(selected_unit, target_faction):
				return []

			return [selected_unit]
		
		"all_enemies":
			return get_units_by_faction(Unit.Faction.ENEMY)
		
		"all_allies":
			return get_units_by_faction(Unit.Faction.ALLY)
		
		_:
			print("Tipo de alvo de carta desconhecido: ", target_type)
			return []

func matches_target_faction(unit: Unit, target_faction: String) -> bool:
	if target_faction.is_empty():
		return true

	match target_faction:
		"ally":
			return unit.faction == Unit.Faction.ALLY

		"enemy":
			return unit.faction == Unit.Faction.ENEMY

		_:
			print("Facção de alvo de carta desconhecida: ", target_faction)
			return false

func get_units_by_faction(faction: Unit.Faction) -> Array[Unit]:
	var targets: Array[Unit] = []
	
	for battle_floor in battle_state.battlefield.floors:
		targets.append_array(battle_floor.get_units_for_faction(faction))

	return targets
