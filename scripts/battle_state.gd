class_name BattleState
extends RefCounted


var player_hp: int = 50
var player_max_hp: int = 50
var player_block: int = 0

var enemy_hp: int = 30
var enemy_max_hp: int = 30
var enemy_block: int = 0

func damage_enemy(amount: int) -> void:
	enemy_hp -= amount

	if enemy_hp < 0:
		enemy_hp = 0

	print("Inimigo recebeu ", amount, " de dano.")
	print("HP do inimigo: ", enemy_hp, "/", enemy_max_hp)

func heal_player(amount: int) -> void:
	player_hp += amount

	if player_hp > player_max_hp:
		player_hp = player_max_hp

	print("Jogador recuperou ", amount, " de vida.")
	print("HP do jogador: ", player_hp, "/", player_max_hp)

func add_player_block(amount: int) -> void:
	player_block += amount

	print("Jogador ganhou ", amount, " de bloqueio.")
	print("Bloqueio: ", player_block)
