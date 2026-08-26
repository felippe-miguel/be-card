class_name UnitView
extends Button

var unit: Unit

signal selected(unit: Unit)

func setup(setup_unit: Unit) -> void:
	unit = setup_unit
	unit.changed.connect(_on_unit_changed)
	update_display()

func update_display() -> void:
	var faction_name = Unit.Faction.keys()[unit.faction]

	text = (
		unit.name + "\n"
		+ faction_name + "\n"
		+ "HP: " + str(unit.hp) + "/" + str(unit.max_hp) + "\n"
		+ "ATK: " + str(unit.attack) + "\n"
		+ "Block: " + str(unit.block) + "\n"
		+ "Floor: " + str(unit.floor_index) + " | Pos: " + str(unit.position_index)
	)

func _pressed() -> void:
	selected.emit(unit)

func _on_unit_changed() -> void:
	update_display()
