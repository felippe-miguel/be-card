class_name KeywordTooltip
extends VBoxContainer

## Tooltip de palavras-chave ao lado de uma carta (docs/MERCHANT_CARDS_
## EXECUTION_PLAN.md, Passos 5 e 6): um bloco (PanelContainer) por
## palavra-chave — título em negrito na cor dela, explicação embaixo —
## precedido, opcionalmente, por um bloco da unidade invocada (set_unit()).
## Apresentação pura: recebe KeywordData/UnitData já resolvidos por quem o
## usa (Card) e só sabe se desenhar e se posicionar ao lado de um Control.
##
## Os textos são RichTextLabel com bbcode_enabled e fit_content desde já,
## e recebem BBCode de KeywordText (Passo 7).

const BLOCK_WIDTH = 240.0
const BLOCK_SEPARATION = 4
const SIDE_GAP = 12.0
const SCREEN_MARGIN = 4.0
const TOP_Z_INDEX = 4000
const MAX_LAYOUT_FRAMES = 8

const TEXT_COLOR = Color(0.012617188, 0.012617188, 0.012617188, 1)
const BACKGROUND_COLOR = Color(0.93, 0.88, 0.76, 1)
const BORDER_COLOR = Color(0.45, 0.33, 0.16, 1)
const SHADOW_COLOR = Color(0, 0, 0, 0.35)

var keywords: Array[KeywordData] = []

## Glossário usado pra destacar palavras-chave nas descrições (KeywordText).
## Quem usa o tooltip define antes de set_unit()/set_keywords(); null =
## descrições em texto puro, só escapado.
var keyword_database: KeywordDatabase
var unit_data: UnitData
var pattern_text: String = ""

## false quando quem usa o tooltip já mostra a descrição da unidade (a
## carta de invocação a exibe na própria face — ver
## CardData.get_display_description()), pra não repetir o mesmo texto.
var show_unit_description: bool = true

## Alvo atual de show_beside() e um contador que invalida posicionamentos
## adiados quando o tooltip é escondido/reaberto antes deles rodarem.
var target: Control
var request_id: int = 0

func _init() -> void:
	## top_level: não herda escala/posição da carta (que cresce no hover) e
	## não é cortado por ScrollContainer. z_as_relative = false + z_index
	## alto: desenha por cima das cartas vizinhas, que também têm z_index
	## (HOVERED_Z_INDEX = 100 na carta sob o mouse).
	top_level = true
	z_as_relative = false
	z_index = TOP_Z_INDEX
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	custom_minimum_size = Vector2(BLOCK_WIDTH, 0)
	add_theme_constant_override("separation", BLOCK_SEPARATION)

func set_keywords(new_keywords: Array[KeywordData]) -> void:
	keywords = new_keywords

	rebuild()

## Bloco de cabeçalho com a unidade invocada. null limpa o bloco.
func set_unit(new_unit_data: UnitData, new_pattern_text: String = "", new_show_description: bool = true) -> void:
	unit_data = new_unit_data
	pattern_text = new_pattern_text
	show_unit_description = new_show_description

	rebuild()

## Texto de descrição já em BBCode: destacado se há glossário, escapado se não.
func describe(text: String) -> String:
	return KeywordText.to_bbcode(text, keyword_database)

func has_content() -> bool:
	return unit_data != null or not keywords.is_empty()

func get_block_count() -> int:
	return get_child_count()

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	if unit_data != null:
		add_child(build_unit_block())

	for keyword in keywords:
		add_child(build_keyword_block(keyword))

	if not has_content():
		hide_tooltip()

func build_unit_block() -> PanelContainer:
	var box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)

	box.add_child(make_text_label("[b]%s[/b]" % KeywordText.escape_bbcode(unit_data.name), 16))
	box.add_child(make_text_label("ATK %d / HP %d" % [unit_data.attack, unit_data.max_hp], 13))

	if pattern_text != "":
		box.add_child(make_text_label(describe(pattern_text), 12))

	if show_unit_description and unit_data.description != "":
		box.add_child(make_text_label(describe(unit_data.description), 12))

	return wrap_in_block(box)

