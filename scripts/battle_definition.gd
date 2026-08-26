class_name BattleDefinition
extends RefCounted

var floors: Array[Dictionary] = []

static func from_dict(data: Dictionary) -> BattleDefinition:
	var definition = BattleDefinition.new()
	
	definition.floors.assign(data.get("floors", []))
	
	return definition
