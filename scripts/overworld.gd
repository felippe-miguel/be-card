class_name Overworld
extends Control

## Mapa do mundo (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa 1). Desenha o grafo
## de WorldMapData — cada ponto como um Button na sua posição, cada conexão
## como uma linha — e deixa o jogador viajar entre pontos conectados
## (Passo 1.3) ou entrar no ponto atual (Passo 1.4). A regra de "pra onde
## dá pra ir" é do CampaignState; aqui só se reflete isso na tela.

signal back_to_menu_pressed

## Clique no ponto ATUAL quando ele tem algo pra entrar (WorldPointData.
## can_enter()) — Main decide o que abrir (batalha, ou o placeholder de
## mercador/evento). Chegar num ponto nunca entra sozinho: dá pra passar
## por um combate sem lutar.
signal point_entered(point_id: String)

## "Editar" num deck do painel de decks, ou "Criar novo deck" (deck_index
## -1) — Main abre o DeckBuilder (Etapa 5).
signal deck_edit_requested(deck_index: int)

const POINT_BUTTON_SIZE = Vector2(170, 56)
const CONNECTION_COLOR = Color(0.75, 0.7, 0.55, 1)
const CONNECTION_WIDTH = 4.0

## Destaque cru do ponto atual — até existir um visual de verdade.
const CURRENT_POINT_MODULATE = Color(1, 0.85, 0.4, 1)
const CURRENT_POINT_MARKER = "★ "
const ENTER_HINT = " — entrar"

## Estado dos pontos (Passo 1.5), igualmente cru: combate vencido ganha um
## marcador no nome; ponto já visitado (fora o atual) ganha um tom azulado.
const WON_COMBAT_MARKER = "✔ "
const VISITED_POINT_MODULATE = Color(0.7, 0.85, 1, 1)

## Visual mínimo por tipo (Passo 1.6): só a cor do texto do botão, pra dar
## pra distinguir combate/mercador/evento de relance. Tipo sem cor aqui
## (ex: "camp") fica com a cor padrão do tema. Fica no texto, não em
## modulate, porque modulate já sinaliza ponto atual/visitado (Passo 1.5).
const POINT_TYPE_COLORS = {
	"combat": Color(1, 0.55, 0.5, 1),
	"card_merchant": Color(0.55, 1, 0.55, 1),
	"artifact_merchant": Color(0.85, 0.6, 1, 1),
	"event": Color(0.5, 0.9, 1, 1),
}

## Ponto desabilitado (fora de alcance) mantém o tom do tipo, só apagado —
## senão todos os pontos distantes ficariam iguais em cinza.
const DISABLED_TYPE_COLOR_ALPHA = 0.45

@onready var back_button: Button = $TopBar/BackButton
@onready var location_label: Label = $TopBar/LocationLabel
@onready var map_canvas: Control = $MapCanvas
@onready var collection_button: Button = $TopBar/CollectionButton
@onready var collection_panel: PanelContainer = $CollectionPanel
@onready var collection_title: Label = $CollectionPanel/CollectionMargin/CollectionVBox/CollectionTitle
@onready var collection_list: Label = $CollectionPanel/CollectionMargin/CollectionVBox/CollectionList
@onready var deck_button: Button = $TopBar/DeckButton
@onready var deck_panel: PanelContainer = $DeckPanel
@onready var deck_list_container: VBoxContainer = $DeckPanel/DeckMargin/DeckVBox/DeckList
@onready var new_deck_button: Button = $DeckPanel/DeckMargin/DeckVBox/NewDeckButton
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var notice_label: Label = $NoticeLabel

## Recebidos de Main via setup(), antes de entrar na árvore — o overworld
## não carrega o mapa nem cria a campanha sozinho; Main guarda os dois e
## eles sobrevivem a esta tela ser liberada (idas e vindas pro combate, a
## partir do Passo 1.4).
var world_map: WorldMapData
var campaign_state: CampaignState

## Só pra mostrar nomes de cartas e artefatos (o CampaignState guarda ids).
var card_database: CardDatabase
var artifact_database: ArtifactDatabase

## id do ponto -> Button desenhado pra ele.
var point_buttons: Dictionary = {}

## Mensagem mostrada ao chegar no mapa (ex: ouro ganho no combate de onde
## o jogador acabou de voltar — ver Main._on_battle_finished()). "" =
## nenhuma. Fica até a tela ser trocada; sem timer, de propósito (cru).
var notice: String = ""

func setup(map: WorldMapData, state: CampaignState, cards: CardDatabase, artifacts: ArtifactDatabase, arrival_notice: String = "") -> void:
	world_map = map
	campaign_state = state
	card_database = cards
	artifact_database = artifacts
	notice = arrival_notice

