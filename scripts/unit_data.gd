class_name UnitData
extends RefCounted

var id: String
var name: String
var max_hp: int

static func from_dict(data: Dictionary) -> UnitData:
	var unit_data = UnitData.new()

	unit_data.id = data.get("id", "")
	unit_data.name = data.get("name", "")
	unit_data.max_hp = data.get("max_hp", 1)

	return unit_data
