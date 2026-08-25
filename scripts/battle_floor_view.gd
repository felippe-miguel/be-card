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

func connect_to_floor(battleFloor: BattleFloor) -> void:
	battleFloor.unit_added.connect(_on_unit_added)
	battleFloor.unit_removed.connect(_on_unit_removed)

func _on_unit_added(unit: Unit) -> void:
	create_unit_view(unit)

func _on_unit_removed(unit: Unit) -> void:
	var container = get_container_for_faction(unit.faction)

	for child in container.get_children():
		var unit_view = child as UnitView

		if unit_view != null and unit_view.unit == unit:
			container.remove_child(unit_view)
			unit_view.queue_free()
			break

	reorder_unit_views(unit.faction)

func create_unit_view(unit: Unit) -> void:
	var unit_view  = preload("res://scenes/unit_view.tscn").instantiate()
	var container = get_container_for_faction(unit.faction)
	
	container.add_child(unit_view)
	
	unit_view.setup(unit)
	
	unit_view.selected.connect(_on_unit_selected)
	reorder_unit_views(unit.faction)

func get_container_for_faction(faction: Unit.Faction) -> HBoxContainer:
	if faction == Unit.Faction.ENEMY:
		return enemy_container

	return ally_container

func reorder_unit_views(faction: Unit.Faction) -> void:
	var container = get_container_for_faction(faction)
	var unit_views: Array[UnitView] = []

	for child in container.get_children():
		var unit_view = child as UnitView

		if unit_view != null:
			unit_views.append(unit_view)

	unit_views.sort_custom(
		func(first: UnitView, second: UnitView) -> bool:
			if faction == Unit.Faction.ALLY:
				return first.unit.position_index > second.unit.position_index

			return first.unit.position_index < second.unit.position_index
	)

	for position in range(unit_views.size()):
		container.move_child(unit_views[position], position)

func _on_unit_selected(unit: Unit) -> void:
	unit_selected.emit(unit)
