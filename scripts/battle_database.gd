class_name BattleDatabase
extends RefCounted

var battles: Dictionary = {}

func load_battles() -> void:
	var directory = DirAccess.open("res://data/battles")
	
	if directory == null:
		print("Não consegui abrir a pasta de batalhas.")
		return
	
	directory.list_dir_begin()
	
	var file_name = directory.get_next()
	
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			load_battle(file_name)
		
		file_name = directory.get_next()
	
	directory.list_dir_end()

func load_battle(file_name: String) -> void:
	var path = "res://data/battles/" + file_name
	var file = FileAccess.open(path, FileAccess.READ)
	
	if file == null:
		print("Não consegui abrir: ", path)
		return
	
	var json_text = file.get_as_text()
	var data = JSON.parse_string(json_text)
	
	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return
	
	var battle = BattleDefinition.from_dict(data)
	
	var battle_id = file_name.get_basename()
	
	battles[battle_id] = battle
	
	print("Batalha carregada: ", battle_id)
