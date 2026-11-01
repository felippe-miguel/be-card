class_name DeckBuilder
extends Control

## Tela de montagem de deck (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa 5),
## aberta pelo painel de decks do overworld ("Editar" ou "Criar novo deck").
## Coleção à esquerda, deck à direita: "+" põe uma cópia no deck, "−" tira.
## Acima das colunas, o artefato equipado no deck (Etapa 6 — no máximo 1).
##
## Toda edição acontece numa CÓPIA do deck (working_deck): nada muda no
## CampaignState até "Salvar". "Cancelar"/Esc descartam a edição. A regra
## de validade é a mesma de sempre (CampaignState.is_deck_valid()): aqui só
## se impede, na UI, passar das cópias possuídas e salvar deck vazio.

## Main volta pro overworld em qualquer um dos dois. message: aviso curto
## pro overworld ("Deck X salvo"), "" = nenhum.
signal closed(message: String)

const NEW_DECK_NAME = "Novo deck"

const CARD_SCENE: PackedScene = preload("res://scenes/card.tscn")
const KEYWORD_TOOLTIP_SCENE: PackedScene = preload("res://scenes/keyword_tooltip.tscn")
const ARTIFACT_CARD_SCENE: PackedScene = preload("res://scenes/artifact_card.tscn")

## O artefato equipado aparece como carta reduzida no topo da coluna do deck
## (a barra de cima só tem o seletor): em tamanho cheio (335 px de altura)
## empurraria as colunas pra fora da tela de 980 px.
const ARTIFACT_PREVIEW_SCALE = 0.65

@onready var name_edit: LineEdit = $Margin/Layout/TopBar/NameEdit
@onready var count_label: Label = $Margin/Layout/TopBar/CountLabel
@onready var name_warning_label: Label = $Margin/Layout/TopBar/NameWarningLabel
@onready var save_button: Button = $Margin/Layout/TopBar/SaveButton
@onready var cancel_button: Button = $Margin/Layout/TopBar/CancelButton
@onready var delete_button: Button = $Margin/Layout/TopBar/DeleteButton
@onready var collection_rows: GridContainer = $Margin/Layout/Columns/CollectionColumn/Scroll/HoverMargin/Rows
@onready var deck_rows: VBoxContainer = $Margin/Layout/Columns/DeckColumn/Scroll/Rows
@onready var artifact_option: OptionButton = $Margin/Layout/ArtifactBar/ArtifactOption
@onready var deck_column: VBoxContainer = $Margin/Layout/Columns/DeckColumn

## Recebidos de Main via setup(), antes de entrar na árvore.
var campaign_state: CampaignState
var card_database: CardDatabase
var artifact_database: ArtifactDatabase
var unit_database: UnitDatabase
var keyword_database: KeywordDatabase

## artifact_id de cada item do artifact_option, na mesma ordem dos itens
## ("" = Nenhum).
var artifact_option_ids: Array[String] = []

## Índice do deck sendo editado em campaign_state.deck_lists; -1 = deck
## novo (ainda não existe na campanha).
var deck_index: int = -1

var working_deck: DeckList

## Holder (tamanho reduzido) e carta do artefato equipado; criados em
## setup_artifact_slot(). O holder some com "Nenhum".
var artifact_holder: Control
var artifact_card: ArtifactCard

## Tooltip único, compartilhado pelas linhas da coluna do deck (que são
## recriadas a cada refresh()): mostra as palavras-chave (e o bloco da
## unidade, nas cartas de invocação) da linha sob o mouse. As cartas da
## coleção e o ArtifactCard têm o tooltip próprio, dentro do Card.
var row_tooltip: KeywordTooltip

## Label "no deck: x / y" e botão "+" de cada carta da coleção, por card_id.
## A grade de cartas é criada UMA vez (a coleção não muda enquanto o
## builder está aberto — compra/evento só acontecem em outras telas) e
## refresh() só atualiza estes dois: recriar dezenas de Card a cada "+"/"−"
## faria o hover piscar sob o mouse.
var collection_usage_labels: Dictionary = {}
var collection_add_buttons: Dictionary = {}

func setup(state: CampaignState, cards: CardDatabase, artifacts: ArtifactDatabase, units: UnitDatabase, keywords: KeywordDatabase, index: int) -> void:
	campaign_state = state
	card_database = cards
	artifact_database = artifacts
	unit_database = units
	keyword_database = keywords
	deck_index = index

	if index >= 0 and index < state.deck_lists.size():
		working_deck = state.deck_lists[index].duplicate_list()
	else:
		deck_index = -1
		working_deck = DeckList.new()
		working_deck.name = "%s %d" % [NEW_DECK_NAME, state.deck_lists.size() + 1]

