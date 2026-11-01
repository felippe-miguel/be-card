class_name PointPlaceholder
extends Control

## Tela provisória de um ponto do overworld que ainda não tem conteúdo
## (docs/CAMPAIGN_EXECUTION_PLAN.md, Passo 1.6): mercadores e eventos. Só
## mostra o nome/tipo do ponto e volta pro mapa. Cada tipo ganha a sua tela
## de verdade na etapa correspondente (mercador de cartas na Etapa 4,
## artefatos na 6, eventos na 7) — e aí esta tela deixa de ser usada por
## aquele tipo.

signal back_pressed

@onready var title_label: Label = $Center/Content/TitleLabel
@onready var subtitle_label: Label = $Center/Content/SubtitleLabel
@onready var back_button: Button = $Center/Content/BackButton

## Recebido de Main via setup(), antes de entrar na árvore.
var point: WorldPointData

func setup(entered_point: WorldPointData) -> void:
	point = entered_point

func _ready() -> void:
	title_label.text = point.name
	subtitle_label.text = "%s — em breve" % point.get_type_name()

	back_button.pressed.connect(back_pressed.emit)
	back_button.grab_focus()

## Esc também volta pro mapa — mesmo comportamento do overworld (Esc
## sempre "sobe um nível").
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed.emit()
