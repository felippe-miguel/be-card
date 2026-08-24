class_name Battlefield
extends RefCounted

var floors: Array[BattleFloor] = []

func _init(number_of_floors: int = 3) -> void:
	for i in range(number_of_floors):
		floors.append(
			BattleFloor.new(i)
		)

func get_floor(index: int) -> BattleFloor:
	if index < 0 or index >= floors.size():
		return null
	
	return floors[index]
