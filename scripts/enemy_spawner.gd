class_name EnemySpawner
extends RefCounted

## Spawna inimigos automaticamente nos primeiros turnos da batalha: um
## inimigo por andar (se houver espaço), sorteado de um pool fixo. Depois
## de MAX_SPAWN_TURNS turnos, spawn_wave() não faz mais nada.

const MAX_SPAWN_TURNS = 3

## Dragão fica de fora do pool aleatório por enquanto — é forte demais
## para um spawn comum; reservado para um futuro spawn especial/chefe.
const ENEMY_POOL: Array[String] = [
	"slime", "skeleton", "orc", "goblin", "wolf", "bat", "troll", "bandit"
]

var battle_state: BattleState

func _init(state: BattleState) -> void:
	battle_state = state

func should_spawn(turn_number: int) -> bool:
	return turn_number <= MAX_SPAWN_TURNS

func spawn_wave(turn_number: int) -> void:
	if not should_spawn(turn_number):
		return

	print("Spawn de inimigos - turno ", turn_number)

	for battle_floor in battle_state.battlefield.floors:
		spawn_on_floor(battle_floor)

func spawn_on_floor(battle_floor: BattleFloor) -> void:
	if not battle_floor.can_add_unit(Unit.Faction.ENEMY):
		return

	var unit_id = ENEMY_POOL[randi() % ENEMY_POOL.size()]
	var unit = battle_state.create_unit(unit_id, Unit.Faction.ENEMY)

	if unit == null:
		return

	battle_floor.add_unit(unit)
