class_name DeckBuilder
extends Control

## Tela de montagem de deck (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa 5),
## aberta pelo painel de decks do overworld ("Editar" ou "Criar novo deck").
## Coleção à esquerda, deck à direita: "+" põe uma cópia no deck, "−" tira.
##
## Toda edição acontece numa CÓPIA do deck (working_deck): nada muda no
## CampaignState até "Salvar". "Cancelar"/Esc descartam a edição. A regra
## de validade é a mesma de sempre (CampaignState.is_deck_valid()): aqui só
## se impede, na UI, passar das cópias possuídas e salvar deck vazio.

## Main volta pro overworld em qualquer um dos dois. message: aviso curto
## pro overworld ("Deck X salvo"), "" = nenhum.
signal closed(message: String)

const NEW_DECK_NAME = "Novo deck"

@onready var name_edit: LineEdit = $Margin/Layout/TopBar/NameEdit
@onready var count_label: Label = $Margin/Layout/TopBar/CountLabel
@onready var name_warning_label: Label = $Margin/Layout/TopBar/NameWarningLabel
@onready var save_button: Button = $Margin/Layout/TopBar/SaveButton
@onready var cancel_button: Button = $Margin/Layout/TopBar/CancelButton
@onready var delete_button: Button = $Margin/Layout/TopBar/DeleteButton
@onready var collection_rows: VBoxContainer = $Margin/Layout/Columns/CollectionColumn/Scroll/Rows
@onready var deck_rows: VBoxContainer = $Margin/Layout/Columns/DeckColumn/Scroll/Rows

## Recebidos de Main via setup(), antes de entrar na árvore.
var campaign_state: CampaignState
var card_database: CardDatabase

## Índice do deck sendo editado em campaign_state.deck_lists; -1 = deck
## novo (ainda não existe na campanha).
var deck_index: int = -1

var working_deck: DeckList

func setup(state: CampaignState, cards: CardDatabase, index: int) -> void:
	campaign_state = state
	card_database = cards
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

	## Deck novo não tem o que apagar; o último deck da campanha também não
	## pode ser apagado (ver CampaignState.can_delete_deck()).
	delete_button.disabled = deck_index < 0 or not campaign_state.can_delete_deck(deck_index)

	refresh()

## Esc = Cancelar (descarta a edição) — mesmo "sobe um nível" das outras
## telas. Com o campo de nome focado, o LineEdit consome o Esc antes
## (perde o foco), então é preciso um segundo Esc pra sair.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()

## Recria as duas colunas inteiras a cada mudança — poucas cartas, e assim
## não há estado de botão pra sincronizar.
func refresh() -> void:
	for child in collection_rows.get_children():
		child.queue_free()

	for child in deck_rows.get_children():
		child.queue_free()

	for card_id in sort_by_name(campaign_state.collection.keys()):
		collection_rows.add_child(create_collection_row(card_id))

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

func sort_by_name(ids: Array) -> Array:
	var result = ids.duplicate()

	result.sort_custom(func(a, b): return get_card_name(a).naturalnocasecmp_to(get_card_name(b)) < 0)

	return result

func get_card_name(card_id: String) -> String:
	var card_data: CardData = card_database.cards.get(card_id)

	return card_data.name if card_data != null else card_id

## Coleção: nome + custo, quantas cópias já estão no deck de quantas possui,
## e "+" (desabilitado quando todas as cópias possuídas já estão no deck).
func create_collection_row(card_id: String) -> Control:
	var card_data: CardData = card_database.cards.get(card_id)
	var in_deck = working_deck.get_copies(card_id)
	var owned = campaign_state.get_copies(card_id)
	var row = create_row("%s  (mana %d)" % [get_card_name(card_id), card_data.cost if card_data != null else 0])
	var usage = Label.new()
	var add_button = Button.new()

	usage.text = "no deck: %d / %d" % [in_deck, owned]
	usage.custom_minimum_size = Vector2(110, 0)

	add_button.text = "+"
	add_button.custom_minimum_size = Vector2(44, 36)
	add_button.disabled = in_deck >= owned
	add_button.pressed.connect(_on_add_pressed.bind(card_id))

	row.add_child(usage)
	row.add_child(add_button)

	return row

func create_deck_row(card_id: String) -> Control:
	var row = create_row("%s ×%d" % [get_card_name(card_id), working_deck.get_copies(card_id)])
	var remove_button = Button.new()

	remove_button.text = "−"
	remove_button.custom_minimum_size = Vector2(44, 36)
	remove_button.pressed.connect(_on_remove_pressed.bind(card_id))

	row.add_child(remove_button)

	return row

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
