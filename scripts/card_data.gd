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
