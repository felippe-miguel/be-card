class_name MainMenu
extends Control

## Menu principal (docs/CAMPAIGN_EXECUTION_PLAN.md, Passo 1.1). Só emite
## sinais — quem decide o que "Jogar"/"Sair" fazem é Main.

signal play_pressed
signal quit_pressed

@onready var play_button: Button = $Center/Buttons/PlayButton
@onready var quit_button: Button = $Center/Buttons/QuitButton

func _ready() -> void:
	play_button.pressed.connect(play_pressed.emit)
	quit_button.pressed.connect(quit_pressed.emit)

	play_button.grab_focus()
