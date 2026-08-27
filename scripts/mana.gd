class_name Mana
extends RefCounted

## Mana do jogador: recurso gasto ao jogar cartas. Reabastece por completo
## a cada turno — não acumula sobra de um turno para o outro.

signal changed

var max_mana: int
var current: int

func _init(starting_max_mana: int) -> void:
	max_mana = starting_max_mana
	current = max_mana

func can_afford(cost: int) -> bool:
	return current >= cost

func spend(cost: int) -> void:
	current -= cost

	if current < 0:
		current = 0

	changed.emit()

func refill() -> void:
	current = max_mana

	changed.emit()
