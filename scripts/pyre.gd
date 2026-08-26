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
	var result = CombatMath.apply_block(amount, block)

	block = result.remaining_block

	if result.remaining_damage > 0:
		hp -= result.remaining_damage

	if hp < 0:
		hp = 0

	changed.emit()

func is_destroyed() -> bool:
	return hp <= 0
