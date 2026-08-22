extends Control

func _ready():
	var database = CardDatabase.new()

	database.load_cards()

	print("")
	print("=== CARTAS ===")

	for card_id in database.cards:
		var card = database.cards[card_id]

		print(
			card.id,
			" | ",
			card.name,
			" | custo: ",
			card.cost
		)
