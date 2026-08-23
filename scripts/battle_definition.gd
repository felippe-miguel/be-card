class_name BattleDefinition
extends RefCounted


var floors: Array = []


static func from_dict(data: Dictionary) -> BattleDefinition:
	var definition = BattleDefinition.new()

	definition.floors = data.get("floors", [])

	return definition
