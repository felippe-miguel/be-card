class_name EventDatabase
extends RefCounted

## Todos os eventos de data/events/*.json, por id (Etapa 7). Mesmo
## padrão de carregamento de UnitDatabase/CardDatabase — o id vem do
## próprio JSON ("id"), não do nome do arquivo.

var events: Dictionary = {}

func load_events(card_database: CardDatabase, artifact_database: ArtifactDatabase) -> void:
	var directory = DirAccess.open("res://data/events")

	if directory == null:
		print("Não consegui abrir a pasta de eventos.")
		return

	directory.list_dir_begin()

	var file_name = directory.get_next()

	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			load_event(file_name, card_database, artifact_database)

		file_name = directory.get_next()

	directory.list_dir_end()

func load_event(file_name: String, card_database: CardDatabase, artifact_database: ArtifactDatabase) -> void:
	var path = "res://data/events/" + file_name
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return

	var event = EventData.from_dict(data, card_database, artifact_database)

	events[event.id] = event

	print("Evento carregado: ", event.id)
