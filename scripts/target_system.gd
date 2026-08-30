class_name TargetSystem
extends RefCounted

var battle_state: BattleState

func _init(state: BattleState) -> void:
	battle_state = state

# ==========================================
# ATTACK PATTERNS (docs/playtest_3x3.md seção 3/4)
# ==========================================
## Ponto de entrada usado por BattleState.execute_unit_attack(). Cada
## padrão é identificado por uma string (Unit.attack_pattern, copiada de
## UnitData) em vez de um TargetRule.Shape — os padrões deste sandbox são
## algorítmicos (dependem de varrer a lane do atacante, achar o alvo mais
## distante, espelhar a row de um alvo já encontrado nas lanes vizinhas
## etc.), não simples formas fixas. TargetRule.Shape continua existindo
## para o uso mais simples de get_attack_targets() logo abaixo.
func get_pattern_attack_targets(attacker: Unit) -> Array[Unit]:
	var target_faction = get_opposite_faction(attacker.faction)
	var count = max(1, attacker.attack_pattern_count)

	match attacker.attack_pattern:
		## Guerreiro/Guardião: o(s) primeiro(s) ocupado(s) da própria lane,
		## procurando Front -> Back. attack_pattern_count > 1 é o
		## Lanceiro ("os dois primeiros inimigos da mesma lane").
		"lane_front":
			return take_first(get_battle_floor().get_lane_units(target_faction, attacker.lane), count)

		## Arqueiro: o(s) mais distante(s) da própria lane, procurando
		## Back -> Front.
		"lane_rear":
			var lane_units = get_battle_floor().get_lane_units(target_faction, attacker.lane)

			lane_units.reverse()

			return take_first(lane_units, count)

		## Assassino: a unidade mais ao fundo (maior row) entre as duas
		## lanes vizinhas à do atacante — nunca a própria lane.
		"adjacent_lanes_furthest":
			return get_adjacent_lanes_furthest(target_faction, attacker.lane)

		## Mago: o primeiro alvo da própria lane (igual "lane_front" com
		## count 1) mais quem estiver na mesma row nas lanes vizinhas —
		## naturalmente limitado pelo grid quando o alvo está numa lane
		## de borda.
		"primary_plus_adjacent_row":
			return get_primary_plus_adjacent_row(target_faction, attacker.lane)

		_:
			print("Padrão de ataque desconhecido: ", attacker.attack_pattern)
			return []

func take_first(units: Array[Unit], count: int) -> Array[Unit]:
	if units.size() <= count:
		return units

	return units.slice(0, count)

## Descrições legíveis dos padrões acima, para UI (hover de combate — ver
## Game._on_unit_hover_started()/BattleFloorView.set_pattern_info()).
## Mantidas ao lado da implementação de cada padrão de propósito, pra não
## desalinhar se a lógica mudar.
const PATTERN_DESCRIPTIONS = {
	"lane_front": "Mira o(s) primeiro(s) inimigo(s) da própria lane, procurando da Front para a Back.",
	"lane_rear": "Mira o(s) inimigo(s) mais distante(s) da própria lane, procurando da Back para a Front.",
	"adjacent_lanes_furthest": "Ignora a própria lane. Olha as duas lanes vizinhas (só uma, se estiver numa lane de borda) e mira o inimigo mais ao fundo (maior row) entre os candidatos das duas.",
	"primary_plus_adjacent_row": "Mira o primeiro inimigo da própria lane (Front → Back) e também quem estiver na MESMA row nas lanes vizinhas — naturalmente limitado pelo grid quando o alvo está numa lane de borda.",
}

func describe_pattern(pattern_id: String, count: int = 1) -> String:
	var description: String = PATTERN_DESCRIPTIONS.get(pattern_id, "Padrão de ataque desconhecido: %s" % pattern_id)

	if count > 1:
		description += "\n\nPega os %d primeiros alvos encontrados nessa varredura, não só o primeiro." % count

	return description

