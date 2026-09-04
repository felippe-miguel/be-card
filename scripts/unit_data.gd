class_name UnitData
extends RefCounted

var id: String
var name: String
var max_hp: int
var attack: int

## Padrão de ataque (docs/playtest_3x3.md seção 3/4) — id resolvido por
## TargetSystem.get_pattern_attack_targets(). attack_pattern_count só se
## aplica a padrões que pegam os "N primeiros" de uma varredura (ver
## TargetSystem). "lane_front" (mira o mais à frente da própria lane) é o
## padrão default para qualquer unidade que ainda não define o seu.
var attack_pattern: String = "lane_front"
var attack_pattern_count: int = 1

## Passiva do Guardião (docs/playtest_3x3.md seção 4): bônus de HP máximo
## concedido a cada aliado ortogonalmente adjacente (mesma facção),
## enquanto esta unidade estiver viva e posicionada. 0 = sem aura. Ver
## BattleState.recalculate_auras().
var aura_adjacent_ally_max_hp_bonus: int = 0

## Status que a unidade já nasce possuindo (docs/MECHANICS_EXECUTION_PLAN.md
## Etapa 1) — status_id -> stacks, ex.: {"strength": 2} pro Berserker. Vazio
## = nasce sem nenhum status. Aplicado por BattleState.create_unit().
var initial_statuses: Dictionary = {}

## Eventos/triggers que a unidade carrega (docs/MECHANICS_EXECUTION_PLAN.md
## Etapa 2) — cada entrada: {"event": <id>, "effect": <Dictionary>}. Ver
## Unit.triggers/BattleState.fire_event() para a resolução em si.
var triggers: Array[Dictionary] = []

## Combinação "Posição + Modificador" (docs/MECHANICS_EXECUTION_PLAN.md
## Etapa 5): bônus de ATK concedido à própria unidade só enquanto ela
## estiver na Back (row 2), recalculado do zero a cada mudança no grid —
## mesma técnica de aura_adjacent_ally_max_hp_bonus acima, só que aplicado
## à própria unidade em vez de vizinhos. Ver Unit.position_attack_bonus/
## BattleState.recalculate_position_modifiers().
var back_row_attack_bonus: int = 0

## Combinação "Movimento + Ataque" (Etapa 5): bônus de ATK só no turno em
## que a unidade avançou (moveu pra uma row menor) — ver Unit.
## advanced_this_turn/get_effective_attack().
var advance_attack_bonus: int = 0

static func from_dict(data: Dictionary) -> UnitData:
	var unit_data = UnitData.new()

	unit_data.id = data.get("id", "")
	unit_data.name = data.get("name", "")
	unit_data.max_hp = data.get("max_hp", 1)
	unit_data.attack = data.get("attack", 0)
	unit_data.attack_pattern = data.get("attack_pattern", "lane_front")
	unit_data.attack_pattern_count = data.get("attack_pattern_count", 1)
	unit_data.aura_adjacent_ally_max_hp_bonus = data.get("aura_adjacent_ally_max_hp_bonus", 0)
	unit_data.initial_statuses = data.get("initial_statuses", {})
	unit_data.triggers.assign(data.get("triggers", []))
	unit_data.back_row_attack_bonus = data.get("back_row_attack_bonus", 0)
	unit_data.advance_attack_bonus = data.get("advance_attack_bonus", 0)

	return unit_data
