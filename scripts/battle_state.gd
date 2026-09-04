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

## Preenchido só num clone criado por clone_for_simulation() (Unit real do
## BattleState original -> Unit clone correspondente neste). Ver
## simulate_full_turn() — desde que efeitos de trigger podem mover uma
## unidade durante o próprio turno simulado (Empurrão — docs/
## MECHANICS_EXECUTION_PLAN.md Etapa 3), procurar o clone pela POSIÇÃO
## real (lane/row de antes do turno) não é confiável: a unidade pode não
## estar mais lá depois de ser empurrada, mesmo viva. Esta identidade
## direta não depende de posição nenhuma.
var simulation_origin_map: Dictionary = {}

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

	## Combinação "Posição + Modificador" (docs/MECHANICS_EXECUTION_PLAN.md
	## Etapa 5) — mesma técnica e os mesmos sinais da aura acima, não é um
	## "evento" (nunca suprimido por suppress_events): é um modificador
	## derivado, sempre recalculado do zero a partir do grid atual.
	main_floor.unit_added.connect(func(_unit): recalculate_position_modifiers())
	main_floor.unit_removed.connect(func(_unit, _old_lane, _old_row): recalculate_position_modifiers())
	main_floor.unit_moved.connect(func(_unit, _old_lane, _old_row): recalculate_position_modifiers())

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
	main_floor.unit_moved.connect(func(moved_unit, old_lane, old_row):
		## Combinação "Movimento + Ataque" (Etapa 5): "avançou" = moveu pra
		## uma row MENOR (em direção à Front), não importa a facção — quem
		## chama decide o sentido junto com quem move (ex.: Empurrão
		## empurra pra trás, row aumenta, nunca conta como avanço). Marcado
		## sempre, mesmo com suppress_events (não é um evento de trigger,
		## é só um registro de fato ocorrido, igual à aura acima) — resetado
		## no início de cada turno (ver execute_full_turn()).
		if moved_unit.row < old_row:
			moved_unit.advanced_this_turn = true

		if not suppress_events:
			fire_event(moved_unit, "on_move")
	)

	recalculate_auras()
	recalculate_position_modifiers()

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
		unit_data.triggers,
		unit_data.back_row_attack_bonus,
		unit_data.advance_attack_bonus,
		unit_data.description
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

## Chamado por Unit.died assim que hp chega a 0 — ainda ANTES da remoção
## "reativa" do grid (que só aconteceria depois, reagindo a Unit.changed,
## emitido logo depois de died dentro de take_damage()). Captura lane/row/
## faction ANTES de remover (usados pelo context de ON_DEATH — Explosive/
## Sacrifice/Revenge miram por posição/facção, não pela unidade em si), e
## remove do grid AGORA, explicitamente, em vez de esperar a reação normal
## — Death Spawn (docs/MECHANICS_EXECUTION_PLAN.md Etapa 4) invoca outra
## unidade na MESMA célula de quem morreu, e isso só é possível se a
## célula já estiver livre quando o trigger ON_DEATH rodar. remove_unit()
## chamado de novo depois (reagindo a changed) é um no-op seguro — a
## unidade já não está mais na célula (ver BattleFloor.remove_unit()).
func on_unit_died(unit: Unit) -> void:
	var context = {
		"lane": unit.lane,
		"row": unit.row,
		"faction": unit.faction,
	}

	battlefield.get_floor(0).remove_unit(unit)

	fire_event(unit, "on_death", context)

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

## Combinação "Posição + Modificador" (docs/MECHANICS_EXECUTION_PLAN.md
## Etapa 5): recalcula do zero, pra cada unidade com back_row_attack_bonus
## > 0, se ela está na Back agora ou não — mesma técnica/motivo de
## recalculate_auras() acima (sempre do zero, nunca incremental).
func recalculate_position_modifiers() -> void:
	var battle_floor = battlefield.get_floor(0)

	for unit in battle_floor.get_units():
		if unit.back_row_attack_bonus == 0:
			continue

		var bonus = unit.back_row_attack_bonus if unit.row == BattleFloor.Row.BACK else 0

		unit.set_position_attack_bonus(bonus)

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
		## hp_before/depois mede o dano líquido (já descontado o block) que
		## de fato chegou no alvo — usado por triggers ON_HIT que reagem à
		## quantidade real de dano causada (ex.: Vampírico, "cura pelo dano
		## causado" — docs/MECHANICS_EXECUTION_PLAN.md Etapa 3), não ao
		## ATK bruto do atacante.
		var hp_before = target.hp

		unit.attack_unit(target)

		var damage_dealt = hp_before - target.hp

		## ON_HIT só ocorre quando existe contato/dano válido — aqui, pra
		## cada alvo de verdade atingido (não pra ataques sem alvo, já
		## cobertos pelo ON_ATTACK acima). Funciona por alvo mesmo em
		## ataques de área (attack_pattern_count > 1, ou padrões como
		## primary_plus_adjacent_row): este for já resolve um alvo de cada
		## vez.
		fire_event(unit, "on_hit", {"target": target, "damage_dealt": damage_dealt})

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

	## Combinação "Movimento + Ataque" (Etapa 5): advanced_this_turn some no
	## fim do turno que ele beneficiou — reseta por último (não antes do
	## combate acima, que é exatamente quem precisa lê-lo) pra começar o
	## PRÓXIMO turno "limpo", pronto pra registrar os movimentos daquele
	## turno (cartas de movimento jogadas antes do próximo "Rodar turno").
	for unit in battlefield.get_floor(0).get_units():
		unit.advanced_this_turn = false

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

		if not trigger_condition_met(unit, trigger.get("condition", {})):
			continue

		print(unit.name, " disparou trigger '", event_name, "'.")

		execute_trigger_effect(unit, trigger.get("effect", {}), context)

