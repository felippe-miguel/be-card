class_name ArtifactData
extends RefCounted

## Um artefato (docs/CAMPAIGN_EXECUTION_PLAN.md, Etapa 6), vindo de
## data/artifacts/*.json: efeito passivo que vale em todo combate do deck
## que o equipa (1 artefato por deck — decisão do usuário). Catálogo puro;
## quais artefatos o jogador possui fica no CampaignState, e qual deck
## equipa qual fica no DeckList.

## Tipos de efeito conhecidos — cada um mapeia pra algo que a batalha já
## sabe fazer (ver Game.get_artifact_bonus()), em vez de um sistema novo:
## - max_mana: soma em Mana.max_mana.
## - hand_size: soma nas cartas compradas por turno (e na mão inicial).
## - ally_max_hp / ally_attack: soma no HP máximo / ATK de toda unidade
##   aliada criada na batalha (ver BattleState.create_unit()).
const EFFECT_TYPES = ["max_mana", "hand_size", "ally_max_hp", "ally_attack"]

var id: String = ""
var name: String = ""
var description: String = ""
var effect_type: String = ""
var amount: int = 0

static func from_dict(data: Dictionary) -> ArtifactData:
	var artifact = ArtifactData.new()
	var effect: Dictionary = data.get("effect", {})

	artifact.id = data.get("id", "")
	artifact.name = data.get("name", "")
	artifact.description = data.get("description", "")
	artifact.effect_type = effect.get("type", "")
	artifact.amount = int(effect.get("amount", 0))

	if not EFFECT_TYPES.has(artifact.effect_type):
		print("Artefato \"", artifact.id, "\": efeito desconhecido: ", artifact.effect_type)

	return artifact

## Quanto este artefato soma num efeito específico — 0 se o efeito for
## outro. Assim quem aplica (Game) só pergunta "quanto de max_mana?" sem
## precisar saber qual artefato está equipado.
func get_bonus(type: String) -> int:
	return amount if effect_type == type else 0
