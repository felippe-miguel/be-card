class_name Card
extends Control

@onready var name_label: Label = $NameLabel
@onready var description_label: Label = $DescriptionLabel
@onready var cost_label: Label = $CostLabel

var data: CardData

signal played(card: Card)

func setup(card_data: CardData) -> void:
	data = card_data
	name_label.text = data.name
	description_label.text = data.description
	cost_label.text = str(data.cost)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			played.emit(self)
