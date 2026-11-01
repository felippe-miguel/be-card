class_name ArtifactDatabase
extends RefCounted

## Todos os artefatos de data/artifacts/*.json, por id (Etapa 6). Mesmo
## padrão de carregamento de CardDatabase/MerchantDatabase.

var artifacts: Dictionary = {}

func load_artifacts() -> void:
	var directory = DirAccess.open("res://data/artifacts")

	if directory == null:
		print("Não consegui abrir a pasta de artefatos.")
		return

	directory.list_dir_begin()

	var file_name = directory.get_next()

	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			load_artifact(file_name)

		file_name = directory.get_next()

	directory.list_dir_end()

func load_artifact(file_name: String) -> void:
	var path = "res://data/artifacts/" + file_name
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return

	var artifact = ArtifactData.from_dict(data)

	artifacts[artifact.id] = artifact

	print("Artefato carregado: ", artifact.id)
