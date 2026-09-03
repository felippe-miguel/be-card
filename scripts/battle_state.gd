class_name BattleState
extends RefCounted

var battlefield: Battlefield
var pyre: Pyre
var unit_database: UnitDatabase
var target_system: TargetSystem

## true só enquanto clone_for_simulation() está reconstruindo o roster
## existente num clone novo — sem isto, colocar cada unidade no clone via
## place_unit_at() dispararia ON_SUMMON de novo pra unidades que já
## existiam há turnos, poluindo o preview do turno (docs/
## MECHANICS_EXECUTION_PLAN.md Etapa 2). Nunca true fora de
## clone_for_simulation().
var suppress_events: bool = false

func _init(battle_definition: BattleDefinition, database: UnitDatabase) -> void:
	unit_database = database
	
	battlefield = Battlefield.new(battle_definition.floors.size())
	
	pyre = Pyre.new("Pyre", 50)

	for floor_index in range(battle_definition.floors.size()):
		var floor_definition = battle_definition.floors[floor_index]
		var battle_floor = battlefield.get_floor(floor_index)
		
		for unit_definition in floor_definition.get("units", []):
			var unit_id = unit_definition.get("id", "")
			var faction_name = unit_definition.get("faction", "enemy")
			var faction = Unit.Faction.ENEMY

			if faction_name == "ally":
				faction = Unit.Faction.ALLY

			var unit = create_unit(unit_id, faction)

			if unit == null:
				continue

			var lane = unit_definition.get("lane", -1)
			var row = unit_definition.get("row", -1)

			if lane >= 0 and row >= 0:
				battle_floor.place_unit_at(unit, lane, row)
			else:
				battle_floor.add_unit(unit)
	
	target_system = TargetSystem.new(self)

	## Recalcula a aura do Guardião a cada mudança no grid (spawn,
	## morte/remoção, mover, trocar) — ver recalculate_auras(). Ligado
	## depois do loop de setup acima de propósito: o roster inicial ainda
	## não emitiu esses sinais pra ninguém ouvir, por isso a chamada
	## manual logo abaixo cobre esse caso.
	var main_floor = battlefield.get_floor(0)

	main_floor.unit_added.connect(func(_unit): recalculate_auras())
	main_floor.unit_removed.connect(func(_unit, _old_lane, _old_row): recalculate_auras())
	main_floor.unit_moved.connect(func(_unit, _old_lane, _old_row): recalculate_auras())

	## Eventos/triggers (docs/MECHANICS_EXECUTION_PLAN.md Etapa 2): ON_SUMMON
	## e ON_MOVE reaproveitam os mesmos sinais do BattleFloor que a aura já
	## escuta — pelo mesmo motivo (roster inicial não passa por eles, ver
	## comentário acima). ON_DEATH não usa sinal do BattleFloor (precisaria
	## de lane/row, que unit_removed já entrega zerados) — ver
	## wire_unit_events()/on_unit_died(), ligado por unidade em create_unit().
	main_floor.unit_added.connect(func(added_unit):
		if not suppress_events:
			fire_event(added_unit, "on_summon")
	)
	main_floor.unit_moved.connect(func(moved_unit, _old_lane, _old_row):
		if not suppress_events:
			fire_event(moved_unit, "on_move")
	)

	recalculate_auras()

## Toda unidade aliada nasce com o dobro de ATK/HP — compensação
## temporária e propositalmente grosseira pro loop de 4 waves de
## inimigos (Game.MAX_ENEMY_WAVES): a cada turno mais um inimigo entra
## no campo, então o lado aliado nunca cresce em número, só em força.
## "Por enquanto", pra facilitar o playtest — não é balanceamento final.
const ALLY_STAT_MULTIPLIER = 2

func create_unit(unit_id: String, faction: Unit.Faction) -> Unit:
	var unit_data = unit_database.units.get(unit_id)

	if unit_data == null:
		print("Unidade não encontrada: ", unit_id)

		return null

	var max_hp = unit_data.max_hp
	var attack = unit_data.attack

	if faction == Unit.Faction.ALLY:
		max_hp *= ALLY_STAT_MULTIPLIER
		attack *= ALLY_STAT_MULTIPLIER

	var unit = Unit.new(
		unit_data.id,
		unit_data.name,
		max_hp,
		attack,
		faction,
		unit_data.attack_pattern,
		unit_data.attack_pattern_count,
		unit_data.aura_adjacent_ally_max_hp_bonus,
		unit_data.triggers
	)

	for status_id in unit_data.initial_statuses:
		unit.apply_status(status_id, unit_data.initial_statuses[status_id])

	wire_unit_events(unit)

	return unit

