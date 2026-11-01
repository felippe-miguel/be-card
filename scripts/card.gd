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

const UNAFFORDABLE_COST_COLOR = Color(1, 0.4, 0.4, 1)

@onready var background: Panel = $Background
@onready var art: TextureRect = $Art
@onready var unit_frame: TextureRect = $UnitFrame
@onready var spell_frame: TextureRect = $SpellFrame
@onready var name_label: Label = $NameLabel
@onready var description_label: RichTextLabel = $DescriptionLabel
@onready var cost_label: Label = $CostLabel
@onready var target_label: Label = $TargetLabel
@onready var summon_preview_label: Label = $SummonPreviewLabel

## Convenção de nome de arquivo pra arte de carta: res://resources/images/
## cards/<CardData.id>.png. Cartas sem arquivo correspondente (ainda a
## maioria) escondem o TextureRect, mostrando só a moldura (UnitFrame/
## SpellFrame) por cima do fundo padrão.
const ART_PATH_FORMAT = "res://resources/images/cards/%s.png"

var data: CardData

## Posição/z-index de repouso na mão, definidos por quem organiza a mão
## (Game.layout_hand()). O hover anima a partir/para esses valores.
var rest_position: Vector2 = Vector2.ZERO
var rest_z_index: int = 0

var normal_style: StyleBoxFlat
var hover_style: StyleBoxFlat
var pending_style: StyleBoxFlat

## Cor normal (affordable) do custo, lida do próprio CostLabel.label_settings
## no _ready() — qualquer cor que for escolhida no editor pra ele vira
## automaticamente a cor "de volta ao normal" em set_affordable(), sem um
## valor fixo divergir do que o editor mostra.
var cost_label_normal_color: Color = Color.WHITE

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

## Tooltip de palavras-chave/unidade invocada (Passos 5 e 6 de docs/
## MERCHANT_CARDS_EXECUTION_PLAN.md). Só existe se setup() recebeu um
## KeywordDatabase; sem ele a carta se comporta como antes.
var keyword_tooltip: KeywordTooltip

const KEYWORD_TOOLTIP_SCENE = preload("res://scenes/keyword_tooltip.tscn")

signal played(card: Card)

func _ready() -> void:
	pivot_offset = size / 2.0

	normal_style = build_style(BORDER_COLOR, 2)
	hover_style = build_style(HOVER_BORDER_COLOR, 3)
	pending_style = build_style(PENDING_BORDER_COLOR, 4)
	background.add_theme_stylebox_override("panel", normal_style)

	## CostLabel usa um LabelSettings (não theme_override_colors) pra cor —
	## e um LabelSettings embutido na cena é COMPARTILHADO por todas as
	## instâncias de card.tscn, a menos que seja duplicado aqui: sem isto,
	## set_affordable() mudaria a cor do custo de TODAS as cartas da mão de
	## uma vez (a última chamada "venceria" pra todo mundo), em vez de só
	## desta carta. Guarda a cor original (a escolhida no editor) como "a
	## cor de quando dá pra pagar", antes de qualquer set_affordable() rodar.
	if cost_label.label_settings != null:
		cost_label.label_settings = cost_label.label_settings.duplicate()
		cost_label_normal_color = cost_label.label_settings.font_color

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

func setup(card_data: CardData, unit_database: UnitDatabase = null, keyword_database: KeywordDatabase = null) -> void:
	data = card_data
	name_label.text = data.name
	set_description_bbcode(KeywordText.to_bbcode(data.get_display_description(unit_database), keyword_database))
	cost_label.text = str(data.cost)
	target_label.text = "Alvo: " + data.get_target_description()

	update_summon_preview(unit_database)
	update_art()
	update_frame()
	update_keyword_tooltip(unit_database, keyword_database)

## Único lugar que escreve a descrição: recebe BBCode já pronto (destacado
## por KeywordText, ou só escapado quando não há KeywordDatabase).
func set_description_bbcode(bbcode: String) -> void:
	description_label.text = "[center]%s[/center]" % bbcode

## Carrega res://resources/images/cards/<CardData.id>.png, se existir —
## ver ART_PATH_FORMAT acima.
func update_art() -> void:
	var path = ART_PATH_FORMAT % data.id

	if ResourceLoader.exists(path):
		art.texture = load(path)
		art.visible = true
	else:
		art.visible = false

## Moldura por tipo de carta: invocação (type "unit") mostra UnitFrame; o
## resto (feitiços, type "skill") mostra SpellFrame. Cada moldura é um nó
## próprio na cena pra poder ser posicionada à mão no editor (as imagens
## não têm o mesmo enquadramento).
func update_frame() -> void:
	var is_unit = data.type == "unit"

	unit_frame.visible = is_unit
	spell_frame.visible = not is_unit

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

## Resolve uma vez (no setup) o que o tooltip mostra: o bloco da unidade
## invocada (se a carta invoca e unit_database veio) e as palavras-chave
## derivadas dos efeitos. Sem keyword_database, não há tooltip nenhum.
func update_keyword_tooltip(unit_database: UnitDatabase, keyword_database: KeywordDatabase) -> void:
	if keyword_tooltip != null:
		keyword_tooltip.hide_tooltip()

	if keyword_database == null:
		return

	if keyword_tooltip == null:
		keyword_tooltip = KEYWORD_TOOLTIP_SCENE.instantiate()
		add_child(keyword_tooltip)

	keyword_tooltip.keyword_database = keyword_database

	var unit_data: UnitData = null

	if unit_database != null:
		unit_data = unit_database.units.get(data.get_summon_unit_id())

	if unit_data != null:
		## Sem description própria, a face da carta já mostra a descrição da
		## unidade (get_display_description()); o tooltip não a repete.
		keyword_tooltip.set_unit(unit_data, TargetSystem.describe_pattern(unit_data.attack_pattern, unit_data.attack_pattern_count), data.description != "")
	else:
		keyword_tooltip.set_unit(null)

	keyword_tooltip.set_keywords(keyword_database.get_keywords(data.get_keyword_ids(unit_database)))

func hide_keyword_tooltip() -> void:
	if keyword_tooltip != null:
		keyword_tooltip.hide_tooltip()

## Destaca o custo em vermelho quando o jogador não tem mana suficiente
## para jogar esta carta agora. CostLabel tem um LabelSettings próprio (ver
## _ready()), e um LabelSettings atribuído sempre vence sobre
## theme_override_colors/font_color — por isso a cor é mudada direto nele,
## não via add_theme_color_override() (que não teria efeito nenhum aqui).
func set_affordable(affordable: bool) -> void:
	var color = cost_label_normal_color if affordable else UNAFFORDABLE_COST_COLOR

	if cost_label.label_settings != null:
		cost_label.label_settings.font_color = color
	else:
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
	hide_keyword_tooltip()

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

	if pending:
		hide_keyword_tooltip()

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

	if keyword_tooltip != null:
		keyword_tooltip.show_beside(self)

func _on_mouse_exited() -> void:
	hide_keyword_tooltip()

	if any_card_pending or is_leaving:
		return

	apply_resting_style()

	z_index = rest_z_index

	animate_to(rest_position, 1.0)

## top_level desacopla o desenho do tooltip da carta; por segurança, ele
## nunca fica na tela se a carta sair da árvore.
func _exit_tree() -> void:
	hide_keyword_tooltip()

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
