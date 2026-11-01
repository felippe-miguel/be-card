class_name Merchant
extends Control

## Tela de um mercador (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapas 4 e 6) — o
## mesmo para cartas e artefatos: um grid de cartas de verdade por seção, cada
## uma com o que o jogador já tem e um botão de compra com o preço. Mostra a seção de
## cartas e/ou a de artefatos conforme o estoque do MerchantData. A regra de
## compra (ouro, coleção, artefato único) é do CampaignState; aqui só se
## reflete isso na tela.

signal back_pressed

const CARD_SCENE: PackedScene = preload("res://scenes/card.tscn")
const ARTIFACT_CARD_SCENE: PackedScene = preload("res://scenes/artifact_card.tscn")

## Folga ao redor do grid de cartas: o ScrollContainer corta o que sair da
## área dele, e a carta sob o mouse sobe Card.HOVER_LIFT e cresce
## Card.HOVER_SCALE ao redor do centro (ver Card). Sem esta margem, a
## primeira linha seria cortada no topo e as colunas das pontas, nas laterais.
const GRID_MARGIN_TOP = 40
const GRID_MARGIN_SIDE = 24
const GRID_MARGIN_BOTTOM = 16
const GRID_SEPARATION_H = 24
const GRID_SEPARATION_V = 32
const GRID_COLUMNS = 3

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
var unit_database: UnitDatabase
var keyword_database: KeywordDatabase

## Botão de compra e label de "o que você tem" por item, pra atualizar só o
## estado a cada mudança em vez de recriar as linhas. Chaves separadas por
## tipo porque um id de carta e um de artefato poderiam coincidir.
var card_buy_buttons: Dictionary = {}
var card_owned_labels: Dictionary = {}
var artifact_buy_buttons: Dictionary = {}
var artifact_owned_labels: Dictionary = {}

func setup(entered_point: WorldPointData, merchant_data: MerchantData, state: CampaignState, cards: CardDatabase, artifacts: ArtifactDatabase, units: UnitDatabase, keywords: KeywordDatabase) -> void:
	point = entered_point
	merchant = merchant_data
	campaign_state = state
	card_database = cards
	artifact_database = artifacts
	unit_database = units
	keyword_database = keywords

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

		var grid = create_grid()

		for artifact_id in sort_by_price(merchant.artifact_prices, func(id): return artifact_database.artifacts[id].name):
			grid.add_child(create_artifact_tile(artifact_id))

		rows_container.add_child(wrap_with_hover_margin(grid))

	if not merchant.card_prices.is_empty():
		rows_container.add_child(create_section_title("Cartas"))

		var grid = create_grid()

		for card_id in sort_by_price(merchant.card_prices, func(id): return card_database.cards[id].name):
			grid.add_child(create_card_tile(card_id))

		rows_container.add_child(wrap_with_hover_margin(grid))

func create_section_title(text: String) -> Label:
	var label = Label.new()

	label.text = text
	label.add_theme_font_size_override("font_size", 26)

	return label

func create_grid() -> GridContainer:
	var grid = GridContainer.new()

	grid.columns = GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", GRID_SEPARATION_H)
	grid.add_theme_constant_override("v_separation", GRID_SEPARATION_V)

	return grid

## Margem em volta do grid pra o hover da carta não ser cortado pelo
## ScrollContainer (ver GRID_MARGIN_*). Centraliza o grid na horizontal.
func wrap_with_hover_margin(content: Control) -> MarginContainer:
	var margin = MarginContainer.new()

	margin.add_theme_constant_override("margin_top", GRID_MARGIN_TOP)
	margin.add_theme_constant_override("margin_left", GRID_MARGIN_SIDE)
	margin.add_theme_constant_override("margin_right", GRID_MARGIN_SIDE)
	margin.add_theme_constant_override("margin_bottom", GRID_MARGIN_BOTTOM)
	margin.add_child(content)

	return margin

## Tile genérico (carta ou artefato): o item (Card/ArtifactCard) dentro de
## um holder + rodapé com "o que você tem" e o botão de compra. A Card se
## posiciona sozinha (position animada no hover), o que brigaria com o
## layout de um Container — por isso ela fica num holder (Control comum, que
## não reposiciona filhos) do tamanho dela, com rest_position ZERO. O
## holder ignora o mouse e o item usa PASS: o hover funciona e a roda do
## mouse ainda rola o ScrollContainer. Sem clique de compra na carta: só
## pelo botão, pra não comprar sem querer.
func create_tile(item: Control, price: int) -> Dictionary:
	var tile = VBoxContainer.new()
	var holder = Control.new()
	var footer = HBoxContainer.new()
	var owned = Label.new()
	var buy = Button.new()

	tile.add_theme_constant_override("separation", 8)

	holder.custom_minimum_size = item.custom_minimum_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	## O rodapé (Você tem + botão) pode ser mais largo que a carta e alargar o
	## tile; sem isto o holder esticaria e a carta ficaria colada à esquerda.
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	item.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_child(item)
	item.position = Vector2.ZERO
	item.rest_position = Vector2.ZERO
	tile.add_child(holder)

	owned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owned.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	buy.custom_minimum_size = Vector2(150, 44)
	buy.text = "Comprar — %d ouro" % price

	footer.add_theme_constant_override("separation", 8)
	footer.add_child(owned)
	footer.add_child(buy)
	tile.add_child(footer)

	return {"tile": tile, "owned": owned, "buy": buy}

## O custo de mana fica sempre na cor normal (set_affordable() é sobre mana
## em combate, não sobre ouro).
func create_card_tile(card_id: String) -> Control:
	var card_data: CardData = card_database.cards[card_id]
	var card: Card = CARD_SCENE.instantiate()
	var parts = create_tile(card, merchant.get_card_price(card_id))

	## setup() usa os @onready da Card, que só existem quando ela entra na
	## árvore; o tile ainda não está nela aqui, então o setup espera o sinal
	## ready (emitido depois do _ready() da própria Card).
	card.ready.connect(card.setup.bind(card_data, unit_database, keyword_database))

	parts.buy.pressed.connect(_on_buy_card_pressed.bind(card_id))
	card_buy_buttons[card_id] = parts.buy
	card_owned_labels[card_id] = parts.owned

	return parts.tile

func create_artifact_tile(artifact_id: String) -> Control:
	var artifact: ArtifactData = artifact_database.artifacts[artifact_id]
	var artifact_card: ArtifactCard = ARTIFACT_CARD_SCENE.instantiate()
	var parts = create_tile(artifact_card, merchant.get_artifact_price(artifact_id))

	artifact_card.ready.connect(artifact_card.setup.bind(artifact, keyword_database))

	parts.buy.pressed.connect(_on_buy_artifact_pressed.bind(artifact_id))
	artifact_buy_buttons[artifact_id] = parts.buy
	artifact_owned_labels[artifact_id] = parts.owned

	return parts.tile

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