## Liga o Unit.died desta unidade a on_unit_died() (evento ON_DEATH) —
## separado de create_unit() só pra poder ser reaproveitado por
## clone_for_simulation() também, que cria Units "na mão" (não via
## create_unit()) mas ainda quer o mesmo comportamento de evento no clone
## (senão o preview de turno erraria o efeito de triggers ON_DEATH/ON_HIT/
## etc. — ver docs/MECHANICS_EXECUTION_PLAN.md Etapa 2).
func wire_unit_events(unit: Unit) -> void:
	unit.died.connect(func(): on_unit_died(unit))

## Chamado por Unit.died assim que hp chega a 0 — ainda ANTES da remoção do
## grid (que só acontece reagindo a Unit.changed, emitido logo depois de
## died dentro de take_damage()), por isso lane/row/faction ainda são
## válidos aqui pra qualquer trigger ON_DEATH que precise de posição (ex.:
## Explosive, que causa dano aos inimigos da mesma lane).
func on_unit_died(unit: Unit) -> void:
	fire_event(unit, "on_death", {
		"lane": unit.lane,
		"row": unit.row,
		"faction": unit.faction,
	})

## Passiva do Guardião: recalcula do zero, para cada facção, o bônus de
## HP máximo que cada unidade recebe de auras de aliados adjacentes —
## nunca acumula incrementalmente, sempre soma tudo de novo a partir do
## estado atual do grid. Evita bugs de "esqueci de remover o bônus
## quando X saiu de perto" ao custo de ser O(unidades²) por chamada, o
## que é irrelevante com no máximo 9 unidades por facção.
func recalculate_auras() -> void:
	var battle_floor = battlefield.get_floor(0)

	for faction in [Unit.Faction.ALLY, Unit.Faction.ENEMY]:
		var units = battle_floor.get_units_for_faction(faction)
		var bonuses: Dictionary = {}

		for unit in units:
			bonuses[unit] = 0

		for unit in units:
			if unit.aura_adjacent_ally_max_hp_bonus == 0:
				continue

			for neighbor in battle_floor.get_adjacent_units(faction, unit.lane, unit.row):
				bonuses[neighbor] += unit.aura_adjacent_ally_max_hp_bonus

		for unit in units:
			unit.set_received_max_hp_bonus(bonuses[unit])

## Stun (docs/MECHANICS_EXECUTION_PLAN.md Etapa 1): impede o ataque deste
## turno e consome 1 stack — "Stun 1" pula exatamente um turno de ataque.
func execute_unit_attack(unit: Unit) -> void:
	if unit.get_status_stacks("stun") > 0:
		print(unit.name, " está atordoada(o) e perde o ataque deste turno.")
		unit.reduce_status("stun", 1)
		return

	var targets = target_system.get_pattern_attack_targets(unit)

	## ON_ATTACK dispara mesmo sem alvo válido — atacar não significa
	## necessariamente acertar (docs/MECHANICS_EXECUTION_PLAN.md Etapa 2).
	fire_event(unit, "on_attack")

	if targets.is_empty():
		print(unit.name, " (", unit.attack_pattern, ") não encontrou nenhum alvo.")
		return

	print(
		unit.name, " (", unit.attack_pattern, ") mira em: ",
		targets.map(func(t): return "%s [L%d/R%d]" % [t.name, t.lane, t.row])
	)

	for target in targets:
		unit.attack_unit(target)

		## ON_HIT só ocorre quando existe contato/dano válido — aqui, pra
		## cada alvo de verdade atingido (não pra ataques sem alvo, já
		## cobertos pelo ON_ATTACK acima).
		fire_event(unit, "on_hit", {"target": target})

		if target.is_dead():
			fire_event(unit, "on_kill", {"target": target})

## Fase de combate automática: cada Unit viva (aliada ou inimiga) ataca uma
## vez, andar por andar. Usa um snapshot de get_units() por andar para não
## ser afetado por remoções de unidades derrotadas durante a própria fase.
func execute_combat_phase() -> void:
	for battle_floor in battlefield.floors:
		var units = battle_floor.get_units()

		for unit in units:
			if unit.is_dead():
				continue

			execute_unit_attack(unit)

## Só a facção pedida ataca. Mesmo cuidado de snapshot que
## execute_combat_phase(). Base de execute_full_turn() logo abaixo.
func execute_faction_turn(faction: Unit.Faction) -> void:
	for battle_floor in battlefield.floors:
		var units = battle_floor.get_units_for_faction(faction)

		for unit in units:
			if unit.is_dead():
				continue

			execute_unit_attack(unit)