func _ready() -> void:
	back_button.pressed.connect(back_to_menu_pressed.emit)
	collection_button.pressed.connect(toggle_collection_panel)
	deck_button.pressed.connect(toggle_deck_panel)
	new_deck_button.pressed.connect(deck_edit_requested.emit.bind(-1))

	render_map()

	## Conexão some sozinha quando esta tela é liberada (o Godot desconecta
	## sinais cujo alvo foi destruído), então não precisa desconectar à mão
	## mesmo com campaign_state vivendo mais que o overworld.
	campaign_state.changed.connect(refresh_points)
	campaign_state.changed.connect(refresh_collection_panel)
	campaign_state.changed.connect(refresh_deck_ui)
	campaign_state.changed.connect(refresh_gold)
	refresh_points()
	refresh_collection_panel()
	refresh_deck_ui()
	refresh_gold()

	notice_label.text = notice
	notice_label.visible = notice != ""

## Esc sobe um nível: fecha o painel lateral aberto (coleção ou decks); sem
## painel aberto, volta pro menu principal (mesmo efeito do botão "Voltar
## ao menu").
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()

		if collection_panel.visible or deck_panel.visible:
			close_side_panels()
		else:
			back_to_menu_pressed.emit()

## Coleção e decks dividem o mesmo canto da tela — abrir um fecha o outro.
func close_side_panels() -> void:
	collection_panel.visible = false
	deck_panel.visible = false

## Painel cru, só leitura (Etapa 2): lista as cartas possuídas e quantas
## cópias de cada, pra conferir a coleção sem uma tela própria. A tela de
## verdade (montar decks a partir da coleção) é o DeckBuilder da Etapa 5.
func toggle_collection_panel() -> void:
	var opening = not collection_panel.visible

	close_side_panels()
	collection_panel.visible = opening

## Painel de escolha de deck (Etapa 3): o deck ativo é escolhido aqui, no
## overworld, e vale pra todo combate até ser trocado — não se escolhe deck
## a cada combate (decisão do usuário). Criar/editar decks abre uma tela
## própria, o DeckBuilder (Etapa 5) — o painel é pequeno demais pra isso.
func toggle_deck_panel() -> void:
	var opening = not deck_panel.visible

	close_side_panels()
	deck_panel.visible = opening

func refresh_gold() -> void:
	gold_label.text = "Ouro: %d" % campaign_state.gold

## Recria a lista inteira a cada mudança (poucos decks, sem estado próprio
## nos botões) — mais simples que sincronizar botão a botão.
func refresh_deck_ui() -> void:
	var active_deck = campaign_state.get_active_deck()

	deck_button.text = "Deck: %s" % (active_deck.name if active_deck != null else "nenhum")

	for child in deck_list_container.get_children():
		child.queue_free()

	for i in range(campaign_state.deck_lists.size()):
		deck_list_container.add_child(create_deck_option(i))

## Uma linha por deck: botão de selecionar + "Editar". Deck ativo: marcado
## com ✔. Deck inválido (vazio, ou usando mais cópias do que a coleção
## tem): não selecionável, com o motivo no texto — mas ainda editável, pra
## dar pra consertar.
func create_deck_option(index: int) -> HBoxContainer:
	var deck_list: DeckList = campaign_state.deck_lists[index]
	var is_active = index == campaign_state.active_deck_index
	var is_valid = campaign_state.is_deck_valid(deck_list)
	var row = HBoxContainer.new()
	var button = Button.new()
	var edit_button = Button.new()

	button.text = "%s%s (%d cartas)%s\nArtefato: %s" % [
		"✔ " if is_active else "",
		deck_list.name,
		deck_list.get_total_card_count(),
		"" if is_valid else " — inválido",
		get_artifact_name(deck_list.artifact_id) if deck_list.artifact_id != "" else "nenhum"
	]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not is_valid
	button.pressed.connect(campaign_state.select_deck.bind(index))

	edit_button.text = "Editar"
	edit_button.pressed.connect(deck_edit_requested.emit.bind(index))

	row.add_child(button)
	row.add_child(edit_button)

	return row

func refresh_collection_panel() -> void:
	collection_title.text = "Coleção — %d cartas" % campaign_state.get_total_card_count()

	var lines: PackedStringArray = []

	for card_id in get_sorted_collection_ids():
		lines.append("%s ×%d" % [get_card_name(card_id), campaign_state.get_copies(card_id)])

	if lines.is_empty():
		lines.append("Nenhuma carta.")

	## Artefatos na mesma lista, numa seção própria (Etapa 6) — painel cru,
	## só leitura, igual às cartas.
	lines.append("")
	lines.append("Artefatos:")

	var artifact_ids = campaign_state.artifacts.keys()

	artifact_ids.sort_custom(func(a, b): return get_artifact_name(a).naturalnocasecmp_to(get_artifact_name(b)) < 0)

	for artifact_id in artifact_ids:
		lines.append(get_artifact_name(artifact_id))

	if artifact_ids.is_empty():
		lines.append("Nenhum artefato.")

	collection_list.text = "\n".join(lines)

