class_name Deck
extends RefCounted

## Baralho de cartas do jogador: pilha de compra, mão e descarte.
## Toda carta do CardDatabase entra na pilha de compra ao iniciar.

signal changed

## Limite de cartas na mão. Compras além disso não acontecem; as cartas
## permanecem na pilha de compra até haver espaço na mão.
const MAX_HAND_SIZE = 7

var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []
var hand: Array[CardData] = []

func _init(cards: Array[CardData]) -> void:
	draw_pile = cards.duplicate()
	draw_pile.shuffle()

func draw(amount: int) -> void:
	for i in range(amount):
		draw_single_card()

	changed.emit()

func draw_single_card() -> void:
	if hand.size() >= MAX_HAND_SIZE:
		print("Mão cheia (", MAX_HAND_SIZE, ") - carta não comprada.")
		return

	if draw_pile.is_empty():
		reshuffle_discard_into_draw_pile()

	if draw_pile.is_empty():
		print("Sem cartas para comprar.")
		return

	var card_data = draw_pile.pop_back()

	hand.append(card_data)

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

func reshuffle_discard_into_draw_pile() -> void:
	if discard_pile.is_empty():
		return

	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	draw_pile.shuffle()

	print("Baralho reembaralhado a partir do descarte.")
