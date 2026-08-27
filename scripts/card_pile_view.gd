class_name CardPileView
extends Control

## Representa visualmente uma pilha de cartas (baralho ou descarte) como
## uma contagem, sem distinguir cartas individuais.

@onready var title_label: Label = $TitleLabel
@onready var count_label: Label = $CountLabel

func setup(title: String) -> void:
	title_label.text = title

func set_count(count: int) -> void:
	count_label.text = str(count)
