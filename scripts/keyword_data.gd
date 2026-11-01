class_name KeywordData
extends RefCounted

## Uma palavra-chave do glossário (docs/MERCHANT_CARDS_EXECUTION_PLAN.md,
## Passo 3), vinda de data/keywords/*.json: nome exibido (em inglês),
## explicação (em português), apelidos opcionais e cor de destaque.
## Catálogo puro — saber QUAIS palavras-chave uma carta usa é papel de
## CardData.get_keyword_ids(); desenhar tooltip/BBCode fica na apresentação.

var id: String = ""
var name: String = ""

## Outras formas que também recebem destaque no texto (ex.: flexões em
## português). Vazio na maioria.
var aliases: Array[String] = []

## has_color = false quando o JSON não traz "color" (ou traz um valor
## inválido): a palavra-chave tem tooltip, mas não é pintada no texto.
var color: Color = Color.WHITE
var has_color: bool = false

var description: String = ""

static func from_dict(data: Dictionary) -> KeywordData:
	var keyword = KeywordData.new()

	keyword.id = data.get("id", "")
	keyword.name = data.get("name", "")
	keyword.description = data.get("description", "")
	keyword.aliases.assign(data.get("aliases", []))

	var color_text: String = str(data.get("color", ""))

	if color_text != "":
		if Color.html_is_valid(color_text):
			keyword.color = Color.html(color_text)
			keyword.has_color = true
		else:
			push_warning("Palavra-chave \"%s\": cor inválida: %s" % [keyword.id, color_text])

	return keyword
