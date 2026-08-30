class_name BattleState
extends RefCounted

var battlefield: Battlefield
var pyre: Pyre
var unit_database: UnitDatabase
var target_system: TargetSystem

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

	recalculate_auras()

func create_unit(unit_id: String, faction: Unit.Faction) -> Unit:
	var unit_data = unit_database.units.get(unit_id)
	
	if unit_data == null:
		print("Unidade não encontrada: ", unit_id)
		
		return null
	
	return Unit.new(
		unit_data.id,
		unit_data.name,
		unit_data.max_hp,
		unit_data.attack,
		faction,
		unit_data.attack_pattern,
		unit_data.attack_pattern_count,
		unit_data.aura_adjacent_ally_max_hp_bonus
	)

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

func execute_unit_attack(unit: Unit) -> void:
	var targets = target_system.get_pattern_attack_targets(unit)

	if targets.is_empty():
		print(unit.name, " (", unit.attack_pattern, ") não encontrou nenhum alvo.")
		return

	print(
		unit.name, " (", unit.attack_pattern, ") mira em: ",
		targets.map(func(t): return "%s [L%d/R%d]" % [t.name, t.lane, t.row])
	)

	for target in targets:
		unit.attack_unit(target)

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
