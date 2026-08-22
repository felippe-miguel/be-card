extends Control

@onready var card_container: HBoxContainer = $HBoxContainer

var card_database: CardDatabase

func _ready():
	card_database = CardDatabase.new()
	card_database.load_cards()

	for card_id in card_database.cards:
		var card_data = card_database.cards[card_id]
		var card = preload("res://scenes/card.tscn").instantiate()

		card_container.add_child(card)
		card.setup(card_data)
		card.played.connect(_on_card_played)

func _on_card_played(card: Card) -> void:
	print("Carta jogada: ", card.data.name)
