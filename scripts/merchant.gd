class_name Merchant
extends Control

## Tela de um mercador (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapas 4 e 6) — o
## mesmo para cartas e artefatos: uma linha por item à venda (nome, detalhe,
## o que o jogador já tem, preço) e um botão de compra. Mostra a seção de
## cartas e/ou a de artefatos conforme o estoque do MerchantData. A regra de
## compra (ouro, coleção, artefato único) é do CampaignState; aqui só se
## reflete isso na tela.

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
var artifact_database: ArtifactDatabase

## Botão de compra e label de "o que você tem" por item, pra atualizar só o
## estado a cada mudança em vez de recriar as linhas. Chaves separadas por
## tipo porque um id de carta e um de artefato poderiam coincidir.
var card_buy_buttons: Dictionary = {}
var card_owned_labels: Dictionary = {}
var artifact_buy_buttons: Dictionary = {}
var artifact_owned_labels: Dictionary = {}

func setup(entered_point: WorldPointData, merchant_data: MerchantData, state: CampaignState, cards: CardDatabase, artifacts: ArtifactDatabase) -> void:
	point = entered_point
	merchant = merchant_data
	campaign_state = state
	card_database = cards
	artifact_database = artifacts

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
## compara primeiro. Mesma ordem pras duas seções.
func sort_by_price(prices: Dictionary, get_name: Callable) -> Array:
	var ids = prices.keys()

	ids.sort_custom(func(a, b):
		if prices[a] != prices[b]:
			return prices[a] < prices[b]

		return get_name.call(a).naturalnocasecmp_to(get_name.call(b)) < 0
	)

	return ids

func render_rows() -> void:
	if not merchant.artifact_prices.is_empty():
		rows_container.add_child(create_section_title("Artefatos"))

		for artifact_id in sort_by_price(merchant.artifact_prices, func(id): return artifact_database.artifacts[id].name):
			rows_container.add_child(create_artifact_row(artifact_id))

	if not merchant.card_prices.is_empty():
		rows_container.add_child(create_section_title("Cartas"))

		for card_id in sort_by_price(merchant.card_prices, func(id): return card_database.cards[id].name):
			rows_container.add_child(create_card_row(card_id))

func create_section_title(text: String) -> Label:
	var label = Label.new()

	label.text = text
	label.add_theme_font_size_override("font_size", 26)

	return label

## Linha genérica: texto (expande) + label de "o que você tem" + botão.
func create_row(info_text: String, price: int) -> Dictionary:
	var row = HBoxContainer.new()
	var info = Label.new()
	var owned = Label.new()
	var buy = Button.new()

	row.add_theme_constant_override("separation", 16)

	info.text = info_text
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	owned.custom_minimum_size = Vector2(110, 0)
	owned.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	buy.custom_minimum_size = Vector2(180, 44)
	buy.text = "Comprar — %d ouro" % price

	row.add_child(info)
	row.add_child(owned)
	row.add_child(buy)

	return {"row": row, "owned": owned, "buy": buy}

func create_card_row(card_id: String) -> Control:
	var card_data: CardData = card_database.cards[card_id]
	var parts = create_row("%s  (mana %d)\n%s" % [card_data.name, card_data.cost, card_data.description], merchant.get_card_price(card_id))

	parts.buy.pressed.connect(_on_buy_card_pressed.bind(card_id))
	card_buy_buttons[card_id] = parts.buy
	card_owned_labels[card_id] = parts.owned

	return parts.row

func create_artifact_row(artifact_id: String) -> Control:
	var artifact: ArtifactData = artifact_database.artifacts[artifact_id]
	var parts = create_row("%s\n%s" % [artifact.name, artifact.description], merchant.get_artifact_price(artifact_id))

	parts.buy.pressed.connect(_on_buy_artifact_pressed.bind(artifact_id))
	artifact_buy_buttons[artifact_id] = parts.buy
	artifact_owned_labels[artifact_id] = parts.owned

	return parts.row

## Carta: compra quantas quiser enquanto tiver ouro. Artefato: um de cada —
## já possuído fica desabilitado com "Já possui".
func refresh_rows() -> void:
	gold_label.text = "Ouro: %d" % campaign_state.gold

	for card_id in card_buy_buttons:
		card_buy_buttons[card_id].disabled = not campaign_state.can_afford(merchant.get_card_price(card_id))
		card_owned_labels[card_id].text = "Você tem: %d" % campaign_state.get_copies(card_id)

	for artifact_id in artifact_buy_buttons:
		var owned = campaign_state.owns_artifact(artifact_id)

		artifact_buy_buttons[artifact_id].disabled = owned or not campaign_state.can_afford(merchant.get_artifact_price(artifact_id))
		artifact_owned_labels[artifact_id].text = "Já possui" if owned else ""

func _on_buy_card_pressed(card_id: String) -> void:
	## buy_card()/buy_artifact() já recusam sozinhos; o refresh vem pelo
	## campaign_state.changed.
	campaign_state.buy_card(card_id, merchant.get_card_price(card_id))

func _on_buy_artifact_pressed(artifact_id: String) -> void:
	campaign_state.buy_artifact(artifact_id, merchant.get_artifact_price(artifact_id))
