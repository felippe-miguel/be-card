class_name MerchantData
extends RefCounted

## Estoque de um mercador de cartas (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa
## 4), vindo de data/merchants/*.json. Estoque fixo e infinito por decisão
## da versão crua: sempre as mesmas cartas, compra quantas quiser — sem
## quantidade limitada nem rotação por enquanto.

var id: String = ""

## card_id -> preço em ouro. Carta desconhecida ou preço inválido é
## descartado com aviso (mesmo espírito do DeckList/coleção inicial).
var prices: Dictionary = {}

static func from_dict(data: Dictionary, card_database: CardDatabase) -> MerchantData:
	var merchant = MerchantData.new()

	merchant.id = data.get("id", "")

	var raw_prices: Dictionary = data.get("cards", {})

	for card_id in raw_prices:
		var raw_price = raw_prices[card_id]

		if not card_database.cards.has(card_id):
			print("Mercador \"", merchant.id, "\": carta desconhecida ignorada: ", card_id)
			continue

		if not (raw_price is float or raw_price is int) or int(raw_price) < 0:
			print("Mercador \"", merchant.id, "\": preço inválido pra ", card_id, ": ", raw_price)
			continue

		merchant.prices[card_id] = int(raw_price)

	return merchant

func get_price(card_id: String) -> int:
	return prices.get(card_id, -1)
