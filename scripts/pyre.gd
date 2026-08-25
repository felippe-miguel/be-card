class_name Pyre
extends RefCounted

var name: String
var hp: int
var max_hp: int
var block: int = 0

signal changed

func _init(pyre_name: String, max_health: int) -> void:
	name = pyre_name
	max_hp = max_health
	hp = max_health

func take_damage(amount: int) -> void:
	var remaining_damage = amount

	if block > 0:
		var blocked = min(block, remaining_damage)

		block -= blocked
		remaining_damage -= blocked

	if remaining_damage > 0:
		hp -= remaining_damage

	if hp < 0:
		hp = 0

	changed.emit()

func is_destroyed() -> bool:
	return hp <= 0
