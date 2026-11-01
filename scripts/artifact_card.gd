class_name ArtifactCard
extends Control

## Um artefato desenhado como carta (docs/MERCHANT_CARDS_EXECUTION_PLAN.md,
## Passos 9 e 10): mesmo tamanho e moldura do Card, mas sem custo, sem alvo e
## sem preview de invocação — no rodapé fica a marca "Artefato". Não tem
## sinal de clique: quem usa (Merchant/DeckBuilder) age pelos próprios
## botões/seletor.

## Mesmos valores do hover do Card (ver Card.HOVER_*): a carta sob o mouse
## cresce, sobe e vai pro topo da pilha enquanto o mouse estiver sobre ela.
## Cópia mínima de propósito (decisão do plano: poucas linhas, em vez de um
## helper compartilhado) — se o hover do Card mudar, conferir aqui também.
const HOVER_SCALE = 1.12
const HOVER_LIFT = 24.0
const HOVER_ANIMATION_DURATION = 0.1
const HOVERED_Z_INDEX = 100

## Mesma convenção do Card.ART_PATH_FORMAT, numa pasta própria.
const ART_PATH_FORMAT = "res://resources/images/artifacts/%s.png"

@onready var art: TextureRect = $Art
@onready var name_label: Label = $NameLabel
@onready var description_label: RichTextLabel = $DescriptionLabel

const KEYWORD_TOOLTIP_SCENE = preload("res://scenes/keyword_tooltip.tscn")

var data: ArtifactData

## Só existe se setup() receber keyword_database. Hoje nenhum artefato tem
## palavra-chave, então show_beside() não mostra nada (tooltip sem conteúdo).
var keyword_tooltip: KeywordTooltip

## Posição de repouso, definida por quem organiza o layout (o holder do
## Merchant/DeckBuilder deixa ZERO). O hover anima a partir/para ela.
var rest_position: Vector2 = Vector2.ZERO
var rest_z_index: int = 0

## Escala de repouso (1.0 = tamanho cheio). O DeckBuilder mostra o artefato
## reduzido; o hover cresce a partir dela (base_scale * HOVER_SCALE), não do
## tamanho cheio. Definir antes do primeiro hover.
var base_scale: float = 1.0

var hover_tween: Tween

func _ready() -> void:
	pivot_offset = size / 2.0

	## PASS (não o STOP padrão): a roda do mouse continua rolando o
	## ScrollContainer com o cursor sobre a carta; o hover segue funcionando.
	mouse_filter = Control.MOUSE_FILTER_PASS

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

## Só chamar depois de a carta entrar na árvore (usa os @onready).
func setup(artifact_data: ArtifactData, keyword_database: KeywordDatabase = null) -> void:
	data = artifact_data
	name_label.text = data.name

	## Destacado por KeywordText; sem glossário, só escapado ("[" na
	## descrição não vira BBCode).
	set_description_bbcode(KeywordText.to_bbcode(data.description, keyword_database))

	update_art()

	update_keyword_tooltip(keyword_database)

## Mesma ideia de Card.update_keyword_tooltip(), sem o bloco de unidade.
func update_keyword_tooltip(keyword_database: KeywordDatabase) -> void:
	if keyword_tooltip != null:
		keyword_tooltip.hide_tooltip()

	if keyword_database == null:
		return

	if keyword_tooltip == null:
		keyword_tooltip = KEYWORD_TOOLTIP_SCENE.instantiate()
		add_child(keyword_tooltip)

	keyword_tooltip.keyword_database = keyword_database

	keyword_tooltip.set_keywords(keyword_database.get_keywords(data.get_keyword_ids()))

func hide_keyword_tooltip() -> void:
	if keyword_tooltip != null:
		keyword_tooltip.hide_tooltip()

## top_level desacopla o tooltip da carta; ele nunca fica na tela se a carta
## sair da árvore (ex.: troca de artefato no DeckBuilder).
func _exit_tree() -> void:
	hide_keyword_tooltip()

## Único lugar que escreve a descrição: recebe BBCode já pronto.
func set_description_bbcode(bbcode: String) -> void:
	description_label.text = "[center]%s[/center]" % bbcode

func update_art() -> void:
	var path = ART_PATH_FORMAT % data.id

	if ResourceLoader.exists(path):
		art.texture = load(path)
		art.visible = true
	else:
		art.visible = false

func _on_mouse_entered() -> void:
	z_index = HOVERED_Z_INDEX

	animate_to(rest_position - Vector2(0, HOVER_LIFT), base_scale * HOVER_SCALE)

	if keyword_tooltip != null:
		keyword_tooltip.show_beside(self)

func _on_mouse_exited() -> void:
	hide_keyword_tooltip()

	z_index = rest_z_index

	animate_to(rest_position, base_scale)

func animate_to(target_position: Vector2, target_scale: float) -> void:
	if hover_tween != null:
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.tween_property(self, "position", target_position, HOVER_ANIMATION_DURATION)
	hover_tween.tween_property(self, "scale", Vector2(target_scale, target_scale), HOVER_ANIMATION_DURATION)
