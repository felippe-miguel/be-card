class_name BattleFloorView
extends PanelContainer

@onready var unit_container: HBoxContainer = $HBoxContainer

var floor_index: int

signal selected(floor_view: BattleFloorView)
signal enemy_selected(enemy: Enemy)

func setup(index: int) -> void:
	floor_index = index

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			selected.emit(self)

func connect_to_floor(floor: BattleFloor) -> void:
	floor.unit_added.connect(_on_unit_added)
	floor.unit_removed.connect(_on_unit_removed)

func _on_unit_added(unit: Unit) -> void:
	create_enemy_view(unit)

func _on_unit_removed(unit: Unit) -> void:
	print(
		"Unidade removida do andar: ",
		unit.name
	)

func create_enemy_view(unit: Unit) -> void:
	var enemy = preload(
        "res://scenes/enemy.tscn"
	).instantiate()

	unit_container.add_child(enemy)

	enemy.setup(unit)

	enemy.selected.connect(
		_on_enemy_selected
	)

func _on_enemy_selected(enemy: Enemy) -> void:
	enemy_selected.emit(enemy)
