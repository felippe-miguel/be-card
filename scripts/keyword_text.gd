class_name KeywordText
extends RefCounted

## Destaque de palavras-chave em texto de descrição (docs/MERCHANT_CARDS_
## EXECUTION_PLAN.md, Passo 7): converte texto puro em BBCode, pintando em
## negrito e na cor do glossário cada termo (nome ou apelido) de uma
## KeywordData com cor. Camada de apresentação, estática — carta, artefato
## e tooltip chamam o mesmo helper.

## Chave do metadado onde o regex compilado fica guardado no próprio
## KeywordDatabase (compila uma vez por glossário, não por carta; e some
## junto com ele, sem cache global que sobreviva a um glossário recarregado).
const CACHE_META = "keyword_text_cache"

## "[" literal vira "[lb]": conteúdo (ex.: "[x]") nunca vira BBCode sem querer.
static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")

## Texto puro -> BBCode. Sem glossário (ou sem nenhuma palavra-chave com
## cor), só escapa.
##
## Uma única varredura sobre o texto ORIGINAL com um regex de alternância:
## os trechos entre os casamentos são escapados e cada casamento é embrulhado
## em [b][color=#hex]…[/color][/b]. Como nada é re-escaneado, o BBCode
## inserido nunca casa de novo com outra palavra-chave.
##
## - Sem diferenciar maiúsculas; fronteira de palavra com (?<!\p{L}) e
##   (?!\p{L}), porque \b falha com letras acentuadas ("Poisoné" e "Blocker"
##   não casam).
## - Termos mais longos primeiro, pra "On Card Played" vencer qualquer termo
##   mais curto que o contenha.
## - O número logo DEPOIS do termo entra no destaque ("Poison 3"). Número
##   antes ("12 de Block", "+2 ATK") fica de fora: só o termo é pintado.
static func to_bbcode(text: String, keyword_database: KeywordDatabase) -> String:
	var compiled: Dictionary = get_compiled(keyword_database)

	if compiled.is_empty():
		return escape_bbcode(text)

	var regex: RegEx = compiled["regex"]
	var colors: Dictionary = compiled["colors"]
	var result: String = ""
	var cursor: int = 0

	for match in regex.search_all(text):
		var start: int = match.get_start()

		result += escape_bbcode(text.substr(cursor, start - cursor))

		var color: Color = colors[match.get_string("term").to_lower()]

		result += "[b][color=#%s]%s[/color][/b]" % [color.to_html(false), escape_bbcode(match.get_string())]

		cursor = match.get_end()

	return result + escape_bbcode(text.substr(cursor))

## {"regex": RegEx, "colors": {termo em minúsculas: Color}}, ou {} se não há
## nada a destacar. Recompila se o número de palavras-chave mudou.
static func get_compiled(keyword_database: KeywordDatabase) -> Dictionary:
	if keyword_database == null:
		return {}

	## has_meta() antes: get_meta() com default null loga erro quando a
	## chave ainda não existe (null conta como "sem default").
	if keyword_database.has_meta(CACHE_META):
		var cached: Dictionary = keyword_database.get_meta(CACHE_META)

		if cached["count"] == keyword_database.keywords.size():
			return cached["data"]

	var colors: Dictionary = {}

	for keyword in keyword_database.keywords.values():
		if not keyword.has_color:
			continue

		for term in [keyword.name] + keyword.aliases:
			if term != "":
				colors[term.to_lower()] = keyword.color

	var data: Dictionary = {}

	if not colors.is_empty():
		var terms: Array = colors.keys()

		terms.sort_custom(func(a: String, b: String): return a.length() > b.length())

		var escaped_terms: Array[String] = []

		for term in terms:
			escaped_terms.append(escape_regex(term))

		var regex = RegEx.new()
		var error = regex.compile(r"(?i)(?<!\p{L})(?<term>%s)(?!\p{L})(?: \d+)?" % "|".join(escaped_terms))

		if error == OK:
			data = {"regex": regex, "colors": colors}
		else:
			push_warning("KeywordText: regex inválido para o glossário.")

	keyword_database.set_meta(CACHE_META, {"count": keyword_database.keywords.size(), "data": data})

	return data

static func escape_regex(term: String) -> String:
	var result: String = ""

	for character in term:
		if r"\^$.|?*+()[]{}-/ ".contains(character):
			result += "\\" + character
		else:
			result += character

	return result
