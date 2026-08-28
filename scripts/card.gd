class_name Card
extends Control

## Ajuste visual de hover: a carta sob o mouse cresce um pouco, sobe um
## pouco, ganha um contorno mais claro e vai para o topo da pilha
## enquanto o mouse estiver sobre ela. Ao sair, volta ao z_index de
## repouso (fixo, definido por set_hand_position) — não fica "grudada"
## no topo.
const HOVER_SCALE = 1.12
const HOVER_LIFT = 24.0
const HOVER_ANIMATION_DURATION = 0.1
const HOVERED_Z_INDEX = 100

const BACKGROUND_COLOR = Color(0.18359044, 0.18359044, 0.18359044, 1)
const BORDER_COLOR = Color(0.4, 0.4, 0.4, 1)
const HOVER_BORDER_COLOR = Color(0.95, 0.85, 0.55, 0.9)
const PENDING_BORDER_COLOR = Color(0.35, 0.75, 1.0, 1)
const SHADOW_COLOR = Color(0, 0, 0, 0.3)

const AFFORDABLE_COST_COLOR = Color(1, 1, 1, 1)
const UNAFFORDABLE_COST_COLOR = Color(1, 0.4, 0.4, 1)

@onready var background: Panel = $Background
@onready var name_label: Label = $NameLabel
@onready var description_label: Label = $DescriptionLabel
@onready var cost_label: Label = $CostLabel
@onready var target_label: Label = $TargetLabel
@onready var summon_preview_label: Label = $SummonPreviewLabel

var data: CardData

## Posição/z-index de repouso na mão, definidos por quem organiza a mão
## (Game.layout_hand()). O hover anima a partir/para esses valores.
var rest_position: Vector2 = Vector2.ZERO
var rest_z_index: int = 0

var normal_style: StyleBoxFlat
var hover_style: StyleBoxFlat
var pending_style: StyleBoxFlat

## true enquanto esta carta é a jogada aguardando alvo (Game.pending_card).
## Muda a cor de repouso da borda para se distinguir das demais na mão, e
## trava o estado de hover (maior, deslocada pra cima) mesmo sem o mouse
## em cima.
var is_pending: bool = false

## Compartilhado entre todas as cartas da mão — só pode haver uma carta
## pendente por vez (Game.pending_card), então uma flag estática simples
## já basta para bloquear o hover das demais enquanto isso durar.
## Game.render_hand() zera isso a cada reconstrução da mão, já que a
## carta pendente nunca chama set_pending(false) sozinha — o nó dela é
## destruído junto (ver docs/ARCHITECTURE.md).
static var any_card_pending: bool = false

var hover_tween: Tween

signal played(card: Card)

func _ready() -> void:
	pivot_offset = size / 2.0

	normal_style = build_style(BORDER_COLOR, 2)
	hover_style = build_style(HOVER_BORDER_COLOR, 3)
	pending_style = build_style(PENDING_BORDER_COLOR, 4)
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

func setup(card_data: CardData, unit_database: UnitDatabase = null) -> void:
	data = card_data
	name_label.text = data.name
	description_label.text = data.description
	cost_label.text = str(data.cost)
	target_label.text = "Alvo: " + data.get_target_description()

	update_summon_preview(unit_database)

## Mostra ATK/HP base da unidade invocada, para cartas de invocação, sem
## precisar abrir data/units/*.json ou jogar a carta pra descobrir. Não
## mostra nada se a carta não invoca unidade ou se unit_database não foi
## passado (chamador que não tem acesso a ele, ex: preview fora do jogo).
func update_summon_preview(unit_database: UnitDatabase) -> void:
	var unit_id = data.get_summon_unit_id()

	if unit_id == "" or unit_database == null:
		summon_preview_label.visible = false
		return

	var unit_data: UnitData = unit_database.units.get(unit_id)

	if unit_data == null:
		summon_preview_label.visible = false
		return

	summon_preview_label.text = "ATK %d / HP %d" % [unit_data.attack, unit_data.max_hp]
	summon_preview_label.visible = true

## Destaca o custo em vermelho quando o jogador não tem mana suficiente
## para jogar esta carta agora.
func set_affordable(affordable: bool) -> void:
	var color = AFFORDABLE_COST_COLOR if affordable else UNAFFORDABLE_COST_COLOR

	cost_label.add_theme_color_override("font_color", color)

## Define a posição/z-index de repouso da carta na mão (ordem de
## empilhamento fixa: cartas mais à direita recebem z_index maior).
func set_hand_position(new_position: Vector2, z: int) -> void:
	rest_position = new_position
	rest_z_index = z

	position = new_position
	z_index = z

## Marca/desmarca esta carta como a que está aguardando alvo. Chamado por
## Game ao entrar em TARGETING_UNIT/TARGETING_FLOOR/TARGETING_POSITION.
## Trava a carta no estado "grande e elevada" do hover — não solta mais
## até deixar de estar pendente — e, enquanto isso durar, nenhuma carta
## (nem esta) reage a hover de verdade (ver any_card_pending).
func set_pending(pending: bool) -> void:
	is_pending = pending
	any_card_pending = pending

	apply_resting_style()

	if pending:
		z_index = HOVERED_Z_INDEX
		animate_to(rest_position - Vector2(0, HOVER_LIFT), HOVER_SCALE)
	else:
		z_index = rest_z_index
		animate_to(rest_position, 1.0)

## Estilo de "repouso" (fora de hover): pending_style se esta carta está
## aguardando alvo, senão normal_style. O hover sempre tem prioridade
## visual, mas ao sair do hover volta para este estado, não direto para
## normal_style — assim a carta pendente não perde o destaque.
func apply_resting_style() -> void:
	background.add_theme_stylebox_override("panel", pending_style if is_pending else normal_style)

func _on_mouse_entered() -> void:
	if any_card_pending:
		return

	background.add_theme_stylebox_override("panel", hover_style)

	z_index = HOVERED_Z_INDEX

	animate_to(rest_position - Vector2(0, HOVER_LIFT), HOVER_SCALE)

func _on_mouse_exited() -> void:
	if any_card_pending:
		return

	apply_resting_style()

	z_index = rest_z_index

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
