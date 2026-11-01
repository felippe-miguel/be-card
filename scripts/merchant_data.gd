class_name MerchantData
extends RefCounted

## Estoque de um mercador (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapas 4 e 6),
## vindo de data/merchants/*.json: {"id": ..., "cards": {"<card_id>":
## <preço>}, "artifacts": {"<artifact_id>": <preço>}} — as duas seções são
## opcionais (Feira da Vila só vende cartas, Mascate Errante só artefatos).
## Estoque fixo e infinito por decisão da versão crua: cartas compra quantas
## quiser; artefato só se compra uma vez porque o jogador só pode possuir um
## de cada (ver CampaignState.buy_artifact()).

var id: String = ""

## card_id -> preço em ouro.
var card_prices: Dictionary = {}

## artifact_id -> preço em ouro.
var artifact_prices: Dictionary = {}

## Id desconhecido ou preço inválido é descartado com aviso (mesmo espírito
## do DeckList/coleção inicial).
static func from_dict(data: Dictionary, card_database: CardDatabase, artifact_database: ArtifactDatabase) -> MerchantData:
	var merchant = MerchantData.new()

	merchant.id = data.get("id", "")
	merchant.card_prices = parse_prices(data.get("cards", {}), card_database.cards, merchant.id)
	merchant.artifact_prices = parse_prices(data.get("artifacts", {}), artifact_database.artifacts, merchant.id)

	return merchant

## catalog: o dicionário id -> dado do catálogo correspondente, só pra
## checar se o id existe.
static func parse_prices(raw_prices: Dictionary, catalog: Dictionary, merchant_id: String) -> Dictionary:
	var result: Dictionary = {}

	for item_id in raw_prices:
		var raw_price = raw_prices[item_id]

		if not catalog.has(item_id):
			print("Mercador \"", merchant_id, "\": item desconhecido ignorado: ", item_id)
			continue

		if not (raw_price is float or raw_price is int) or int(raw_price) < 0:
			print("Mercador \"", merchant_id, "\": preço inválido pra ", item_id, ": ", raw_price)
			continue

		result[item_id] = int(raw_price)

	return result

func get_card_price(card_id: String) -> int:
	return card_prices.get(card_id, -1)

func get_artifact_price(artifact_id: String) -> int:
	return artifact_prices.get(artifact_id, -1)
