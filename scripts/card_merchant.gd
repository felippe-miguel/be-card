class_name CardMerchant
extends Control

## Tela de um mercador de cartas (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa
## 4). Crua de propósito: uma linha por carta à venda (nome, custo de mana,
## descrição, quantas cópias o jogador já tem, preço) e um botão de compra.
## A regra de compra (ouro suficiente, crescer a coleção) é do
## CampaignState; aqui só se reflete isso na tela.

signal back_pressed

@onready var title_label: Label = $Margin/Layout/TopBar/TitleLabel
@onready var gold_label: Label = $Margin/Layout/TopBar/GoldLabel
@onready var back_button: Button = $Margin/Layout/TopBar/BackButton
@onready var rows_container: VBoxContainer = $Margin/Layout/Scroll/Rows

## Recebidos de Main via setup(), antes de entrar na árvore.
var point: WorldPointData
var merchant: MerchantData
var campaign_state: CampaignState
var card_database: CardDatabase

## card_id -> Button de compra, pra atualizar só o estado (habilitado,
## cópias possuídas) a cada mudança em vez de recriar as linhas.
var buy_buttons: Dictionary = {}
var owned_labels: Dictionary = {}

func setup(entered_point: WorldPointData, merchant_data: MerchantData, state: CampaignState, cards: CardDatabase) -> void:
	point = entered_point
	merchant = merchant_data
	campaign_state = state
	card_database = cards

func _ready() -> void:
	title_label.text = point.name
	back_button.pressed.connect(back_pressed.emit)

	render_rows()

	## Some sozinha quando a tela é liberada (ver o mesmo comentário em
	## Overworld._ready()).
	campaign_state.changed.connect(refresh_rows)
	refresh_rows()

## Esc volta pro mapa — mesmo comportamento das outras telas de ponto.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed.emit()

## Ordem: preço crescente, depois nome — o que o jogador provavelmente
## compara primeiro.
func get_sorted_card_ids() -> Array:
	var ids = merchant.prices.keys()

	ids.sort_custom(func(a, b):
		if merchant.get_price(a) != merchant.get_price(b):
			return merchant.get_price(a) < merchant.get_price(b)

		return card_database.cards[a].name.naturalnocasecmp_to(card_database.cards[b].name) < 0
	)

	return ids

func render_rows() -> void:
	for card_id in get_sorted_card_ids():
		rows_container.add_child(create_row(card_id))

func create_row(card_id: String) -> Control:
	var card_data: CardData = card_database.cards[card_id]
	var row = HBoxContainer.new()
	var info = Label.new()
	var owned = Label.new()
	var buy = Button.new()

	row.add_theme_constant_override("separation", 16)

	info.text = "%s  (mana %d)\n%s" % [card_data.name, card_data.cost, card_data.description]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	owned.custom_minimum_size = Vector2(110, 0)
	owned.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	buy.custom_minimum_size = Vector2(180, 44)
	buy.text = "Comprar — %d ouro" % merchant.get_price(card_id)
	buy.pressed.connect(_on_buy_pressed.bind(card_id))

	row.add_child(info)
	row.add_child(owned)
	row.add_child(buy)

	buy_buttons[card_id] = buy
	owned_labels[card_id] = owned

	return row

func refresh_rows() -> void:
	gold_label.text = "Ouro: %d" % campaign_state.gold

	for card_id in buy_buttons:
		buy_buttons[card_id].disabled = not campaign_state.can_afford(merchant.get_price(card_id))
		owned_labels[card_id].text = "Você tem: %d" % campaign_state.get_copies(card_id)

func _on_buy_pressed(card_id: String) -> void:
	## buy_card() já recusa sozinho sem ouro suficiente; o refresh vem pelo
	## campaign_state.changed.
	campaign_state.buy_card(card_id, merchant.get_price(card_id))
