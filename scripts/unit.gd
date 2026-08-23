class_name Unit
extends RefCounted

var id: String
var name: String
var hp: int
var max_hp: int
var block: int = 0

signal changed

func _init(
	unit_id: String,
	unit_name: String,
	max_health: int
) -> void:
	id = unit_id
	name = unit_name
	max_hp = max_health
	hp = max_health

func take_damage(amount: int) -> void:
	var remaining_damage = amount

	if block > 0:
		var blocked = min(block, remaining_damage)

		block -= blocked
		remaining_damage -= blocked

		print(name, " bloqueou ", blocked, " de dano.")

	if remaining_damage > 0:
		hp -= remaining_damage

	if hp < 0:
		hp = 0

	print(
		name,
		" recebeu ",
		remaining_damage,
		" de dano. HP: ",
		hp,
		"/",
		max_hp
	)
	
	changed.emit()

func heal(amount: int) -> void:
	hp += amount

	if hp > max_hp:
		hp = max_hp

	print(
		name,
		" recuperou ",
		amount,
		" de vida. HP: ",
		hp,
		"/",
		max_hp
	)
	
	changed.emit()

func add_block(amount: int) -> void:
	block += amount

	print(
		name,
		" ganhou ",
		amount,
		" de bloqueio. Block: ",
		block
	)
	
	changed.emit()

func is_dead() -> bool:
	return hp <= 0
