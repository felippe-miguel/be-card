class_name EffectSystem
extends RefCounted

var battle_state: BattleState
var target_system: TargetSystem

func _init(state: BattleState) -> void:
	battle_state = state
	target_system = state.target_system

## selected_lane/selected_row substituem o antigo selected_floor/
## selected_position agora que o sandbox 3x3 só tem um andar (ver
## docs/playtest_3x3.md) e uma posição é sempre uma célula (lane, row).
func execute_effect(
	effect: Dictionary,
	selected_unit: Unit = null,
	selected_lane: int = -1,
	selected_row: int = -1
) -> void:
	var type = effect.get("type", "")
	var target_type = effect.get("target", "")
	var target_faction: String = effect.get("target_faction", "")
	var targets: Array[Unit] = []

	if type != "summon":
		targets = target_system.get_card_targets(
			target_type,
			selected_unit,
			target_faction
		)

		if target_type == "selected_unit" and targets.is_empty():
			print("Efeito precisa de uma unidade selecionada!")
			return

	if type == "summon":
		execute_summon_effect(effect, selected_lane, selected_row)
		return

	## Golpe de Escudo precisa de um alvo derivado (o inimigo da lane do
	## aliado escolhido), que só o TargetSystem desta instância sabe achar —
	## por isso não é um "efeito básico" estático (ver apply_basic_effect()).
	if type == "shield_bash":
		execute_shield_bash(targets)
		return

	apply_basic_effect(type, targets, effect)

func execute_summon_effect(effect: Dictionary, selected_lane: int, selected_row: int) -> void:
	var unit_id = effect.get("unit", "")
	var unit_data = battle_state.unit_database.units.get(unit_id)

	if unit_data == null:
		print("Unidade não encontrada: ", unit_id)
		return

	var unit = battle_state.create_unit(unit_id, Unit.Faction.ALLY)
	var battle_floor = battle_state.battlefield.get_floor(0)

	if battle_floor == null:
		return

	var placed: bool

	if selected_lane >= 0 and selected_row >= 0:
		placed = battle_floor.place_unit_at(unit, selected_lane, selected_row)
	else:
		placed = battle_floor.add_unit(unit)

	if not placed:
		print("Célula ocupada ou grid cheio!")
		return

	print(
		"Invocado: ", unit.name,
		" em Lane ", unit.lane,
		" Row ", unit.row
	)

## Golpe de Escudo (docs/CARDS_EXECUTION_PLAN.md Passo 4.3): cada aliado
## escolhido causa dano igual ao próprio Block ao primeiro inimigo da lane
## dele (mesma varredura Front -> Back de "lane_front"). O Block não é
## consumido. Dano comum (take_damage), sem atribuição ao aliado — então
## ON_KILL/ON_HIT dele não disparam; sem inimigo na lane ou sem Block, nada
## acontece (a carta é gasta mesmo assim).
func execute_shield_bash(targets: Array[Unit]) -> void:
	for ally in targets:
		if ally.block <= 0:
			continue

		var lane_enemies = target_system.get_battle_floor().get_lane_units(
			target_system.get_opposite_faction(ally.faction),
			ally.lane
		)

		if lane_enemies.is_empty():
			continue

		lane_enemies.front().take_damage(ally.block)

## Aplica um efeito básico (damage/heal/block/apply_status/cleanse/
## remove_status/modify_attack/double_status/detonate_poison) já resolvido numa lista de alvos —
## reaproveitado tanto por execute_effect()
## acima (alvos vêm do vocabulário de CARTA: selected_unit/all_enemies/
## all_allies) quanto por BattleState.execute_trigger_effect() (alvos vêm
## do vocabulário de EVENTO/TRIGGER: self/trigger_target/lane_enemies —
## ver docs/MECHANICS_EXECUTION_PLAN.md Etapa 2). static porque nenhum dos
## dois precisa de uma instância de EffectSystem pra só aplicar o efeito
## numa lista de alvos já pronta. summon não é um "efeito básico" (não tem
## uma lista de alvos, cria uma unidade nova) — fica de fora de propósito,
## resolvido só por execute_summon_effect() acima.
static func apply_basic_effect(type: String, targets: Array[Unit], effect: Dictionary) -> void:
	match type:
		"damage":
			var amount = effect.get("amount", 0)

			for target in targets:
				target.take_damage(amount)

		"block":
			var amount = effect.get("amount", 0)

			for target in targets:
				target.add_block(amount)

		"heal":
			var amount = effect.get("amount", 0)

			for target in targets:
				target.heal(amount)

		"apply_status":
			var status_id: String = effect.get("status", "")
			var stacks = effect.get("stacks", 1)

			for target in targets:
				target.apply_status(status_id, stacks)

		"cleanse":
			for target in targets:
				target.clear_all_statuses()

		## Etapa 3 (docs/MECHANICS_EXECUTION_PLAN.md) completa o vocabulário
		## de efeitos: RemoveStatus (um status específico, diferente de
		## Cleanse acima, que remove todos) e ModifyAttack (o modificador
		## ad-hoc que já existia desde antes da Etapa 1 — ver Unit.
		## modify_attack()), agora também disponível como efeito de
		## trigger/carta.
		"remove_status":
			var status_id: String = effect.get("status", "")

			for target in targets:
				target.remove_status(status_id)

		"modify_attack":
			var amount = effect.get("amount", 0)

			for target in targets:
				target.modify_attack(amount)

		## Fúria Dobrada (docs/CARDS_EXECUTION_PLAN.md Passo 4.1): soma de
		## novo os stacks atuais do status. Sem o status, nada acontece.
		"double_status":
			var status_id: String = effect.get("status", "")

			for target in targets:
				target.apply_status(status_id, target.get_status_stacks(status_id))

		## Detonar Toxina (Passo 4.2): dano normal (respeita Block) igual
		## aos stacks de Poison, e o Poison some. Sem Poison, nada acontece.
		## Remove antes de causar o dano pra não mexer no status de uma
		## unidade que o dano acabou de matar.
		"detonate_poison":
			for target in targets:
				var poison_stacks = target.get_status_stacks("poison")

				if poison_stacks <= 0:
					continue

				target.remove_status("poison")
				target.take_damage(poison_stacks)

		_:
			print("Efeito desconhecido: ", type)

func can_target_selected_unit(effect: Dictionary, selected_unit: Unit) -> bool:
	if effect.get("target", "") != "selected_unit":
		return true

	var target_faction: String = effect.get("target_faction", "")
	var targets = target_system.get_card_targets(
		"selected_unit",
		selected_unit,
		target_faction
	)

	return not targets.is_empty()
