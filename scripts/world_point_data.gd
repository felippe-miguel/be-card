class_name WorldPointData
extends RefCounted

## Um ponto de interesse do overworld (docs/CAMPAIGN_EXECUTION_PLAN.md,
## Passo 1.2) — só a definição estática, vinda de data/world/*.json. O que
## o jogador já fez neste ponto (visitado, combate vencido) é estado de
## campanha, não mora aqui.

## Nome legível de cada tipo de ponto — usado no rótulo do botão no mapa e
## no título da tela do ponto. Mesmo espírito de CardData.
## describe_effect_target(): texto derivado do dado, sem precisar de
## tradução separada por enquanto.
const TYPE_NAMES = {
	"camp": "Acampamento",
	"combat": "Combate",
	"card_merchant": "Mercador de cartas",
	"artifact_merchant": "Mercador de artefatos",
	"event": "Evento",
}

var id: String
var name: String

## Um dos ids de TYPE_NAMES. "camp" é neutro (nada pra entrar); os demais
## têm algo pra entrar — combate (Passo 1.4), mercadores (Etapas 4 e 6) e
## eventos (Etapa 7). Mercador/evento sem dado definido abre o placeholder.
var type: String = ""

## Posição em pixels de tela, relativa ao canto superior esquerdo do
## overworld. Simples de propósito: o mapa cru não tem câmera nem scroll.
var position: Vector2 = Vector2.ZERO

## Só pra type "combat" (Passo 1.4): id de data/battles/*.json, a batalha
## iniciada ao entrar neste ponto. "" pros demais tipos.
var battle_id: String = ""

## Só pra type "combat" (Etapa 4): ouro ganho ao vencer este combate pela
## primeira vez — refazer dá menos (ver CampaignState.
## record_current_combat_result()).
var gold_reward: int = 0

## Só pra type "card_merchant"/"artifact_merchant" (Etapas 4 e 6): id de
## data/merchants/*.json, o estoque deste mercador. "" = sem estoque
## definido (abre o placeholder).
var merchant_id: String = ""

## Só pra type "event" (Etapa 7): id de data/events/*.json. "" = sem evento
## definido (abre o placeholder).
var event_id: String = ""

static func from_dict(data: Dictionary) -> WorldPointData:
	var point = WorldPointData.new()

	point.id = data.get("id", "")
	point.name = data.get("name", "")
	point.type = data.get("type", "")
	point.battle_id = data.get("battle", "")
	point.gold_reward = int(data.get("gold", 0))
	point.merchant_id = data.get("merchant", "")
	point.event_id = data.get("event", "")

	var raw_position: Array = data.get("position", [0, 0])

	if raw_position.size() >= 2:
		point.position = Vector2(raw_position[0], raw_position[1])

	return point

## Pontos em que "entrar" faz algo: combate com batalha definida, ou
## qualquer mercador/evento.
func can_enter() -> bool:
	match type:
		"combat":
			return battle_id != ""

		"card_merchant", "artifact_merchant", "event":
			return true

		_:
			return false

func get_type_name() -> String:
	return TYPE_NAMES.get(type, type)
