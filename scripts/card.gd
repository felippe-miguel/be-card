class_name Card
extends Control

## Ajuste visual de hover: a carta sob o mouse cresce um pouco, sobe um
## pouco, ganha um contorno mais claro e vai para o topo da pilha
## enquanto o mouse estiver sobre ela. Ao sair, volta ao z_index de
## repouso (fixo, definido por move_to_hand_position()/play_draw_entrance())
## — não fica "grudada" no topo.
const HOVER_SCALE = 1.12
const HOVER_LIFT = 24.0
const HOVER_ANIMATION_DURATION = 0.1
const HOVERED_Z_INDEX = 100

## Compra: a carta entra pequena/transparente na posição do baralho e
## cresce até o tamanho normal no lugar dela na mão (ver
## play_draw_entrance()). Descarte: o inverso, encolhendo rumo à pilha de
## descarte/cemitério antes de ser destruída (ver play_discard_exit()).
const DRAW_ANIMATION_DURATION = 0.25
const DISCARD_ANIMATION_DURATION = 0.2
const REFLOW_ANIMATION_DURATION = 0.15

const BACKGROUND_COLOR = Color(0.18359044, 0.18359044, 0.18359044, 1)
const BORDER_COLOR = Color(0.4, 0.4, 0.4, 1)
const HOVER_BORDER_COLOR = Color(0.95, 0.85, 0.55, 0.9)
const PENDING_BORDER_COLOR = Color(0.35, 0.75, 1.0, 1)
const SHADOW_COLOR = Color(0, 0, 0, 0.3)

const AFFORDABLE_COST_COLOR = Color(1, 1, 1, 1)
const UNAFFORDABLE_COST_COLOR = Color(1, 0.4, 0.4, 1)

@onready var background: Panel = $Background
@onready var art: TextureRect = $Art
@onready var name_label: Label = $NameLabel
@onready var description_label: Label = $DescriptionLabel
@onready var cost_label: Label = $CostLabel
@onready var target_label: Label = $TargetLabel
@onready var summon_preview_label: Label = $SummonPreviewLabel

## Convenção de nome de arquivo pra arte de carta: res://resources/images/
## cards/<CardData.id>.png. Cartas sem arquivo correspondente (ainda a
## maioria) escondem o TextureRect, mostrando só a moldura (Frame) por
## cima do fundo padrão.
const ART_PATH_FORMAT = "res://resources/images/cards/%s.png"

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
## Game.render_hand() também zera isso a cada reconstrução da mão, como
## rede de segurança (set_pending(false) já zera sozinho no caminho
## normal, mas é um no-op se a carta pendente já estiver is_leaving — ver
## set_pending()).
static var any_card_pending: bool = false

## true a partir do momento em que esta carta foi jogada/descartada e está
## animando para fora da mão (play_discard_exit()) — o nó continua vivo
## (queue_free só roda ao fim do tween) só pra terminar a animação; nesse
## meio-tempo ela já não conta mais como "carta da mão" pra ninguém (ver
## Game.render_hand()), então hover/pending não devem mais mexer nela.
var is_leaving: bool = false

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
	update_art()

## Carrega res://resources/images/cards/<CardData.id>.png, se existir —
## ver ART_PATH_FORMAT acima.
func update_art() -> void:
	var path = ART_PATH_FORMAT % data.id

	if ResourceLoader.exists(path):
		art.texture = load(path)
		art.visible = true
	else:
		art.visible = false

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

## Reposiciona uma carta que JÁ está na mão (ex: outra carta foi jogada ao
## lado e a mão inteira reorganizou) — anima suavemente até o novo lugar,
## em vez de saltar na hora (reaproveita animate_to(), o mesmo tween do
## hover, já que é a mesma coisa: mover position/scale com um tween).
func move_to_hand_position(new_position: Vector2, z: int) -> void:
	rest_position = new_position
	rest_z_index = z
	z_index = z

	animate_to(new_position, 1.0, REFLOW_ANIMATION_DURATION)

## Compra: a carta nasce em from_position (a posição do baralho, em
## coordenadas locais do container da mão — ver Game.pile_entry_position()),
## pequena e transparente, e anima crescendo/aparecendo até new_position —
## o efeito de "sair do baralho e ir pra mão".
func play_draw_entrance(from_position: Vector2, new_position: Vector2, z: int) -> void:
	rest_position = new_position
	rest_z_index = z

	position = from_position
	scale = Vector2(0.4, 0.4)
	modulate.a = 0.0
	z_index = z

	if hover_tween != null:
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.set_trans(Tween.TRANS_CUBIC)
	hover_tween.set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "position", new_position, DRAW_ANIMATION_DURATION)
	hover_tween.tween_property(self, "scale", Vector2.ONE, DRAW_ANIMATION_DURATION)
	hover_tween.tween_property(self, "modulate:a", 1.0, DRAW_ANIMATION_DURATION * 0.6)

## Jogada/descartada: anima encolhendo/sumindo rumo a to_position (a
## pilha de descarte ou cemitério, conforme o destino real da carta — ver
## Game.animate_card_leaving()) e só então destrói o nó. mouse_filter vira
## IGNORE pra esta carta não reagir mais a hover enquanto se despede.
func play_discard_exit(to_position: Vector2) -> void:
	is_leaving = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if hover_tween != null:
		hover_tween.kill()

	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", to_position, DISCARD_ANIMATION_DURATION)
	tween.tween_property(self, "scale", Vector2(0.3, 0.3), DISCARD_ANIMATION_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, DISCARD_ANIMATION_DURATION)
	tween.chain().tween_callback(queue_free)

## Marca/desmarca esta carta como a que está aguardando alvo. Chamado por
## Game ao entrar em TARGETING_UNIT/TARGETING_FLOOR/TARGETING_POSITION.
## Trava a carta no estado "grande e elevada" do hover — não solta mais
## até deixar de estar pendente — e, enquanto isso durar, nenhuma carta
## (nem esta) reage a hover de verdade (ver any_card_pending).
func set_pending(pending: bool) -> void:
	## Esta carta já está animando pra fora da mão (play_discard_exit()) —
	## isto chega aqui quando Game.cancel_pending_action() tenta "destravar"
	## a carta pendente DEPOIS de ela já ter sido descartada com sucesso
	## (Game.render_hand() já rodou e iniciou a saída); nada a fazer, e
	## animate_to() aqui brigaria com o tween de saída.
	if is_leaving:
		return

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
	if any_card_pending or is_leaving:
		return

	background.add_theme_stylebox_override("panel", hover_style)

	z_index = HOVERED_Z_INDEX

	animate_to(rest_position - Vector2(0, HOVER_LIFT), HOVER_SCALE)

func _on_mouse_exited() -> void:
	if any_card_pending or is_leaving:
		return

	apply_resting_style()

	z_index = rest_z_index

	animate_to(rest_position, 1.0)

func animate_to(target_position: Vector2, target_scale: float, duration: float = HOVER_ANIMATION_DURATION) -> void:
	if hover_tween != null:
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.tween_property(self, "position", target_position, duration)
	hover_tween.tween_property(self, "scale", Vector2(target_scale, target_scale), duration)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			played.emit(self)
