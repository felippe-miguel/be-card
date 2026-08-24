class_name CardDatabase
extends RefCounted

var cards: Dictionary = {}

func load_cards() -> void:
	var directory = DirAccess.open("res://data/cards")
	
	if directory == null:
		print("Não consegui abrir a pasta de cartas.")
		return
	
	directory.list_dir_begin()
	
	var file_name = directory.get_next()
	
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			load_card(file_name)
		
		file_name = directory.get_next()
	
	directory.list_dir_end()

func load_card(file_name: String) -> void:
	var path = "res://data/cards/" + file_name
	var file = FileAccess.open(path, FileAccess.READ)
	
	if file == null:
		print("Não consegui abrir: ", path)
		return
	
	var json_text = file.get_as_text()
	var data = JSON.parse_string(json_text)
	
	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return
	
	var card = CardData.from_dict(data)
	
	cards[card.id] = card
	
	print("Carta carregada: ", card.id)
