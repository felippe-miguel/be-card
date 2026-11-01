class_name DeckList
extends RefCounted

## Um deck montado pelo jogador fora do combate (docs/CAMPAIGN_EXECUTION_
## PLAN.md, Etapa 3): nome + quais cartas (e quantas cópias) ele leva pra
## batalha. Não confundir com Deck, que é o embaralhamento DENTRO de um
## combate (compra/mão/descarte) — o Deck de uma batalha nasce a partir de
## um DeckList (ver Game.setup_deck_and_mana()).
##
## Guarda só ids, igual ao CampaignState, pra serializar direto num save.

var name: String = ""

## Artefato equipado neste deck (Etapa 6) — no máximo 1 por deck, por
## decisão do usuário (por isso um campo só, não uma lista). "" = nenhum.
## Precisa ser um artefato que o jogador possui (ver CampaignState.
## is_deck_valid()).
var artifact_id: String = ""

## card_id -> cópias no deck (sempre >= 1). Mesmo formato da coleção do
## CampaignState, pra comparar uma com a outra direto (ver
## CampaignState.is_deck_valid()).
var cards: Dictionary = {}

## Mesmo formato do JSON da coleção inicial: {"name": ..., "artifact":
## "<artifact_id>" (opcional), "cards": {"<card_id>": <cópias>}}. Ids/
## quantidades inválidos são descartados com aviso, igual a
## CampaignState.load_starting_collection().
static func from_dict(data: Dictionary, card_database: CardDatabase, artifact_database: ArtifactDatabase) -> DeckList:
	var deck_list = DeckList.new()

	deck_list.name = data.get("name", "")

	var raw_artifact: String = data.get("artifact", "")

	if raw_artifact != "" and not artifact_database.artifacts.has(raw_artifact):
		push_warning("Deck \"%s\": artefato desconhecido ignorado: %s" % [deck_list.name, raw_artifact])
	else:
		deck_list.artifact_id = raw_artifact

	var raw_cards: Dictionary = data.get("cards", {})

	for card_id in raw_cards:
		var raw_copies = raw_cards[card_id]

		if not card_database.cards.has(card_id):
			push_warning("Deck \"%s\": carta desconhecida ignorada: %s" % [deck_list.name, card_id])
			continue

		if not (raw_copies is float or raw_copies is int) or int(raw_copies) < 1:
			push_warning("Deck \"%s\": quantidade inválida pra %s: %s" % [deck_list.name, card_id, raw_copies])
			continue

		deck_list.cards[card_id] = int(raw_copies)

	return deck_list

## Inverso de from_dict() — o formato do save (Etapa 8). O artefato só
## entra se houver um equipado.
func to_dict() -> Dictionary:
	var data: Dictionary = {"name": name, "cards": cards.duplicate()}

	if artifact_id != "":
		data["artifact"] = artifact_id

	return data

## Cópia independente — cada campanha nova recebe as suas a partir dos
## decks iniciais de Main, e editar um deck (Etapa 5) nunca pode alterar
## os dados de partida.
func duplicate_list() -> DeckList:
	var copy = DeckList.new()

	copy.name = name
	copy.artifact_id = artifact_id
	copy.cards = cards.duplicate()

	return copy

func get_copies(card_id: String) -> int:
	return cards.get(card_id, 0)

## Edição no DeckBuilder (Etapa 5). DeckList não conhece a coleção — quem
## chama (DeckBuilder) é que impede passar das cópias possuídas; a regra
## final continua sendo CampaignState.is_deck_valid() ao salvar.
func add_copy(card_id: String) -> void:
	cards[card_id] = get_copies(card_id) + 1

## Chegando a zero, a entrada sai do dicionário — mantém o invariante
## "cópias sempre >= 1" que o resto do código assume.
func remove_copy(card_id: String) -> void:
	var copies = get_copies(card_id) - 1

	if copies <= 0:
		cards.erase(card_id)
	else:
		cards[card_id] = copies

func get_total_card_count() -> int:
	var total = 0

	for card_id in cards:
		total += cards[card_id]

	return total

## Lista plana com um id por CÓPIA (ex: strike ×3 → três "strike") — o que
## a batalha precisa pra montar o Deck do combate.
func get_card_ids() -> Array[String]:
	var result: Array[String] = []

	for card_id in cards:
		for i in range(cards[card_id]):
			result.append(card_id)

	return result