func get_adjacent_lanes_furthest(faction: Unit.Faction, lane: int) -> Array[Unit]:
	var battle_floor = get_battle_floor()
	var candidates: Array[Unit] = []

	for adjacent_lane in BattleFloor.adjacent_lanes(lane):
		candidates.append_array(battle_floor.get_lane_units(faction, adjacent_lane))

	if candidates.is_empty():
		return []

	var furthest = candidates.front()

	for unit in candidates:
		if unit.row > furthest.row:
			furthest = unit

	return [furthest]

func get_primary_plus_adjacent_row(faction: Unit.Faction, lane: int) -> Array[Unit]:
	var battle_floor = get_battle_floor()
	var lane_units = battle_floor.get_lane_units(faction, lane)

	if lane_units.is_empty():
		return []

	var primary = lane_units.front()
	var targets: Array[Unit] = [primary]

	for adjacent_lane in BattleFloor.adjacent_lanes(lane):
		var unit = battle_floor.get_unit_at(faction, adjacent_lane, primary.row)

		if unit != null:
			targets.append(unit)

	return targets

# ==========================================
# UNIT ATTACK TARGETING (legado, TargetRule.Shape)
# ==========================================
## FRONT/REAR/ALL, já com escopo de lane — reaproveitado por
## get_pattern_attack_targets() acima só indiretamente (cada padrão
## consulta BattleFloor diretamente); mantido para qualquer efeito futuro
## que precise de uma forma simples sem passar pelo vocabulário de
## padrões.
func get_attack_targets(attacker: Unit, shape: TargetRule.Shape) -> Array[Unit]:
	var target_faction = get_opposite_faction(
		attacker.faction
	)

	match shape:
		TargetRule.Shape.FRONT:
			return get_front_units(target_faction, attacker.lane)

		TargetRule.Shape.REAR:
			return get_rear_units(target_faction, attacker.lane)

		TargetRule.Shape.ALL:
			return get_lane_targets(target_faction, attacker.lane)

		_:
			return []

func get_opposite_faction(faction: Unit.Faction) -> Unit.Faction:
	if faction == Unit.Faction.ALLY:
		return Unit.Faction.ENEMY

	return Unit.Faction.ALLY

func get_front_units(faction: Unit.Faction, lane: int) -> Array[Unit]:
	var targets: Array[Unit] = []
	var lane_units = get_battle_floor().get_lane_units(faction, lane)

	if not lane_units.is_empty():
		targets.append(lane_units.front())

	return targets

func get_rear_units(faction: Unit.Faction, lane: int) -> Array[Unit]:
	var targets: Array[Unit] = []
	var lane_units = get_battle_floor().get_lane_units(faction, lane)

	if not lane_units.is_empty():
		targets.append(lane_units.back())

	return targets

func get_lane_targets(faction: Unit.Faction, lane: int) -> Array[Unit]:
	return get_battle_floor().get_lane_units(faction, lane)

## O sandbox só tem um andar (ver docs/playtest_3x3.md) — atalho para não
## espalhar battle_state.battlefield.get_floor(0) por todo lugar.
func get_battle_floor() -> BattleFloor:
	return battle_state.battlefield.get_floor(0)

# ==========================================
# CARD TARGETING
# ==========================================
func get_card_targets(
	target_type: String,
	selected_unit: Unit = null,
	target_faction: String = ""
) -> Array[Unit]:
	match target_type:
		"selected_unit":
			if selected_unit == null:
				return []

			if not matches_target_faction(selected_unit, target_faction):
				return []

			return [selected_unit]

		"all_enemies":
			return get_units_by_faction(Unit.Faction.ENEMY)

		"all_allies":
			return get_units_by_faction(Unit.Faction.ALLY)

		_:
			print("Tipo de alvo de carta desconhecido: ", target_type)
			return []

func matches_target_faction(unit: Unit, target_faction: String) -> bool:
	if target_faction.is_empty():
		return true

	match target_faction:
		"ally":
			return unit.faction == Unit.Faction.ALLY

		"enemy":
			return unit.faction == Unit.Faction.ENEMY

		_:
			print("Facção de alvo de carta desconhecida: ", target_faction)
			return false

func get_units_by_faction(faction: Unit.Faction) -> Array[Unit]:
	var targets: Array[Unit] = []

	for battle_floor in battle_state.battlefield.floors:
		targets.append_array(battle_floor.get_units_for_faction(faction))

	return targets
