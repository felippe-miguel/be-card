class_name Overworld
extends Control

## Mapa do mundo (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa 1). Desenha o grafo
## de WorldMapData — cada ponto como um Button na sua posição, cada conexão
## como uma linha — e deixa o jogador viajar entre pontos conectados
## (Passo 1.3) ou entrar no ponto atual (Passo 1.4). A regra de "pra onde
## dá pra ir" é do CampaignState; aqui só se reflete isso na tela.

signal back_to_menu_pressed

## Clique no ponto ATUAL quando ele tem algo pra entrar (WorldPointData.
## can_enter()) — Main decide o que abrir (Passo 1.4: a batalha). Chegar
## num ponto nunca entra sozinho: dá pra passar por um combate sem lutar.
signal point_entered(point_id: String)

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

## Rótulo de tipo mostrado embaixo do nome de cada ponto — cru de
## propósito, até existir um visual próprio por tipo (Passo 1.6).
const POINT_TYPE_LABELS = {
	"camp": "acampamento",
	"combat": "combate",
}

@onready var back_button: Button = $TopBar/BackButton
@onready var location_label: Label = $TopBar/LocationLabel
@onready var map_canvas: Control = $MapCanvas

## Recebidos de Main via setup(), antes de entrar na árvore — o overworld
## não carrega o mapa nem cria a campanha sozinho; Main guarda os dois e
## eles sobrevivem a esta tela ser liberada (idas e vindas pro combate, a
## partir do Passo 1.4).
var world_map: WorldMapData
var campaign_state: CampaignState

## id do ponto -> Button desenhado pra ele.
var point_buttons: Dictionary = {}

func setup(map: WorldMapData, state: CampaignState) -> void:
	world_map = map
	campaign_state = state

func _ready() -> void:
	back_button.pressed.connect(back_to_menu_pressed.emit)

	render_map()

	## Conexão some sozinha quando esta tela é liberada (o Godot desconecta
	## sinais cujo alvo foi destruído), então não precisa desconectar à mão
	## mesmo com campaign_state vivendo mais que o overworld.
	campaign_state.changed.connect(refresh_points)
	refresh_points()

## Esc volta pro menu principal — mesmo efeito do botão "Voltar ao menu".
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_to_menu_pressed.emit()

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

	return button

func get_point_text(point: WorldPointData) -> String:
	var is_current = point.id == campaign_state.current_point_id
	var marker = CURRENT_POINT_MARKER if is_current else ""
	var won_marker = WON_COMBAT_MARKER if campaign_state.is_combat_won(point.id) else ""
	var hint = ENTER_HINT if is_current and point.can_enter() else ""

	return "%s%s%s\n[%s]%s" % [marker, won_marker, point.name, POINT_TYPE_LABELS.get(point.type, point.type), hint]

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
