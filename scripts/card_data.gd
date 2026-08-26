class_name CardData
extends RefCounted

var id: String
var name: String
var description: String
var cost: int
var type: String
var effects: Array[Dictionary] = []

static func from_dict(data: Dictionary) -> CardData:
	var card = CardData.new()
	
	card.id = data.get("id", "")
	card.name = data.get("name", "")
	card.description = data.get("description", "")
	card.cost = data.get("cost", 0)
	card.type = data.get("type", "")
	card.effects.assign(data.get("effects", []))
	
	return card
