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

	var floor = battle_state.battlefield.get_floor(
		floor_index
	)

	if floor == null:
		return targets

	var unit = floor.get_front_unit(faction)

	if unit != null:
		targets.append(unit)

	return targets


func get_rear_units(faction: Unit.Faction, floor_index: int) -> Array[Unit]:
	var targets: Array[Unit] = []

	var floor = battle_state.battlefield.get_floor(
		floor_index
	)

	if floor == null:
		return targets

	var unit = floor.get_rear_unit(faction)

	if unit != null:
		targets.append(unit)

	return targets


func get_units_on_floor(faction: Unit.Faction, floor_index: int) -> Array[Unit]:
	var targets: Array[Unit] = []

	var floor = battle_state.battlefield.get_floor(
		floor_index
	)

	if floor == null:
		return targets

	var units = floor.get_units_for_faction(
		faction
	)

	targets.append_array(units)

	return targets


# ==========================================
# CARD TARGETING
# ==========================================
func get_card_targets(target_type: String, selected_unit: Unit = null) -> Array[Unit]:
	match target_type:

		"selected_unit":
			if selected_unit == null:
				return []

			return [selected_unit]

		"all_enemies":
			return get_units_by_faction(
				Unit.Faction.ENEMY
			)

		"all_allies":
			return get_units_by_faction(
				Unit.Faction.ALLY
			)

		_:
			return []


func get_units_by_faction(faction: Unit.Faction) -> Array[Unit]:
	var targets: Array[Unit] = []

	for floor in battle_state.battlefield.floors:
		targets.append_array(
			floor.get_units_for_faction(faction)
		)

	return targets


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
