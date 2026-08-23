class_name Enemy
extends Button

var unit: Unit

signal selected(enemy: Enemy)

func setup(enemy_unit: Unit) -> void:
	unit = enemy_unit
	unit.changed.connect(_on_unit_changed)
	update_display()

func update_display() -> void:
	var faction_name = "ALLY"

	if unit.faction == Unit.Faction.ENEMY:
		faction_name = "ENEMY"

	text = (
		unit.name
		+ "\n"
		+ faction_name
		+ "\n"
		+ "HP: "
		+ str(unit.hp)
		+ "/"
		+ str(unit.max_hp)
		+ "\n"
		+ "Floor: "
		+ str(unit.floor_index)
		+ " | Pos: "
		+ str(unit.position_index)
	)

func _pressed() -> void:
	selected.emit(self)

func _on_unit_changed() -> void:
	update_display()
