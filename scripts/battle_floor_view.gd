class_name BattleFloorView
extends PanelContainer

@onready var enemy_container: HBoxContainer = $HBoxContainer/EnemyContainer
@onready var ally_container: HBoxContainer = $HBoxContainer/AllyContainer

var floor_index: int

signal selected(floor_view: BattleFloorView)
signal unit_selected(unit: Unit)

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
	create_unit_view(unit)

func _on_unit_removed(unit: Unit) -> void:
	print(
		"Unidade removida do andar: ",
		unit.name
	)

func create_unit_view(unit: Unit) -> void:
	var unit_view  = preload(
        "res://scenes/unit_view.tscn"
	).instantiate()

	var container: HBoxContainer

	if unit.faction == Unit.Faction.ENEMY:
		container = enemy_container
	else:
		container = ally_container

	container.add_child(unit_view)
	
	if unit.faction == Unit.Faction.ALLY:
		container.move_child(unit_view, 0)

	unit_view.setup(unit)

	unit_view.selected.connect(
		_on_unit_selected
	)

func _on_unit_selected(unit: Unit) -> void:
	unit_selected.emit(unit)