func build_keyword_block(keyword: KeywordData) -> PanelContainer:
	var box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)

	var title = "[b]%s[/b]" % KeywordText.escape_bbcode(keyword.name)

	if keyword.has_color:
		title = "[color=#%s]%s[/color]" % [keyword.color.to_html(false), title]

	box.add_child(make_text_label(title, 15))
	box.add_child(make_text_label(describe(keyword.description), 12))

	return wrap_in_block(box)

func wrap_in_block(content: Control) -> PanelContainer:
	var block = PanelContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.custom_minimum_size = Vector2(BLOCK_WIDTH, 0)
	block.add_theme_stylebox_override("panel", build_block_style())
	block.add_child(content)

	return block

func build_block_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()

	style.bg_color = BACKGROUND_COLOR
	style.set_border_width_all(2)
	style.border_color = BORDER_COLOR
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	style.shadow_color = SHADOW_COLOR
	style.shadow_size = 5
	style.shadow_offset = Vector2(2, 3)

	return style

## Texto em BBCode (escapado ou destacado por KeywordText). fit_content + autowrap:
## a altura segue o conteúdo na largura fixa do bloco.
func make_text_label(bbcode: String, font_size: int) -> RichTextLabel:
	var label = RichTextLabel.new()

	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("default_color", TEXT_COLOR)
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	label.text = bbcode

	return label

## Mostra o tooltip à direita do target (ou à esquerda, se cruzar a borda
## direita do viewport), alinhado ao topo e preso dentro do viewport. Sem
## conteúdo, não mostra nada. O tamanho só fica certo depois que os
## RichTextLabel com autowrap fazem layout (leva um ou dois frames), então
## o tooltip fica transparente até lá e o retângulo do target é lido de
## novo no fim, já com ele no lugar final.
func show_beside(new_target: Control) -> void:
	if not has_content() or new_target == null or not new_target.is_inside_tree():
		hide_tooltip()
		return

	target = new_target
	request_id += 1

	modulate.a = 0.0
	visible = true

	reset_size()
	reposition()
	finish_layout(request_id)

## Reposiciona a cada frame até o tamanho parar de mudar (no mínimo 2
## frames, no máximo MAX_LAYOUT_FRAMES), porque o RichTextLabel com
## autowrap só acerta a altura depois de receber a largura final. O id
## descarta a espera se o tooltip foi escondido/reaberto no meio.
func finish_layout(id: int) -> void:
	var last_size: Vector2 = Vector2(-1, -1)
	var stable_frames: int = 0

	for i in MAX_LAYOUT_FRAMES:
		await get_tree().process_frame

		if id != request_id or not visible or not is_instance_valid(target) or not target.is_inside_tree():
			return

		reposition()

		if size == last_size:
			stable_frames += 1
		else:
			stable_frames = 0

		last_size = size

		if stable_frames >= 2:
			break

	modulate.a = 1.0

func hide_tooltip() -> void:
	request_id += 1
	visible = false
	target = null

func reposition() -> void:
	var rect: Rect2 = target.get_global_transform() * Rect2(Vector2.ZERO, target.size)
	var viewport_size: Vector2 = get_viewport_rect().size
	reset_size()

	var tooltip_size: Vector2 = size
	var x: float = rect.end.x + SIDE_GAP

	if x + tooltip_size.x > viewport_size.x - SCREEN_MARGIN:
		x = rect.position.x - SIDE_GAP - tooltip_size.x

	x = maxf(SCREEN_MARGIN, x)

	var y: float = clampf(rect.position.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, viewport_size.y - tooltip_size.y - SCREEN_MARGIN))

	global_position = Vector2(x, y)
