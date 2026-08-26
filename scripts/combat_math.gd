class_name CombatMath
extends RefCounted

## Lógica de absorção de dano por bloqueio, compartilhada por qualquer
## entidade que tenha "hp" e "block" (hoje: Unit e Pyre). Mantida fora das
## duas classes para não duplicar a mesma conta em dois lugares.
static func apply_block(amount: int, block: int) -> Dictionary:
	var remaining_damage = amount
	var remaining_block = block
	var blocked = 0

	if remaining_block > 0:
		blocked = min(remaining_block, remaining_damage)

		remaining_block -= blocked
		remaining_damage -= blocked

	return {
		"blocked": blocked,
		"remaining_damage": remaining_damage,
		"remaining_block": remaining_block
	}
