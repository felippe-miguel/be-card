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

## Status (docs/MECHANICS_EXECUTION_PLAN.md Etapa 1) — camada separada dos
## modificadores diretos já existentes (modify_attack()/
## set_received_max_hp_bonus()): representa um estado de gameplay
## (Strength/Weakness/Poison/Burn/Stun) guardado em stacks, status_id ->
## quantidade. Aplicar de novo um status já presente SOMA aos stacks
## existentes, nunca substitui — cada status define sua própria regra de
## quando/como os stacks são consumidos (ver
## BattleState.process_end_of_turn_statuses() para Poison/Burn e
## execute_unit_attack() para Stun).
var statuses: Dictionary = {}

## Nomes legíveis pra UI (UnitView) — ver get_status_summary().
const STATUS_DISPLAY_NAMES = {
	"strength": "Strength",
	"weakness": "Weakness",
	"poison": "Poison",
	"burn": "Burn",
	"stun": "Stun",
}

## Eventos/triggers (docs/MECHANICS_EXECUTION_PLAN.md Etapa 2) — copiados
## de UnitData.triggers na criação. Cada entrada: {"event": <id>, "effect":
## <Dictionary>}. A resolução em si (o que "self"/"trigger_target"/
## "lane_enemies" significam, como o efeito é aplicado) fica em
## BattleState.fire_event()/execute_trigger_effect() — Unit só carrega os
## dados, não sabe disparar sozinho.
var triggers: Array[Dictionary] = []

signal changed

## Emitido uma única vez, na transição de vivo pra morto (ver
## take_damage()) — BattleState conecta isto em wire_unit_events() pra
## disparar o evento ON_DEATH (docs/MECHANICS_EXECUTION_PLAN.md Etapa 2).
## Separado de "changed" de propósito: died precisa emitir ANTES de
## changed, enquanto lane/row ainda são válidos (ver take_damage()).
signal died

func _init(
	unit_id: String,
	unit_name: String,
	max_health: int,
	unit_attack: int,
	unit_faction: Faction,
	unit_attack_pattern: String = "lane_front",
	unit_attack_pattern_count: int = 1,
	unit_aura_bonus: int = 0,
	unit_triggers: Array[Dictionary] = []
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
	triggers = unit_triggers.duplicate(true)

func attack_unit(target: Unit) -> void:
	if target == null:
		return

	var effective_attack = get_effective_attack()

	print(name, " atacou ", target.name, " causando ", effective_attack, " de dano.")

	target.take_damage(effective_attack)

func take_damage(amount: int) -> void:
	var was_alive = not is_dead()
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

	## died emite ANTES de changed de propósito: BattleFloor remove a
	## unidade do grid reagindo a changed (ver BattleFloor._on_unit_
	## changed()), o que zera lane/row — quem ouve died (BattleState.
	## on_unit_died(), pro evento ON_DEATH) precisa da posição ainda válida.
	if was_alive and is_dead():
		died.emit()

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

func get_status_stacks(status_id: String) -> int:
	return statuses.get(status_id, 0)

func apply_status(status_id: String, stacks: int) -> void:
	if stacks <= 0:
		return

	statuses[status_id] = get_status_stacks(status_id) + stacks

	print(name, " recebeu ", stacks, " stack(s) de ", status_id, ". Total: ", statuses[status_id])

	changed.emit()

## Reduz stacks (Poison decai 1 por turno, Stun consome 1 ao ser pulado) —
## remove a entrada por completo ao chegar a zero ou menos.
func reduce_status(status_id: String, amount: int) -> void:
	if not statuses.has(status_id):
		return

	var remaining = get_status_stacks(status_id) - amount

	if remaining <= 0:
		statuses.erase(status_id)
	else:
		statuses[status_id] = remaining

	changed.emit()

func remove_status(status_id: String) -> void:
	if not statuses.has(status_id):
		return

	statuses.erase(status_id)

	changed.emit()

## Usado pela carta Cleanse — remove TODOS os status de uma vez.
## Simplificação deliberada: o documento não define escolha entre vários
## status presentes ao mesmo tempo, e "remover só um, à escolha do
## jogador" exigiria uma UI de seleção que foge do escopo desta etapa.
func clear_all_statuses() -> void:
	if statuses.is_empty():
		return

	statuses.clear()

	changed.emit()

## ATK efetivo = ATK base + Strength - Weakness, nunca negativo. Usado por
## attack_unit() (dano real) e pela UI (UnitView) — unit.attack continua
## sendo o valor base, só alterado por modify_attack() (Flanquear/Linha de
## Frente/Concentração).
func get_effective_attack() -> int:
	return maxi(0, attack + get_status_stacks("strength") - get_status_stacks("weakness"))

## Texto legível dos status ativos, ex.: "Strength 2, Poison 3" — "" quando
## não há nenhum. Ver UnitView.render_display().
func get_status_summary() -> String:
	if statuses.is_empty():
		return ""

	var parts: PackedStringArray = []

	for status_id in statuses:
		var display_name: String = STATUS_DISPLAY_NAMES.get(status_id, status_id.capitalize())

		parts.append("%s %d" % [display_name, statuses[status_id]])

	return ", ".join(parts)
