class_name BattleState
extends RefCounted

var battlefield: Battlefield
var player: Unit
var unit_database: UnitDatabase
var target_system: TargetSystem

func _init(battle_definition: BattleDefinition, database: UnitDatabase) -> void:
	unit_database = database
	
	battlefield = Battlefield.new(battle_definition.floors.size())
	
	player = Unit.new(
		"player",
		"Jogador",
		50,
		0,
		Unit.Faction.ALLY
	)

	for floor_index in range(battle_definition.floors.size()):
		var floor_definition = battle_definition.floors[floor_index]
		var battle_floor = battlefield.get_floor(floor_index)
		
		for unit_definition in floor_definition.get("units", []):
			var unit_id = unit_definition.get("id", "")
			var faction_name = unit_definition.get("faction", "enemy")
			var faction = Unit.Faction.ENEMY
			
			if faction_name == "ally":
				faction = Unit.Faction.ALLY
			
			var unit = create_unit(unit_id, faction)
			
			if unit != null:
				battle_floor.add_unit(unit)
	
	target_system = TargetSystem.new(self)
	test_enemy_attack()
	test_ally_attack()

func get_enemy() -> Unit:
	for battle_floor in battlefield.floors:
		for unit in battle_floor.units:
			return unit
	
	return null

func create_unit(unit_id: String, faction: Unit.Faction) -> Unit:
	var unit_data = unit_database.units.get(unit_id)
	
	if unit_data == null:
		print("Unidade não encontrada: ", unit_id)
		
		return null
	
	return Unit.new(
		unit_data.id,
		unit_data.name,
		unit_data.max_hp,
		unit_data.attack,
		faction
	)

func execute_unit_attack(unit: Unit) -> void:
	var targets = target_system.get_attack_targets(
		unit,
		TargetRule.Shape.FRONT
	)
	
	if targets.is_empty():
		print(unit.name, " não encontrou nenhum alvo.")
		return
	
	var target = targets[0]
	
	unit.attack_unit(target)

func get_target_on_same_floor(unit: Unit, targets: Array[Unit]) -> Unit:
	for target in targets:
		if target.floor_index == unit.floor_index:
			return target
	
	return null

func test_enemy_attack() -> void:
	var battle_floor = battlefield.get_floor(0)
	var enemy = battle_floor.get_front_unit(Unit.Faction.ENEMY)
	
	if enemy == null:
		return
	
	execute_unit_attack(enemy)

func test_ally_attack() -> void:
	var battle_floor = battlefield.get_floor(0)
	var ally = battle_floor.get_front_unit(Unit.Faction.ALLY)
	
	if ally == null:
		return
	
	execute_unit_attack(ally)
