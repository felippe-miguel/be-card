class_name GameState
extends RefCounted

signal changed

enum State {
	PLAYER_ACTION,
	TARGETING_UNIT,
	TARGETING_FLOOR,
	TARGETING_POSITION,
	COMBAT_PHASE,
	SPAWN_PHASE,
	BATTLE_OVER
}

var current: State = State.PLAYER_ACTION

func change_to(new_state: State) -> void:
	current = new_state

	print("Estado do jogo: ", State.keys()[current])

	changed.emit()