## Resolve o turno inteiro pro debug "Rodar turno" (docs/playtest_3x3.md
## seção 7): inimigos atacam primeiro, depois os aliados — ordem fixa,
## não é um sistema de iniciativa/velocidade de verdade.
func execute_full_turn() -> void:
	fire_event_all("on_turn_start")
	execute_faction_turn(Unit.Faction.ENEMY)
	execute_faction_turn(Unit.Faction.ALLY)
	process_end_of_turn_statuses()
	fire_event_all("on_turn_end")

## Poison e Burn são processados no fim do turno, depois que os dois lados
## já atacaram — os dois causam dano igual aos stacks atuais, mas decaem de
## formas diferentes (docs/MECHANICS_EXECUTION_PLAN.md Etapa 1): Poison
## reduz 1 stack por vez, Burn é consumido por completo numa única
## aplicação. Snapshot via get_units() de propósito (mesmo cuidado que
## execute_combat_phase()): unidades que morrem de Poison/Burn são
## removidas do grid na hora (Unit.changed -> BattleFloor._on_unit_
## changed()), o que não pode bagunçar este loop.
func process_end_of_turn_statuses() -> void:
	for battle_floor in battlefield.floors:
		for unit in battle_floor.get_units():
			if unit.is_dead():
				continue

			var poison_stacks = unit.get_status_stacks("poison")

			if poison_stacks > 0:
				print(unit.name, " sofre ", poison_stacks, " de dano de Poison.")
				unit.take_damage(poison_stacks)
				unit.reduce_status("poison", 1)

			if unit.is_dead():
				continue

			var burn_stacks = unit.get_status_stacks("burn")

			if burn_stacks > 0:
				print(unit.name, " sofre ", burn_stacks, " de dano de Burn.")
				unit.take_damage(burn_stacks)
				unit.remove_status("burn")

## Sistema de eventos/triggers (docs/MECHANICS_EXECUTION_PLAN.md Etapa 2):
## cada Unit carrega sua lista de triggers (copiada de UnitData na criação
## — ver create_unit()), cada uma {"event": <id>, "effect": <Dictionary>}.
## fire_event() dispara, pra UMA unidade, todo trigger dela que escute
## event_name. Deliberadamente não é um sistema universal (ver Princípio 3
## do documento) — só um dicionário de evento -> efeito, resolvido por
## execute_trigger_effect() logo abaixo.
func fire_event(unit: Unit, event_name: String, context: Dictionary = {}) -> void:
	for trigger in unit.triggers:
		if trigger.get("event", "") != event_name:
			continue

		print(unit.name, " disparou trigger '", event_name, "'.")

		execute_trigger_effect(unit, trigger.get("effect", {}), context)

## Dispara event_name pra toda unidade viva no andar — usado pelos eventos
## sem uma unidade "dona" natural (ON_TURN_START/ON_TURN_END/ON_CARD_
## PLAYED). Snapshot via get_units(), mesmo cuidado de sempre: nenhuma
## unidade que morrer durante o disparo bagunça o loop.
func fire_event_all(event_name: String, context: Dictionary = {}) -> void:
	for unit in battlefield.get_floor(0).get_units():
		if not unit.is_dead():
			fire_event(unit, event_name, context)

## Resolve "quem é o alvo" de um efeito de TRIGGER — vocabulário separado
## do de CARTA (TargetSystem.get_card_targets()/EffectSystem.execute_
## effect()), porque os alvos possíveis aqui vêm do próprio evento, não de
## uma escolha do jogador:
## - "self": a unidade dona do trigger.
## - "trigger_target": a unidade envolvida no evento (quem foi atingido/
##   morto — ver context["target"] em fire_event() nas chamadas de
##   execute_unit_attack()). Ignorado se já estiver morta.
## - "lane_enemies": inimigos (facção oposta à de context["faction"]) na
##   mesma lane de context["lane"] — usado por ON_DEATH (Explosive), cuja
##   posição vem de on_unit_died() (capturada antes da remoção do grid).
## O efeito em si (damage/heal/block/apply_status/cleanse) é aplicado por
## EffectSystem.apply_basic_effect() — reaproveitado também pelas cartas,
## só a resolução de alvo muda entre os dois contextos.
func execute_trigger_effect(effect_owner: Unit, effect: Dictionary, context: Dictionary) -> void:
	if effect.is_empty():
		return

	var target_key: String = effect.get("target", "self")
	var targets: Array[Unit] = []

	match target_key:
		"self":
			targets = [effect_owner]

		"trigger_target":
			var context_target: Unit = context.get("target")

			if context_target != null and not context_target.is_dead():
				targets = [context_target]

		"lane_enemies":
			var lane: int = context.get("lane", -1)
			var faction: Unit.Faction = context.get("faction", effect_owner.faction)

			if lane >= 0:
				var opposite_faction = target_system.get_opposite_faction(faction)

				targets = battlefield.get_floor(0).get_lane_units(opposite_faction, lane)

		_:
			print("Alvo de trigger desconhecido: ", target_key)

	if targets.is_empty():
		return

	EffectSystem.apply_basic_effect(effect.get("type", ""), targets, effect)

