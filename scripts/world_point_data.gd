class_name WorldPointData
extends RefCounted

## Um ponto de interesse do overworld (docs/CAMPAIGN_EXECUTION_PLAN.md,
## Passo 1.2) — só a definição estática, vinda de data/world/*.json. O que
## o jogador já fez neste ponto (visitado, combate vencido) é estado de
## campanha, não mora aqui.

var id: String
var name: String

## "camp" (ponto neutro, sem ação) ou "combat" por enquanto — os outros
## tipos (card_merchant, artifact_merchant, event) entram no Passo 1.6.
var type: String = ""

## Posição em pixels de tela, relativa ao canto superior esquerdo do
## overworld. Simples de propósito: o mapa cru não tem câmera nem scroll.
var position: Vector2 = Vector2.ZERO

## Só pra type "combat" (Passo 1.4): id de data/battles/*.json, a batalha
## iniciada ao entrar neste ponto. "" pros demais tipos.
var battle_id: String = ""

static func from_dict(data: Dictionary) -> WorldPointData:
	var point = WorldPointData.new()

	point.id = data.get("id", "")
	point.name = data.get("name", "")
	point.type = data.get("type", "")
	point.battle_id = data.get("battle", "")

	var raw_position: Array = data.get("position", [0, 0])

	if raw_position.size() >= 2:
		point.position = Vector2(raw_position[0], raw_position[1])

	return point

## Pontos em que "entrar" faz algo hoje — por enquanto só combate com
## batalha definida. Os demais tipos ganham ação no Passo 1.6.
func can_enter() -> bool:
	return type == "combat" and battle_id != ""
