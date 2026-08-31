class_name BattleDefinition
extends RefCounted

var floors: Array[Dictionary] = []

static func from_dict(data: Dictionary) -> BattleDefinition:
	var definition = BattleDefinition.new()

	definition.floors.assign(data.get("floors", []))

	return definition

## Definição com 1 andar vazio, sem nenhuma unidade pré-definida — usada
## por quem só quer um Battlefield/BattleFloor de verdade pra popular do
## zero: BattleState.clone_for_simulation() (preview de "Rodar turno") e
## o botão de debug "Random" (Game), que sorteia a formação depois.
static func empty() -> BattleDefinition:
	var definition = BattleDefinition.new()

	definition.floors.assign([{"units": []}])

	return definition
