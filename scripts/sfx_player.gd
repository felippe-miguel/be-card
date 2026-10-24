class_name SfxPlayer
extends Node

## Toca cortes de SfxSheet com SOBREPOSIÇÃO: cada chamada a play_random()
## abre uma voz nova e independente (via AudioStreamPlaybackPolyphonic),
## em vez de reaproveitar um único AudioStreamPlayer — assim uma compra
## nova nunca corta o som de uma compra anterior que ainda esteja
## tocando. AudioStreamPolyphonic é o jeito nativo do Godot 4 de tocar
## várias instâncias (do mesmo stream ou de streams diferentes) ao mesmo
## tempo a partir de um único player.
##
## O Godot não tem "tocar só até X segundos" nativo nem pra isto — cada
## voz usa seu próprio SceneTreeTimer avulso (não compartilhado; várias
## vozes podem ter o seu pendente ao mesmo tempo) pra chamar
## stop_stream() no fim do corte.

## Quantas vozes simultâneas o player suporta — bem acima do que este
## jogo precisa hoje (compra de carta, embaralhar), com folga pra não
## cortar sons por falta de voz livre.
const MAX_POLYPHONY = 8

@onready var player: AudioStreamPlayer = $Player
var playback: AudioStreamPlaybackPolyphonic

func _ready() -> void:
	var polyphonic_stream = AudioStreamPolyphonic.new()

	polyphonic_stream.polyphony = MAX_POLYPHONY

	## AudioStreamPolyphonic só entrega um playback via get_stream_
	## playback() depois que o player começa a "tocar" o stream
	## polifônico em si — as vozes individuais (play_stream() abaixo) são
	## abertas por cima disso, não substituem essa reprodução de base.
	player.stream = polyphonic_stream
	player.play()

	playback = player.get_stream_playback()

func play_random(sheet: SfxSheet) -> void:
	if sheet == null or sheet.stream == null or sheet.segments.is_empty():
		return

	var segment = sheet.pick_random_segment()
	var duration = segment.y - segment.x

	if duration <= 0:
		return

	var stream_id = playback.play_stream(sheet.stream, segment.x)

	get_tree().create_timer(duration).timeout.connect(func():
		if playback.is_stream_playing(stream_id):
			playback.stop_stream(stream_id)
	)