func _ready() -> void:
	name_edit.text = working_deck.name
	name_edit.text_changed.connect(_on_name_changed)

	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	delete_button.pressed.connect(_on_delete_pressed)

	row_tooltip = KEYWORD_TOOLTIP_SCENE.instantiate()
	add_child(row_tooltip)
	row_tooltip.keyword_database = keyword_database

	setup_artifact_slot()
	setup_artifact_option()
	artifact_option.item_selected.connect(_on_artifact_selected)

	## Deck novo não tem o que apagar; o último deck da campanha também não
	## pode ser apagado (ver CampaignState.can_delete_deck()).
	delete_button.disabled = deck_index < 0 or not campaign_state.can_delete_deck(deck_index)

	build_collection()
	refresh()

## Esc = Cancelar (descarta a edição) — mesmo "sobe um nível" das outras
## telas. Com o campo de nome focado, o LineEdit consome o Esc antes
## (perde o foco), então é preciso um segundo Esc pra sair.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()

## A coleção só tem os contadores/botões atualizados; a coluna do deck é
## recriada inteira (linhas leves de texto, sem estado de botão pra
## sincronizar).
func refresh() -> void:
	## As linhas (e a que está sob o mouse) vão ser destruídas: sem isto o
	## tooltip ficaria na tela sem mouse_exited pra escondê-lo.
	row_tooltip.hide_tooltip()

	for child in deck_rows.get_children():
		child.queue_free()

	for card_id in collection_usage_labels:
		var in_deck = working_deck.get_copies(card_id)
		var owned = campaign_state.get_copies(card_id)

		collection_usage_labels[card_id].text = "no deck: %d / %d" % [in_deck, owned]
		collection_add_buttons[card_id].disabled = in_deck >= owned

	for card_id in sort_by_name(working_deck.cards.keys()):
		deck_rows.add_child(create_deck_row(card_id))

	count_label.text = "%d cartas" % working_deck.get_total_card_count()
	refresh_save_state()

## Salvar só com deck válido E nome livre — a mesma regra que
## CampaignState.save_deck() aplica, mostrada antes do clique. Chamado
## também a cada tecla no campo de nome (sem recriar as colunas).
func refresh_save_state() -> void:
	var name_taken = campaign_state.is_deck_name_taken(working_deck.name, deck_index)

	name_warning_label.visible = name_taken
	save_button.disabled = name_taken or not campaign_state.is_deck_valid(working_deck)

## "Nenhum" + os artefatos possuídos, por nome. Se o deck já vier com um
## artefato que o jogador não possui (deck inválido vindo do JSON), ele
## aparece marcado, pra ficar claro por que o deck não salva.
func setup_artifact_option() -> void:
	artifact_option.clear()
	artifact_option_ids.clear()

	artifact_option.add_item("Nenhum")
	artifact_option_ids.append("")

	var ids: Array = campaign_state.artifacts.keys()

	if working_deck.artifact_id != "" and not ids.has(working_deck.artifact_id):
		ids.append(working_deck.artifact_id)

	ids.sort_custom(func(a, b): return get_artifact_name(a).naturalnocasecmp_to(get_artifact_name(b)) < 0)

	for artifact_id in ids:
		var label = get_artifact_name(artifact_id)

		if not campaign_state.owns_artifact(artifact_id):
			label += " (não possui)"

		artifact_option.add_item(label)
		artifact_option_ids.append(artifact_id)

	artifact_option.select(artifact_option_ids.find(working_deck.artifact_id))
	refresh_artifact_description()

func get_artifact_name(artifact_id: String) -> String:
	var artifact: ArtifactData = artifact_database.artifacts.get(artifact_id)

	return artifact.name if artifact != null else artifact_id

## Holder do tamanho da carta já reduzido (a Card/ArtifactCard se posiciona
## sozinha, então não vai direto num Container — mesma razão do tile do
## Merchant). A carta fica em escala ARTIFACT_PREVIEW_SCALE; como o pivô é o
## centro, a position compensa pra o canto visual ficar no canto do holder.
func setup_artifact_slot() -> void:
	artifact_card = ARTIFACT_CARD_SCENE.instantiate()
	artifact_holder = Control.new()

	var full_size: Vector2 = artifact_card.custom_minimum_size

	artifact_holder.custom_minimum_size = full_size * ARTIFACT_PREVIEW_SCALE
	artifact_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artifact_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	artifact_holder.visible = false

	artifact_card.base_scale = ARTIFACT_PREVIEW_SCALE
	artifact_card.scale = Vector2.ONE * ARTIFACT_PREVIEW_SCALE
	artifact_card.rest_position = -full_size * (1.0 - ARTIFACT_PREVIEW_SCALE) / 2.0
	artifact_card.position = artifact_card.rest_position

	artifact_holder.add_child(artifact_card)

	## Logo abaixo do título "Deck" (índice 0 da coluna).
	deck_column.add_child(artifact_holder)
	deck_column.move_child(artifact_holder, 1)

func refresh_artifact_description() -> void:
	var artifact: ArtifactData = artifact_database.artifacts.get(working_deck.artifact_id)

	artifact_holder.visible = artifact != null

	if artifact != null:
		artifact_card.setup(artifact, keyword_database)

