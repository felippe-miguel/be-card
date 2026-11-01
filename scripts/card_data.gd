class_name CardData
extends RefCounted

var id: String
var name: String
var description: String
var cost: int
var type: String
var effects: Array[Dictionary] = []

static func from_dict(data: Dictionary) -> CardData:
	var card = CardData.new()
	
	card.id = data.get("id", "")
	card.name = data.get("name", "")
	card.description = data.get("description", "")
	card.cost = data.get("cost", 0)
	card.type = data.get("type", "")
	card.effects.assign(data.get("effects", []))

	return card

## Instância nova com os mesmos dados. Um deck com várias cópias da mesma
## carta (DeckList — Etapa 3) precisa de uma instância por cópia: a mão
## (Game.render_hand()) e o Deck (hand.erase() etc.) usam a referência do
## CardData como identidade, e duas cópias compartilhando a mesma instância
## seriam tratadas como uma carta só.
func copy() -> CardData:
	var card = CardData.new()

	card.id = id
	card.name = name
	card.description = description
	card.cost = cost
	card.type = type
	card.effects = effects.duplicate(true)

	return card

## Descrição legível dos alvos desta carta, derivada de effects. Usada pela
## visual Card para mostrar o alvo sem precisar olhar o console.
func get_target_description() -> String:
	var descriptions: PackedStringArray = []

	for effect in effects:
		var target_description = describe_effect_target(effect)

		if target_description != "" and not descriptions.has(target_description):
			descriptions.append(target_description)

	if descriptions.is_empty():
		return "-"

	return ", ".join(descriptions)

func describe_effect_target(effect: Dictionary) -> String:
	var target: String = effect.get("target", "")
	var target_faction: String = effect.get("target_faction", "")

	match target:
		"selected_unit":
			match target_faction:
				"ally":
					return "unidade aliada"
				"enemy":
					return "unidade inimiga"
				_:
					return "unidade"

		"selected_floor":
			return "andar"

		"selected_position":
			return "célula do grid"

		"all_enemies":
			return "todos os inimigos"

		"all_allies":
			return "todos os aliados"

		"":
			## Cartas do sandbox 3x3 (reposicionamento/buff — ver
			## docs/playtest_3x3.md seção 5) não usam o vocabulário de
			## "target" acima: o alvo é derivado do próprio efeito.
			return describe_action_type(effect.get("type", ""))

		_:
			return ""

func describe_action_type(effect_type: String) -> String:
	match effect_type:
		"reposition", "teleport":
			return "unidade selecionada + célula"

		"flank":
			return "unidade selecionada + lane vizinha"

		"advance", "retreat":
			return "unidade selecionada"

		"swap":
			return "duas unidades aliadas"

		"frontline":
			return "aliados na Front"

		"concentration":
			return "lane escolhida"

		_:
			return ""

## Id da UnitData invocada por esta carta ("" se não for uma carta de
## invocação). Só o id — resolver a UnitData em si é responsabilidade de
## quem tem acesso ao UnitDatabase (ver Card.update_summon_preview()).
func get_summon_unit_id() -> String:
	for effect in effects:
		if effect.get("type", "") == "summon":
			return effect.get("unit", "")

	return ""

## Texto que a carta mostra. Carta de invocação com description vazia usa a
## da unidade invocada: os efeitos da unidade ficam escritos num lugar só
## (data/units/) e aparecem na carta, sem repetir "invoca X numa célula
## vazia" em toda carta. Uma carta de invocação com regra própria ainda pode
## escrever a sua description, que tem prioridade.
func get_display_description(unit_database: UnitDatabase = null) -> String:
	if description != "" or unit_database == null:
		return description

	var unit_data: UnitData = unit_database.units.get(get_summon_unit_id())

	return unit_data.description if unit_data != null else ""

## Palavras-chave (glossário — docs/MERCHANT_CARDS_EXECUTION_PLAN.md Passo 3)
## que um efeito referencia, derivadas dos dados do efeito e nunca do texto
## da descrição. static pra ser reaproveitado pelo efeito da carta, pelo
## efeito de cada trigger de unidade e por ArtifactData.get_keyword_ids().
## Efeito sem mecânica do glossário (damage, heal, summon...) devolve [].
static func keywords_of_effect(effect: Dictionary) -> Array[String]:
	var result: Array[String] = []

	match effect.get("type", ""):
		"apply_status", "remove_status", "double_status":
			var status_id: String = effect.get("status", "")

			if status_id != "":
				result.append(status_id)

		"detonate_poison":
			result.append("poison")

		"block", "shield_bash":
			result.append("block")

		"cleanse":
			result.append("cleanse")

	return result

## Ids de palavra-chave que esta carta usa, sem repetição e na ordem da
## primeira aparição. Para "summon", se unit_database vier, inclui também o
## que a unidade invocada traz: initial_statuses e, por trigger, o id do
## evento seguido das palavras-chave do efeito dele. Sem unit_database, só
## os efeitos da própria carta.
func get_keyword_ids(unit_database: UnitDatabase = null) -> Array[String]:
	var result: Array[String] = []

	for effect in effects:
		_add_keyword_ids(result, keywords_of_effect(effect))

		if effect.get("type", "") != "summon" or unit_database == null:
			continue

		var unit_data: UnitData = unit_database.units.get(effect.get("unit", ""))

		if unit_data == null:
			continue

		for status_id in unit_data.initial_statuses:
			_add_keyword_ids(result, [str(status_id)])

		for trigger in unit_data.triggers:
			var event_id: String = trigger.get("event", "")

			if event_id != "":
				_add_keyword_ids(result, [event_id])

			_add_keyword_ids(result, keywords_of_effect(trigger.get("effect", {})))

	return result

static func _add_keyword_ids(result: Array[String], ids: Array) -> void:
	for keyword_id in ids:
		if not result.has(keyword_id):
			result.append(keyword_id)
