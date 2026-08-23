class_name Enemy
extends Button

var unit: Unit

signal selected(enemy: Enemy)

func setup(enemy_unit: Unit) -> void:
	unit = enemy_unit
	update_display()

func update_display() -> void:
	text = (
		unit.name
		+ "\n"
		+ "HP: "
		+ str(unit.hp)
		+ "/"
		+ str(unit.max_hp)
	)

func _pressed() -> void:
	selected.emit(self)
