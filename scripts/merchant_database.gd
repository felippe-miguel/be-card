class_name MerchantDatabase
extends RefCounted

## Todos os mercadores de data/merchants/*.json, por id (Etapas 4 e 6). Mesmo
## padrão de carregamento de UnitDatabase/CardDatabase — o id vem do
## próprio JSON ("id"), não do nome do arquivo.

var merchants: Dictionary = {}

func load_merchants(card_database: CardDatabase, artifact_database: ArtifactDatabase) -> void:
	var directory = DirAccess.open("res://data/merchants")

	if directory == null:
		print("Não consegui abrir a pasta de mercadores.")
		return

	directory.list_dir_begin()

	var file_name = directory.get_next()

	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			load_merchant(file_name, card_database, artifact_database)

		file_name = directory.get_next()

	directory.list_dir_end()

func load_merchant(file_name: String, card_database: CardDatabase, artifact_database: ArtifactDatabase) -> void:
	var path = "res://data/merchants/" + file_name
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return

	var merchant = MerchantData.from_dict(data, card_database, artifact_database)

	merchants[merchant.id] = merchant

	print("Mercador carregado: ", merchant.id)
