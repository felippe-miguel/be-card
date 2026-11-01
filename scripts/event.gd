class_name Event
extends Control

## Tela de um evento (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa 7): título,
## texto e um botão por escolha. Escolher aplica os efeitos no
## CampaignState (apply_event_choice()) e troca as escolhas pelo texto do
## resultado + "Voltar". A regra do que cada escolha faz é do
## CampaignState/EventData; aqui só se reflete isso na tela. Escolha com
## batalha não mostra resultado: pede a luta a Main.

signal back_pressed

## A escolha escolhida tem um efeito "battle" — Main abre a batalha e,
## ao vencer, paga gold (ver Main._on_battle_finished()).
signal battle_requested(battle_id: String, gold: int)

const COMPLETED_TEXT = "Você já resolveu este evento."

@onready var title_label: Label = $Center/Content/TitleLabel
@onready var text_label: Label = $Center/Content/TextLabel
@onready var choices_container: VBoxContainer = $Center/Content/Choices
@onready var back_button: Button = $Center/Content/BackButton

## Recebidos de Main via setup(), antes de entrar na árvore.
var event_data: EventData
var campaign_state: CampaignState
var card_database: CardDatabase
var artifact_database: ArtifactDatabase

func setup(data: EventData, state: CampaignState, cards: CardDatabase, artifacts: ArtifactDatabase) -> void:
	event_data = data
	campaign_state = state
	card_database = cards
	artifact_database = artifacts

func _ready() -> void:
	title_label.text = event_data.name
	back_button.pressed.connect(back_pressed.emit)

	## Evento único já resolvido: só o aviso e "Voltar".
	if not event_data.repeatable and campaign_state.is_event_completed(event_data.id):
		text_label.text = COMPLETED_TEXT
		back_button.grab_focus()
		return

	text_label.text = event_data.text

	render_choices()

## Esc volta pro mapa — mesmo comportamento das outras telas de ponto.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed.emit()

func render_choices() -> void:
	var first_enabled: Button = null

	for i in range(event_data.choices.size()):
		var button = Button.new()
		var can_choose = campaign_state.can_choose_event_choice(event_data, i)

		button.text = event_data.choices[i].label + get_unavailable_hint(i)
		button.custom_minimum_size = Vector2(0, 52)
		button.disabled = not can_choose
		button.pressed.connect(_on_choice_pressed.bind(i))

		choices_container.add_child(button)

		if can_choose and first_enabled == null:
			first_enabled = button

	if first_enabled != null:
		first_enabled.grab_focus()
	else:
		back_button.grab_focus()

## Por que uma escolha está desabilitada, pro jogador não ficar sem saber.
func get_unavailable_hint(choice_index: int) -> String:
	if campaign_state.can_choose_event_choice(event_data, choice_index):
		return ""

	if not campaign_state.can_afford(event_data.get_gold_cost(choice_index)):
		return " — ouro insuficiente"

	return " — já possui"

func _on_choice_pressed(choice_index: int) -> void:
	var outcome = campaign_state.apply_event_choice(event_data, choice_index)

	if not outcome.applied:
		return

	if not outcome.battle.is_empty():
		battle_requested.emit(outcome.battle.battle_id, outcome.battle.gold)
		return

	show_result(choice_index)

## Texto do resultado escrito no evento, ou um resumo gerado dos efeitos.
func show_result(choice_index: int) -> void:
	for child in choices_container.get_children():
		child.queue_free()

	var choice = event_data.choices[choice_index]

	text_label.text = choice.result_text if choice.result_text != "" else describe_effects(choice.effects)
	back_button.grab_focus()

func describe_effects(effects: Array) -> String:
	var parts: PackedStringArray = []

	for effect in effects:
		match effect.type:
			"gold":
				parts.append(("Você ganhou %d ouro." if effect.amount >= 0 else "Você perdeu %d ouro.") % abs(effect.amount))

			"card":
				parts.append("Você recebeu %s ×%d." % [card_database.cards[effect.card_id].name, effect.count])

			"artifact":
				parts.append("Você recebeu %s." % artifact_database.artifacts[effect.artifact_id].name)

	return " ".join(parts) if not parts.is_empty() else "Nada aconteceu."
