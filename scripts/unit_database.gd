class_name UnitDatabase
extends RefCounted


var units: Dictionary = {}


func load_units() -> void:
	var directory = DirAccess.open("res://data/units")

	if directory == null:
		print("Não consegui abrir a pasta de unidades.")
		return

	directory.list_dir_begin()

	var file_name = directory.get_next()

	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			load_unit(file_name)

		file_name = directory.get_next()

	directory.list_dir_end()


func load_unit(file_name: String) -> void:
	var path = "res://data/units/" + file_name

	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return

	var json_text = file.get_as_text()
	var data = JSON.parse_string(json_text)

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return

	var unit_data = UnitData.from_dict(data)

	units[unit_data.id] = unit_data

	print("Unidade carregada: ", unit_data.id)
