class_name BattleState
extends RefCounted


var battlefield: Battlefield

var player: Unit


func _init() -> void:
	battlefield = Battlefield.new(3)

	player = Unit.new(
		"player",
		"Jogador",
		50
	)

	# Andar 0
	battlefield.get_floor(0).add_unit(
		Unit.new("slime_1", "Slime", 30)
	)

	battlefield.get_floor(0).add_unit(
		Unit.new("slime_2", "Slime", 25)
	)

	# Andar 1
	battlefield.get_floor(1).add_unit(
		Unit.new("skeleton", "Skeleton", 20)
	)

	# Andar 2
	battlefield.get_floor(2).add_unit(
		Unit.new("orc", "Orc", 40)
	)


func get_enemy() -> Unit:
	for floor in battlefield.floors:
		for unit in floor.units:
			return unit

	return null
