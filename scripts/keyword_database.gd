class_name KeywordDatabase
extends RefCounted

var keywords: Dictionary = {}

func load_keywords() -> void:
	var directory = DirAccess.open("res://data/keywords")

	if directory == null:
		print("Não consegui abrir a pasta de palavras-chave.")
		return

	directory.list_dir_begin()

	var file_name = directory.get_next()

	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			load_keyword(file_name)

		file_name = directory.get_next()

	directory.list_dir_end()

func load_keyword(file_name: String) -> void:
	var path = "res://data/keywords/" + file_name
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return

	var json_text = file.get_as_text()
	var data = JSON.parse_string(json_text)

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return

	var keyword = KeywordData.from_dict(data)

	keywords[keyword.id] = keyword

	print("Palavra-chave carregada: ", keyword.id)

## Resolve ids na ordem recebida. Id sem entrada no glossário é ignorado em
## silêncio: a derivação (CardData.get_keyword_ids()) fica tolerante a
## conteúdo novo que ainda não ganhou explicação.
func get_keywords(ids: Array[String]) -> Array[KeywordData]:
	var result: Array[KeywordData] = []

	for keyword_id in ids:
		if keywords.has(keyword_id):
			result.append(keywords[keyword_id])

	return result