func _on_artifact_selected(item_index: int) -> void:
	working_deck.artifact_id = artifact_option_ids[item_index]
	refresh_artifact_description()
	refresh_save_state()

func sort_by_name(ids: Array) -> Array:
	var result = ids.duplicate()

	result.sort_custom(func(a, b): return get_card_name(a).naturalnocasecmp_to(get_card_name(b)) < 0)

	return result

func get_card_name(card_id: String) -> String:
	var card_data: CardData = card_database.cards.get(card_id)

	return card_data.name if card_data != null else card_id

func build_collection() -> void:
	for card_id in sort_by_name(campaign_state.collection.keys()):
		collection_rows.add_child(create_collection_tile(card_id))

## Coleção: a carta de verdade (mesma cena da mão em combate) + quantas
## cópias já estão no deck de quantas possui + "+". Clicar na carta também
## adiciona uma cópia. Mesma ideia do tile de Merchant.create_card_tile()
## (holder do tamanho da carta, porque a Card se posiciona sozinha e
## brigaria com o layout de um Container; margem de hover em HoverMargin
## na cena) — mantido duplicado de propósito, são poucas linhas.
## Carta da coleção sem CardData no catálogo mostra só o id (sem carta).
func create_collection_tile(card_id: String) -> Control:
	var tile = VBoxContainer.new()
	var footer = HBoxContainer.new()
	var usage = Label.new()
	var add_button = Button.new()
	var card_data: CardData = card_database.cards.get(card_id)

	tile.add_theme_constant_override("separation", 8)

	if card_data != null:
		var holder = Control.new()
		var card: Card = CARD_SCENE.instantiate()

		holder.custom_minimum_size = card.custom_minimum_size
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

		## setup() precisa dos @onready da Card: espera o sinal ready dela.
		card.ready.connect(card.setup.bind(card_data, unit_database, keyword_database))

		## PASS (não o STOP padrão) pra a roda do mouse ainda rolar o
		## ScrollContainer com o cursor sobre uma carta.
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.played.connect(func(_card): _on_add_pressed(card_id))

		holder.add_child(card)
		card.position = Vector2.ZERO
		card.rest_position = Vector2.ZERO
		tile.add_child(holder)
	else:
		var missing = Label.new()

		missing.text = card_id
		tile.add_child(missing)

	usage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	usage.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	add_button.text = "+"
	add_button.custom_minimum_size = Vector2(44, 36)
	add_button.pressed.connect(_on_add_pressed.bind(card_id))

	footer.add_theme_constant_override("separation", 8)
	footer.add_child(usage)
	footer.add_child(add_button)
	tile.add_child(footer)

	collection_usage_labels[card_id] = usage
	collection_add_buttons[card_id] = add_button

	return tile

func create_deck_row(card_id: String) -> Control:
	var row = create_row("%s ×%d" % [get_card_name(card_id), working_deck.get_copies(card_id)])
	var remove_button = Button.new()

	remove_button.text = "−"
	remove_button.custom_minimum_size = Vector2(44, 36)
	remove_button.pressed.connect(_on_remove_pressed.bind(card_id))

	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_entered.connect(_on_deck_row_hovered.bind(row, card_id))
	row.mouse_exited.connect(row_tooltip.hide_tooltip)

	row.add_child(remove_button)

	return row

## Tooltip da carta ao lado da linha do deck (sem a carta inteira): mesma
## lógica do Card.update_keyword_tooltip().
func _on_deck_row_hovered(row: Control, card_id: String) -> void:
	var card_data: CardData = card_database.cards.get(card_id)

	if card_data == null:
		return

	var unit_data: UnitData = unit_database.units.get(card_data.get_summon_unit_id())

	if unit_data != null:
		row_tooltip.set_unit(unit_data, TargetSystem.describe_pattern(unit_data.attack_pattern, unit_data.attack_pattern_count))
	else:
		row_tooltip.set_unit(null)

	row_tooltip.set_keywords(keyword_database.get_keywords(card_data.get_keyword_ids(unit_database)))
	row_tooltip.show_beside(row)

func create_row(text: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	var label = Label.new()

	row.add_theme_constant_override("separation", 12)

	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(label)

	return row

func _on_add_pressed(card_id: String) -> void:
	if working_deck.get_copies(card_id) >= campaign_state.get_copies(card_id):
		return

	working_deck.add_copy(card_id)
	refresh()

func _on_remove_pressed(card_id: String) -> void:
	working_deck.remove_copy(card_id)
	refresh()

func _on_name_changed(new_text: String) -> void:
	working_deck.name = new_text
	refresh_save_state()

func _on_save_pressed() -> void:
	if campaign_state.save_deck(deck_index, working_deck) < 0:
		return

	closed.emit("Deck \"%s\" salvo" % working_deck.name)

func _on_cancel_pressed() -> void:
	closed.emit("")

func _on_delete_pressed() -> void:
	var deleted_name = campaign_state.deck_lists[deck_index].name

	if campaign_state.delete_deck(deck_index):
		closed.emit("Deck \"%s\" apagado" % deleted_name)
