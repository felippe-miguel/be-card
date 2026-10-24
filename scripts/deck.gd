class_name Deck
extends RefCounted

## Baralho de cartas do jogador: pilha de compra, mão e descarte.
## Toda carta do CardDatabase entra na pilha de compra ao iniciar.

signal changed

## Disparado só no momento em que o descarte volta pra pilha de compra
## (reshuffle_discard_into_draw_pile()) — changed também dispara junto,
## mas não diferencia "só comprei" de "precisei reembaralhar primeiro".
## Usado por Game pra tocar o efeito sonoro de embaralhar só quando isso
## realmente acontece.
signal reshuffled

## Limite de cartas na mão. Compras além disso não acontecem; as cartas
## permanecem na pilha de compra até haver espaço na mão.
const MAX_HAND_SIZE = 7

var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []
var hand: Array[CardData] = []

## Cartas de invocação de unidade jogadas vão pro cemitério, não pro
## descarte (ver bury()) — permanente: reshuffle_discard_into_draw_pile()
## nunca mexe nele, só no discard_pile normal.
var graveyard_pile: Array[CardData] = []

func _init(cards: Array[CardData]) -> void:
	draw_pile = cards.duplicate()
	draw_pile.shuffle()

## Retorna quantas cartas foram de fato compradas (pode ser menos que
## amount — mão cheia ou baralho vazio mesmo após reembaralhar) — usado
## por Game pra só tocar o efeito sonoro de compra quando algo realmente
## foi comprado.
func draw(amount: int) -> int:
	var drawn_count = 0

	for i in range(amount):
		if draw_single_card():
			drawn_count += 1

	changed.emit()

	return drawn_count

func draw_single_card() -> bool:
	if hand.size() >= MAX_HAND_SIZE:
		print("Mão cheia (", MAX_HAND_SIZE, ") - carta não comprada.")
		return false

	if draw_pile.is_empty():
		reshuffle_discard_into_draw_pile()

	if draw_pile.is_empty():
		print("Sem cartas para comprar.")
		return false

	var card_data = draw_pile.pop_back()

	hand.append(card_data)

	return true

func discard(card_data: CardData) -> void:
	hand.erase(card_data)
	discard_pile.append(card_data)

	changed.emit()

## Descarta a mão inteira de uma vez — usado ao rodar o turno
## (Game._on_run_turn_button_pressed()), ao contrário de discard(), que
## descarta uma única carta jogada.
func discard_hand() -> void:
	discard_pile.append_array(hand)
	hand.clear()

	changed.emit()

## Cartas de invocação de unidade vão pro cemitério em vez do descarte
## (ver Game.finish_card_play()) — saem de circulação de vez, nunca mais
## voltam pro baralho de compra.
func bury(card_data: CardData) -> void:
	hand.erase(card_data)
	graveyard_pile.append(card_data)

	changed.emit()

func reshuffle_discard_into_draw_pile() -> void:
	if discard_pile.is_empty():
		return

	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	draw_pile.shuffle()

	print("Baralho reembaralhado a partir do descarte.")

	reshuffled.emit()
