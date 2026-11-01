class_name EventData
extends RefCounted

## Um evento de campanha (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa 7), vindo
## de data/events/*.json: texto + algumas escolhas, cada uma com efeitos
## simples sobre o CampaignState. Catálogo puro — sem árvore de diálogo:
## escolher aplica os efeitos e acabou. Quais eventos únicos já foram
## resolvidos é estado de campanha (CampaignState.completed_event_ids).
##
## JSON: {"id", "name", "text", "repeatable", "choices": [{"label",
## "result_text" (opcional), "effects": [...]}]}. Efeitos:
## - {"type": "gold", "amount": N} (negativo = pagar; a escolha fica
##   desabilitada sem ouro suficiente)
## - {"type": "card", "card_id": X, "count": N}
## - {"type": "artifact", "artifact_id": X} (desabilitada se já possui)
## - {"type": "battle", "battle_id": X, "gold": N} (luta; o ouro vem só
##   ao vencer — quem aplica é Main, ver Main._on_battle_finished())

const BATTLE_DIRECTORY = "res://data/battles/"

var id: String = ""
var name: String = ""
var text: String = ""

## false (padrão) = evento único: some depois da primeira escolha.
var repeatable: bool = false

## Cada item: {"label": String, "result_text": String, "effects":
## Array[Dictionary]} — efeitos já validados e normalizados (ver
## parse_effect()).
var choices: Array[Dictionary] = []

## Id desconhecido, efeito inválido ou escolha sem rótulo é descartado com
## aviso (mesmo espírito dos mercadores e do DeckList).
static func from_dict(data: Dictionary, card_database: CardDatabase, artifact_database: ArtifactDatabase) -> EventData:
	var event = EventData.new()

	event.id = data.get("id", "")
	event.name = data.get("name", "")
	event.text = data.get("text", "")
	event.repeatable = bool(data.get("repeatable", false))

	for raw_choice in data.get("choices", []):
		if not raw_choice is Dictionary or str(raw_choice.get("label", "")) == "":
			print("Evento \"", event.id, "\": escolha sem rótulo ignorada: ", raw_choice)
			continue

		var effects: Array[Dictionary] = []

		for raw_effect in raw_choice.get("effects", []):
			var effect = parse_effect(raw_effect, event.id, card_database, artifact_database)

			if not effect.is_empty():
				effects.append(effect)

		event.choices.append({
			"label": str(raw_choice["label"]),
			"result_text": str(raw_choice.get("result_text", "")),
			"effects": effects,
		})

	return event

## Efeito normalizado (números como int) ou {} se inválido.
static func parse_effect(raw_effect, event_id: String, card_database: CardDatabase, artifact_database: ArtifactDatabase) -> Dictionary:
	if not raw_effect is Dictionary:
		print("Evento \"", event_id, "\": efeito inválido ignorado: ", raw_effect)
		return {}

	var type = raw_effect.get("type", "")

	match type:
		"gold":
			if is_number(raw_effect.get("amount")):
				return {"type": "gold", "amount": int(raw_effect["amount"])}

		"card":
			var count = raw_effect.get("count", 1)

			if card_database.cards.has(raw_effect.get("card_id", "")) and is_number(count) and int(count) >= 1:
				return {"type": "card", "card_id": raw_effect["card_id"], "count": int(count)}

		"artifact":
			if artifact_database.artifacts.has(raw_effect.get("artifact_id", "")):
				return {"type": "artifact", "artifact_id": raw_effect["artifact_id"]}

		"battle":
			var battle_id = raw_effect.get("battle_id", "")
			var gold = raw_effect.get("gold", 0)

			if battle_id is String and FileAccess.file_exists(BATTLE_DIRECTORY + battle_id + ".json") and is_number(gold) and int(gold) >= 0:
				return {"type": "battle", "battle_id": battle_id, "gold": int(gold)}

	print("Evento \"", event_id, "\": efeito inválido ou com id desconhecido ignorado: ", raw_effect)

	return {}

## JSON sempre devolve número como float — int() só depois desta checagem.
static func is_number(value) -> bool:
	return value is float or value is int

## Ouro que a escolha cobra (soma dos efeitos de ouro negativos), >= 0.
func get_gold_cost(choice_index: int) -> int:
	var cost = 0

	for effect in choices[choice_index].effects:
		if effect.type == "gold" and effect.amount < 0:
			cost -= effect.amount

	return cost

func get_artifact_ids(choice_index: int) -> Array[String]:
	var result: Array[String] = []

	for effect in choices[choice_index].effects:
		if effect.type == "artifact":
			result.append(effect.artifact_id)

	return result

## O efeito de batalha da escolha, ou {} se ela não luta.
func get_battle_effect(choice_index: int) -> Dictionary:
	for effect in choices[choice_index].effects:
		if effect.type == "battle":
			return effect

	return {}
