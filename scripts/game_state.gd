class_name GameState
extends RefCounted

enum State {
	PLAYER_ACTION,
	TARGETING_ENEMY,
	TARGETING_FLOOR,
	TARGETING_POSITION,
	ENEMY_ACTION
}

var current: State = State.PLAYER_ACTION

func change_to(new_state: State) -> void:
	current = new_state
	
	print("Estado do jogo: ", State.keys()[current])
