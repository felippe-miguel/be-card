class_name SfxSheet
extends Resource

## Um único arquivo de áudio contendo várias variações de um mesmo efeito
## sonoro (ex.: "draw.mp3" com 4 sons de puxar carta diferentes,
## encostados um no outro) — segments recorta esse arquivo em pedaços
## tocáveis individualmente, sem precisar separar em arquivos distintos.
##
## É um Resource (não RefCounted, ao contrário do resto dos dados do jogo
## — ver UnitData/CardData) de propósito: só assim dá pra salvar como
## .tres e editar start/end de cada corte direto no Inspector do Godot,
## sem precisar editar código. Ver resources/audio/sfx/*.tres — os
## valores de segments lá são um primeiro palpite (divisão igual pela
## duração total), pra ajustar ouvindo o jogo rodar.

## O arquivo de áudio inteiro, com todas as variações concatenadas.
@export var stream: AudioStream

## Um corte por variação: x = início, y = fim, em segundos, dentro de
## stream. A ordem não importa quando fixed_index == -1 (sorteio) — ver
## pick_random_segment().
@export var segments: Array[Vector2] = []

## -1 (padrão) sorteia entre segments normalmente. >= 0 trava SEMPRE no
## corte desse índice, sem sortear — pedido explícito pra parar de
## sortear entre as variações de "draw" por enquanto (os sons diferentes
## ficaram estranhos alternando) sem precisar mexer em código: só editar
## este campo no Inspector do .tres.
@export var fixed_index: int = -1

func pick_random_segment() -> Vector2:
	if segments.is_empty():
		return Vector2.ZERO

	if fixed_index >= 0 and fixed_index < segments.size():
		return segments[fixed_index]

	return segments[randi() % segments.size()]
