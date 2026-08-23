class_name BattleFloorView
extends PanelContainer

@onready var unit_container: HBoxContainer = $HBoxContainer

var floor_index: int

signal selected(floor_view: BattleFloorView)

func setup(index: int) -> void:
	floor_index = index

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			selected.emit(self)