## Combinação "Summon + Posição" (docs/MECHANICS_EXECUTION_PLAN.md Etapa 5:
## "ao ser invocado na Front, ganha Strength") — não um motor de condições
## genérico, só a ÚNICA chave que existe necessidade real agora ("row").
## condition vazio (a grande maioria dos triggers) sempre passa.
func trigger_condition_met(unit: Unit, condition: Dictionary) -> bool:
	if condition.is_empty():
		return true

	if condition.has("row") and unit.row != int(condition["row"]):
		return false

	return true

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
## - "lane_allies": mesma ideia, mas aliados (mesma facção de context
##   ["faction"]) na mesma lane — usado por ON_DEATH (Sacrifice). Mira
##   TODOS os aliados da lane, não escolhe "o" aliado — mesma simplificação
##   deliberada de lane_enemies (ver Explosive), evitando lógica de
##   escolha (ex.: "o de menor HP") sem necessidade real ainda.
## - "all_allies"/"all_enemies": toda unidade viva da facção (ou da oposta)
##   de context["faction"], em qualquer lane — usado por ON_DEATH (Revenge:
##   "todos os aliados ganham Strength 1"). Reaproveita TargetSystem.
##   get_units_by_faction(), o mesmo usado por cartas "all_enemies"/
##   "all_allies" (docs/MECHANICS_EXECUTION_PLAN.md Etapa 4).
## - "adjacent_allies" (Etapa 5 — "aliados adjacentes ganham Block"): usa
##   a posição ATUAL de effect_owner (não context — ao contrário de ON_
##   DEATH, quem dispara isto normalmente ainda está no grid, ex.: ON_
##   SUMMON), reaproveitando BattleFloor.get_adjacent_units(), a mesma
##   varredura ortogonal da aura do Guardião.
func resolve_trigger_targets(target_key: String, effect_owner: Unit, context: Dictionary) -> Array[Unit]:
	var context_faction: Unit.Faction = context.get("faction", effect_owner.faction)

	match target_key:
		"self":
			return [effect_owner]

		"trigger_target":
			var context_target: Unit = context.get("target")

			if context_target != null and not context_target.is_dead():
				return [context_target]

			return []

		"lane_enemies":
			var lane: int = context.get("lane", -1)

			if lane < 0:
				return []

			return battlefield.get_floor(0).get_lane_units(target_system.get_opposite_faction(context_faction), lane)

		"lane_allies":
			var lane: int = context.get("lane", -1)

			if lane < 0:
				return []

			return battlefield.get_floor(0).get_lane_units(context_faction, lane)

		"all_allies":
			return target_system.get_units_by_faction(context_faction)

		"all_enemies":
			return target_system.get_units_by_faction(target_system.get_opposite_faction(context_faction))

		"adjacent_allies":
			return battlefield.get_floor(0).get_adjacent_units(effect_owner.faction, effect_owner.lane, effect_owner.row)

		_:
			print("Alvo de trigger desconhecido: ", target_key)
			return []

## Aplica o efeito de um trigger. Três efeitos merecem tratamento à parte
## antes (ou em vez) de cair no vocabulário genérico de resolve_trigger_
## targets()/EffectSystem.apply_basic_effect():
## - "summon" (Death Spawn — docs/MECHANICS_EXECUTION_PLAN.md Etapa 4) não
##   afeta uma lista de alvos existentes, cria uma unidade nova — por isso
##   é resolvido ANTES de resolve_trigger_targets(), direto na célula de
##   context["lane"]/["row"] (a de quem morreu; on_unit_died() já a deixou
##   livre antes de disparar ON_DEATH — ver comentário lá).
## - "move" (Etapa 3) também não é um efeito básico (mexe em posição, não
##   em stats) — usa BattleFloor.move_unit() direto, igual às cartas de
##   movimento já fazem; move_unit() já recusa sozinho sair do grid ou
##   cair numa célula ocupada (Knockback: empurra o alvo).
## - "amount": "damage_dealt" (Etapa 3) é resolvido pro valor real de
##   context["damage_dealt"] (Vampírico: "cura pelo dano causado", só
##   disponível como contexto de ON_HIT — ver execute_unit_attack()).
func execute_trigger_effect(effect_owner: Unit, effect: Dictionary, context: Dictionary) -> void:
	if effect.is_empty():
		return

	var type: String = effect.get("type", "")

	if type == "summon":
		execute_trigger_summon_effect(effect, context, effect_owner)
		return

	var targets = resolve_trigger_targets(effect.get("target", "self"), effect_owner, context)

	if targets.is_empty():
		return

	if type == "move":
		var row_delta: int = effect.get("row_delta", 1)
		var battle_floor = battlefield.get_floor(0)

		for target in targets:
			battle_floor.move_unit(target, target.lane, target.row + row_delta)

		return

	var resolved_effect = effect
	var amount = effect.get("amount", null)

	## Checa o tipo ANTES de comparar com a string "damage_dealt" — "amount"
	## normalmente é um número (JSON sempre entrega float, mesmo pra
	## valores inteiros), e comparar float == String com "==" lança "Invalid
	## operands" no GDScript, em vez de simplesmente dar false.
	if typeof(amount) == TYPE_STRING and amount == "damage_dealt":
		resolved_effect = effect.duplicate()
		resolved_effect["amount"] = context.get("damage_dealt", 0)

	EffectSystem.apply_basic_effect(type, targets, resolved_effect)