func get_artifact_name(artifact_id: String) -> String:
	var artifact: ArtifactData = artifact_database.artifacts.get(artifact_id)

	return artifact.name if artifact != null else artifact_id

## Ordem alfabética pelo nome exibido, não pelo id — é o que o jogador lê.
func get_sorted_collection_ids() -> Array:
	var ids = campaign_state.collection.keys()

	ids.sort_custom(func(a, b): return get_card_name(a).naturalnocasecmp_to(get_card_name(b)) < 0)

	return ids

func get_card_name(card_id: String) -> String:
	var card_data: CardData = card_database.cards.get(card_id)

	return card_data.name if card_data != null else card_id

## Linhas primeiro e botões depois, pra os botões ficarem por cima das
## pontas das linhas (ordem de filhos = ordem de desenho).
func render_map() -> void:
	for connection in world_map.connections:
		var point_a: WorldPointData = world_map.points[connection[0]]
		var point_b: WorldPointData = world_map.points[connection[1]]

		map_canvas.add_child(create_connection_line(point_a.position, point_b.position))

	for point_id in world_map.points:
		var point: WorldPointData = world_map.points[point_id]
		var button = create_point_button(point)

		button.pressed.connect(_on_point_pressed.bind(point_id))

		point_buttons[point_id] = button
		map_canvas.add_child(button)

		## Centraliza só depois de entrar na árvore: o texto em duas linhas
		## pode deixar o botão maior que POINT_BUTTON_SIZE, e o tamanho
		## real (com fonte do tema) só é conhecido aqui. position aponta
		## pro centro do ponto, pra a linha da conexão chegar no meio do
		## botão.
		button.reset_size()
		button.position = point.position - button.size / 2

func create_connection_line(from: Vector2, to: Vector2) -> Line2D:
	var line = Line2D.new()

	line.points = PackedVector2Array([from, to])
	line.width = CONNECTION_WIDTH
	line.default_color = CONNECTION_COLOR

	return line

func create_point_button(point: WorldPointData) -> Button:
	var button = Button.new()

	button.text = get_point_text(point)
	button.custom_minimum_size = POINT_BUTTON_SIZE

	apply_type_color(button, point.type)

	return button

## Sobrescreve todos os estados de cor de fonte do Button (normal, hover,
## pressionado, foco), senão a cor do tipo sumiria ao passar o mouse.
func apply_type_color(button: Button, type: String) -> void:
	if not POINT_TYPE_COLORS.has(type):
		return

	var color: Color = POINT_TYPE_COLORS[type]

	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color_name, color)

	button.add_theme_color_override("font_disabled_color", Color(color, DISABLED_TYPE_COLOR_ALPHA))

func get_point_text(point: WorldPointData) -> String:
	var is_current = point.id == campaign_state.current_point_id
	var marker = CURRENT_POINT_MARKER if is_current else ""
	var won_marker = WON_COMBAT_MARKER if campaign_state.is_combat_won(point.id) else ""
	var hint = ENTER_HINT if is_current and point.can_enter() else ""

	return "%s%s%s\n[%s]%s" % [marker, won_marker, point.name, point.get_type_name().to_lower(), hint]

func get_point_modulate(point_id: String) -> Color:
	if point_id == campaign_state.current_point_id:
		return CURRENT_POINT_MODULATE

	if campaign_state.is_visited(point_id):
		return VISITED_POINT_MODULATE

	return Color.WHITE

## Ponto atual: destacado (cor + marcador) e habilitado — clicar nele entra
## no ponto, se houver algo pra entrar (ver _on_point_pressed()). Vizinhos
## do atual: habilitados (clicar = viajar). O resto: desabilitado, já que só
## dá pra viajar por uma conexão existente.
func refresh_points() -> void:
	for point_id in point_buttons:
		var button: Button = point_buttons[point_id]
		var is_current = point_id == campaign_state.current_point_id

		button.text = get_point_text(world_map.points[point_id])
		button.modulate = get_point_modulate(point_id)
		button.disabled = not is_current and not campaign_state.can_travel_to(point_id, world_map)

	var current_point: WorldPointData = world_map.points.get(campaign_state.current_point_id)

	location_label.text = "Você está em: %s" % (current_point.name if current_point != null else "?")

func _on_point_pressed(point_id: String) -> void:
	if point_id == campaign_state.current_point_id:
		if world_map.points[point_id].can_enter():
			point_entered.emit(point_id)

		return

	## travel_to() já recusa sozinho qualquer destino inválido.
	campaign_state.travel_to(point_id, world_map)