## Preview do checkbox "Rodar turno" (ver Game.update_turn_preview()):
## simula execute_full_turn() num clone completo e isolado do estado
## atual, sem tocar em nada real. Retorna, pra cada Unit REAL ainda no
## campo, {"hp": ..., "block": ...} previstos; uma unidade ausente do
## dicionário significa que ela morreria nessa simulação.
func simulate_full_turn() -> Dictionary:
	var clone = clone_for_simulation()

	clone.execute_full_turn()

	var predictions: Dictionary = {}
	var real_floor = battlefield.get_floor(0)
	var clone_floor = clone.battlefield.get_floor(0)

	for unit in real_floor.get_units():
		var clone_unit = clone_floor.get_unit_at(unit.faction, unit.lane, unit.row)

		if clone_unit != null:
			predictions[unit] = {"hp": clone_unit.hp, "block": clone_unit.block}

	return predictions

## Clone raso e totalmente independente do BattleState atual (mesmo
## grid/posições/stats, mas outro Battlefield/outras Units) — mutar o
## clone (via simulate_full_turn() acima) nunca afeta o original. Usado
## só para simulação; nunca deve ser exposto fora dela.
func clone_for_simulation() -> BattleState:
	var clone = BattleState.new(BattleDefinition.empty(), unit_database)
	var source_units = battlefield.get_floor(0).get_units()
	var clone_floor = clone.battlefield.get_floor(0)
	var unit_clones: Array[Unit] = []

	## Reconstruir o roster existente no clone não é um summon de verdade
	## (essas unidades já estavam em campo há turnos) — suprime ON_SUMMON/
	## ON_MOVE enquanto isto roda, senão o preview do turno dispararia esses
	## triggers de novo só por causa da reconstrução.
	clone.suppress_events = true

	for source_unit in source_units:
		var unit_clone = Unit.new(
			source_unit.id,
			source_unit.name,
			source_unit.base_max_hp,
			source_unit.attack,
			source_unit.faction,
			source_unit.attack_pattern,
			source_unit.attack_pattern_count,
			source_unit.aura_adjacent_ally_max_hp_bonus,
			source_unit.triggers
		)

		## Sem isto, o clone nunca dispararia ON_DEATH (nem qualquer outro
		## evento que dependa de Unit.died) — o preview de turno erraria
		## qualquer coisa que um trigger causasse (ex.: Explosive matando
		## outra unidade na simulação).
		clone.wire_unit_events(unit_clone)

		clone_floor.place_unit_at(unit_clone, source_unit.lane, source_unit.row)
		unit_clones.append(unit_clone)

	## hp/block reais são copiados só depois de todo mundo posicionado,
	## pra não serem sobrescritos pelo recálculo de aura que roda a cada
	## place_unit_at() (mexe em hp/max_hp via set_received_max_hp_bonus()).
	for i in range(source_units.size()):
		unit_clones[i].hp = source_units[i].hp
		unit_clones[i].block = source_units[i].block
		unit_clones[i].statuses = source_units[i].statuses.duplicate()

	## A simulação em si (clone.execute_full_turn(), chamada por quem pediu
	## este clone) deve disparar eventos normalmente — só a reconstrução
	## acima era o problema.
	clone.suppress_events = false

	return clone

func count_units_for_faction(faction: Unit.Faction) -> int:
	var count = 0

	for battle_floor in battlefield.floors:
		count += battle_floor.get_units_for_faction(faction).size()

	return count

## Derrota: nenhum aliado restou vivo em nenhum andar. O Pyre ainda não
## participa dessa conta — cartas/ataques ainda não conseguem miná-lo.
func is_defeat() -> bool:
	return count_units_for_faction(Unit.Faction.ALLY) == 0

## Vitória: nenhum inimigo restou vivo em nenhum andar.
func is_victory() -> bool:
	return count_units_for_faction(Unit.Faction.ENEMY) == 0
