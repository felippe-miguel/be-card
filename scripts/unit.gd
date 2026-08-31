class_name Unit
extends RefCounted

enum Faction {
	ALLY,
	ENEMY
}

var id: String
var name: String
var hp: int

## max_hp = base_max_hp + received_max_hp_bonus. base_max_hp é o valor
## puro de UnitData; received_max_hp_bonus vem de auras de aliados
## adjacentes (Guardião) e é recalculado do zero a cada mudança no grid —
## ver BattleState.recalculate_auras()/set_received_max_hp_bonus().
var max_hp: int
var base_max_hp: int
var received_max_hp_bonus: int = 0
var block: int = 0
var faction: Faction

## Coordenadas no grid 3x3 da facção (sandbox de playtest — ver
## docs/playtest_3x3.md). lane = 0..2 (esquerda a direita), row = 0..2
## (0 = Front, 1 = Middle, 2 = Back). -1/-1 enquanto a unidade não está
## posicionada em nenhum andar.
var lane: int = -1
var row: int = -1
var attack: int

## Copiados de UnitData na criação (ver BattleState.create_unit()) — ver
## TargetSystem.get_pattern_attack_targets() para o que cada id de padrão
## faz.
var attack_pattern: String = "lane_front"
var attack_pattern_count: int = 1

## Copiado de UnitData — ver BattleState.recalculate_auras().
var aura_adjacent_ally_max_hp_bonus: int = 0

signal changed

func _init(
	unit_id: String,
	unit_name: String,
	max_health: int,
	unit_attack: int,
	unit_faction: Faction,
	unit_attack_pattern: String = "lane_front",
	unit_attack_pattern_count: int = 1,
	unit_aura_bonus: int = 0
) -> void:
	id = unit_id
	name = unit_name
	base_max_hp = max_health
	max_hp = max_health
	hp = max_health
	attack = unit_attack
	faction = unit_faction
	attack_pattern = unit_attack_pattern
	attack_pattern_count = unit_attack_pattern_count
	aura_adjacent_ally_max_hp_bonus = unit_aura_bonus

func attack_unit(target: Unit) -> void:
	if target == null:
		return
	
	print(name, " atacou ", target.name, " causando ", attack, " de dano.")
	
	target.take_damage(attack)

func take_damage(amount: int) -> void:
	var had_block = block > 0
	var result = CombatMath.apply_block(amount, block)

	block = result.remaining_block
	var remaining_damage = result.remaining_damage

	if had_block:
		print(name, " bloqueou ", result.blocked, " de dano.")

	if remaining_damage > 0:
		hp -= remaining_damage
	
	if hp < 0:
		hp = 0
	
	print(name, " recebeu ", remaining_damage, " de dano. HP: ", hp, "/", max_hp)
	
	changed.emit()

func heal(amount: int) -> void:
	hp += amount
	
	if hp > max_hp:
		hp = max_hp
	
	print(name, " recuperou ", amount, " de vida. HP: ", hp, "/", max_hp)
	
	changed.emit()

## Usado pelas cartas de reposicionamento/buff (Flanquear, Linha de
## Frente, Concentração — docs/playtest_3x3.md seção 5). Permanente
## (sem duração/expiração) de propósito, pelo mesmo motivo que o
## documento permite: velocidade de implementação para o playtest.
func modify_attack(amount: int) -> void:
	attack += amount

	if attack < 0:
		attack = 0

	print(name, " teve ATK alterado em ", amount, ". ATK: ", attack)

	changed.emit()

func add_block(amount: int) -> void:
	block += amount
	
	print(name, " ganhou ", amount, " de bloqueio. Block: ", block)
	
	changed.emit()

func is_dead() -> bool:
	return hp <= 0

## Chamado por BattleState.recalculate_auras() — new_bonus é o total já
## somado de todas as auras recebidas agora (não um delta incremental),
## já que a cada mudança no grid tudo é recalculado do zero, não
## acumulado aos poucos. hp acompanha a mudança (ganhar/perder a mesma
## quantidade que max_hp ganhou/perdeu), depois é limitado a [0, max_hp].
func set_received_max_hp_bonus(new_bonus: int) -> void:
	if new_bonus == received_max_hp_bonus:
		return

	var delta = new_bonus - received_max_hp_bonus

	received_max_hp_bonus = new_bonus
	max_hp = base_max_hp + received_max_hp_bonus
	hp = clampi(hp + delta, 0, max_hp)

	changed.emit()