## Death Spawn (docs/MECHANICS_EXECUTION_PLAN.md Etapa 4): invoca effect
## ["unit"] na célula de quem morreu (context["lane"]/["row"], da mesma
## facção — context["faction"]). Silenciosamente não faz nada se a unidade
## não existir ou a célula estiver ocupada (create_unit()/place_unit_at()
## já cuidam disso sozinhos, mesma robustez de qualquer summon de carta).
func execute_trigger_summon_effect(effect: Dictionary, context: Dictionary, effect_owner: Unit) -> void:
	var lane: int = context.get("lane", -1)
	var row: int = context.get("row", -1)

	if lane < 0 or row < 0:
		return

	var faction: Unit.Faction = context.get("faction", effect_owner.faction)
	var new_unit = create_unit(effect.get("unit", ""), faction)

	if new_unit == null:
		return

	battlefield.get_floor(0).place_unit_at(new_unit, lane, row)

## Preview do checkbox "Rodar turno" (ver Game.update_turn_preview()):
## simula execute_full_turn() num clone completo e isolado do estado
## atual, sem tocar em nada real. Retorna, pra cada Unit REAL ainda no
## campo, {"hp": ..., "block": ...} previstos; uma unidade ausente do
## dicionário significa que ela morreria nessa simulação.
func simulate_full_turn() -> Dictionary:
	var clone = clone_for_simulation()

	clone.execute_full_turn()

	var predictions: Dictionary = {}

	## Identidade direta (simulation_origin_map), não posição — um efeito
	## de trigger pode mover a unidade DURANTE o próprio turno simulado
	## (Empurrão — docs/MECHANICS_EXECUTION_PLAN.md Etapa 3), então a
	## célula onde ela estava antes do turno pode não ter mais ninguém
	## mesmo que a unidade tenha sobrevivido (só foi empurrada). Antes
	## disso usava get_unit_at(faction, lane, row) e tratava "empurrada
	## pra outra célula" como "morreu" por engano.
	for unit in battlefield.get_floor(0).get_units():
		var clone_unit: Unit = clone.simulation_origin_map.get(unit)

		if clone_unit != null and not clone_unit.is_dead():
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
		## source_unit.attack já inclui position_attack_bonus "assado" nele
		## (mesma técnica de base_max_hp acima, que exclui de propósito o
		## bônus de aura) — subtrai aqui pra recalculate_position_modifiers()
		## reaplicar do zero, reagindo ao place_unit_at() logo abaixo, sem
		## contar o bônus em dobro (base limpa + bônus de novo).
		var unit_clone = Unit.new(
			source_unit.id,
			source_unit.name,
			source_unit.base_max_hp,
			source_unit.attack - source_unit.position_attack_bonus,
			source_unit.faction,
			source_unit.attack_pattern,
			source_unit.attack_pattern_count,
			source_unit.aura_adjacent_ally_max_hp_bonus,
			source_unit.triggers,
			source_unit.back_row_attack_bonus,
			source_unit.advance_attack_bonus,
			source_unit.description
		)

		## Sem isto, o clone nunca dispararia ON_DEATH (nem qualquer outro
		## evento que dependa de Unit.died) — o preview de turno erraria
		## qualquer coisa que um trigger causasse (ex.: Explosive matando
		## outra unidade na simulação).
		clone.wire_unit_events(unit_clone)

		clone_floor.place_unit_at(unit_clone, source_unit.lane, source_unit.row)
		unit_clones.append(unit_clone)
		clone.simulation_origin_map[source_unit] = unit_clone

	## hp/block reais são copiados só depois de todo mundo posicionado,
	## pra não serem sobrescritos pelo recálculo de aura que roda a cada
	## place_unit_at() (mexe em hp/max_hp via set_received_max_hp_bonus()).
	for i in range(source_units.size()):
		unit_clones[i].hp = source_units[i].hp
		unit_clones[i].block = source_units[i].block
		unit_clones[i].statuses = source_units[i].statuses.duplicate()
		unit_clones[i].advanced_this_turn = source_units[i].advanced_this_turn

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
