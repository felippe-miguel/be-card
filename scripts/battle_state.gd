class_name BattleState
extends RefCounted

var battlefield: Battlefield
var pyre: Pyre
var unit_database: UnitDatabase
var target_system: TargetSystem

func _init(battle_definition: BattleDefinition, database: UnitDatabase) -> void:
	unit_database = database
	
	battlefield = Battlefield.new(battle_definition.floors.size())
	
	pyre = Pyre.new("Pyre", 50)

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
