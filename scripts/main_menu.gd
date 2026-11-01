class_name MainMenu
extends Control

## Menu principal (docs/CAMPAIGN_EXECUTION_PLAN.md, Passo 1.1 e Etapa 8). Só
## emite sinais — quem decide o que "Continuar"/"Nova campanha"/"Sair" fazem
## é Main. "Continuar" só aparece quando há um save válido; "Nova campanha"
## com um save existente pede confirmação antes de sobrescrevê-lo.

signal continue_pressed
signal new_campaign_pressed
signal quit_pressed

const OVERWRITE_CONFIRM_TEXT = "Já existe uma campanha salva. Começar uma nova vai apagá-la. Continuar?"

@onready var continue_button: Button = $Center/Buttons/ContinueButton
@onready var new_campaign_button: Button = $Center/Buttons/NewCampaignButton
@onready var quit_button: Button = $Center/Buttons/QuitButton

## Recebido de Main via setup(), antes de entrar na árvore.
var has_save: bool = false

func setup(save_exists: bool) -> void:
	has_save = save_exists

func _ready() -> void:
	continue_button.visible = has_save

	continue_button.pressed.connect(continue_pressed.emit)
	new_campaign_button.pressed.connect(_on_new_campaign_button_pressed)
	quit_button.pressed.connect(quit_pressed.emit)

	if has_save:
		continue_button.grab_focus()
	else:
		new_campaign_button.grab_focus()

func _on_new_campaign_button_pressed() -> void:
	if not has_save:
		new_campaign_pressed.emit()
		return

	var dialog = ConfirmationDialog.new()

	dialog.dialog_text = OVERWRITE_CONFIRM_TEXT
	dialog.ok_button_text = "Nova campanha"
	dialog.cancel_button_text = "Cancelar"
	dialog.confirmed.connect(new_campaign_pressed.emit)
	dialog.canceled.connect(dialog.queue_free)

	add_child(dialog)
	dialog.popup_centered()
