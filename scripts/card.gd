class_name Card
extends Control

## Ajuste visual de hover: a carta sob o mouse cresce um pouco, sobe um
## pouco e ganha um contorno mais claro. A borda/sombra normal já ajuda a
## perceber a ordem de empilhamento mesmo sem hover.
const HOVER_SCALE = 1.12
const HOVER_LIFT = 24.0
const HOVER_ANIMATION_DURATION = 0.1

const BACKGROUND_COLOR = Color(0.18359044, 0.18359044, 0.18359044, 1)
const BORDER_COLOR = Color(0.4, 0.4, 0.4, 1)
const HOVER_BORDER_COLOR = Color(0.95, 0.85, 0.55, 0.9)
const SHADOW_COLOR = Color(0, 0, 0, 0.3)

@onready var background: Panel = $Background
@onready var name_label: Label = $NameLabel
@onready var description_label: Label = $DescriptionLabel
@onready var cost_label: Label = $CostLabel
@onready var target_label: Label = $TargetLabel

var data: CardData

## Posição de repouso na mão, definida por quem organiza a mão
## (Game.layout_hand()). O hover anima a partir/para esse valor.
var rest_position: Vector2 = Vector2.ZERO

var normal_style: StyleBoxFlat
var hover_style: StyleBoxFlat

var hover_tween: Tween

## Emitido ao entrar o mouse, para quem organiza a mão decidir a ordem de
## empilhamento (ver Game._on_card_hovered()) — a carta em si não sabe
## z-index de nenhuma outra carta.
signal hovered(card: Card)
signal played(card: Card)

func _ready() -> void:
	pivot_offset = size / 2.0

	normal_style = build_style(BORDER_COLOR, 2)
	hover_style = build_style(HOVER_BORDER_COLOR, 3)
	background.add_theme_stylebox_override("panel", normal_style)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func build_style(border_color: Color, border_width: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()

	style.bg_color = BACKGROUND_COLOR
	style.set_border_width_all(border_width)
	style.border_color = border_color
	style.set_corner_radius_all(8)
	style.shadow_color = SHADOW_COLOR
	style.shadow_size = 6
	style.shadow_offset = Vector2(3, 4)

	return style

func setup(card_data: CardData) -> void:
	data = card_data
	name_label.text = data.name
	description_label.text = data.description
	cost_label.text = str(data.cost)
	target_label.text = "Alvo: " + data.get_target_description()

## Define a posição de repouso da carta na mão. Não mexe em z_index —
## quem controla a ordem de empilhamento é Game (ver bring_to_front()).
func set_hand_position(new_position: Vector2, z: int) -> void:
	rest_position = new_position

	position = new_position
	z_index = z

## Traz a carta para o topo da pilha, permanentemente (até a mão ser
## reconstruída), sem mexer em posição/escala.
func bring_to_front(z: int) -> void:
	z_index = z

func _on_mouse_entered() -> void:
	background.add_theme_stylebox_override("panel", hover_style)

	hovered.emit(self)

	animate_to(rest_position - Vector2(0, HOVER_LIFT), HOVER_SCALE)

func _on_mouse_exited() -> void:
	background.add_theme_stylebox_override("panel", normal_style)

	animate_to(rest_position, 1.0)

func animate_to(target_position: Vector2, target_scale: float) -> void:
	if hover_tween != null:
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.tween_property(self, "position", target_position, HOVER_ANIMATION_DURATION)
	hover_tween.tween_property(self, "scale", Vector2(target_scale, target_scale), HOVER_ANIMATION_DURATION)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			played.emit(self)
