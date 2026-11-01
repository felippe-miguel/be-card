class_name CampaignSave
extends RefCounted

## Save da campanha em disco (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa 8): um
## JSON em user:// com o CampaignState.to_dict(). Só lê/escreve o arquivo;
## o que ele contém e como reconstruir o estado é do CampaignState, e quem
## decide QUANDO salvar/carregar é Main.

const SAVE_PATH = "user://campaign_save.json"

## Grava de forma atômica (arquivo temporário + rename), pra um crash no
## meio da escrita não deixar o save pela metade. Retorna false se falhar.
static func write(state: CampaignState, path: String = SAVE_PATH) -> bool:
	var temp_path = path + ".tmp"
	var file = FileAccess.open(temp_path, FileAccess.WRITE)

	if file == null:
		push_warning("Não consegui gravar o save: %s" % temp_path)
		return false

	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	file.close()

	if DirAccess.rename_absolute(temp_path, path) != OK:
		push_warning("Não consegui finalizar o save: %s" % path)
		return false

	return true

## O conteúdo do save, ou {} se não existe, não é JSON válido ou é de uma
## versão desconhecida — nesses casos é como se não houvesse save (o
## problema só aparece como aviso no console).
static func read(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		push_warning("Não consegui abrir o save: %s" % path)
		return {}

	var data = JSON.parse_string(file.get_as_text())

	if not data is Dictionary:
		push_warning("Save corrompido, ignorado: %s" % path)
		return {}

	var version = data.get("version")

	if not (version is float or version is int) or int(version) != CampaignState.SAVE_VERSION:
		push_warning("Save de versão desconhecida (%s), ignorado: %s" % [str(version), path])
		return {}

	return data

static func exists(path: String = SAVE_PATH) -> bool:
	return not read(path).is_empty()
