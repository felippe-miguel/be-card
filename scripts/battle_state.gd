class_name BattleState
extends RefCounted

var battlefield: Battlefield
var player: Unit

func _init() -> void:
	battlefield = Battlefield.new(3)
	player = Unit.new("player", "Jogador", 50)
	
	var slime = Unit.new("slime", "Slime", 30)
	
	battlefield.get_floor(0).add_unit(slime)

func get_enemy() -> Unit:
	for floor in battlefield.floors:
		for unit in floor.units:
			return unit

	return null
