class_name CampaignState
extends RefCounted

## Estado de campanha (docs/CAMPAIGN_EXECUTION_PLAN.md, Passos 1.3/1.5): o
## que é específico DESTE jogador e sobrevive à campanha inteira — onde ele
## está no overworld e o que já fez em cada ponto. Coleção, decks, ouro etc.
## entram nas próximas etapas. Guarda só ids (nunca WorldPointData), pra
## serializar direto num save no futuro (Etapa 8).

signal changed

var current_point_id: String = ""

## Conjuntos de ids de ponto (point_id -> true) — Dictionary usado como set.
var visited_point_ids: Dictionary = {}

## Combates vencidos ao menos uma vez. Vencer não bloqueia o ponto: dá pra
## refazer o combate quantas vezes quiser (decisão do Passo 1.5), só fica
## marcado. Se refazer dá recompensa é decidido quando houver ouro (Etapa 4).
var won_combat_point_ids: Dictionary = {}

func _init(start_point_id: String) -> void:
	current_point_id = start_point_id
	visited_point_ids[start_point_id] = true

## Exploração livre: dá pra ir pra qualquer ponto conectado ao atual, em
## qualquer direção (inclusive voltar). Não dá pra "viajar" pro próprio
## ponto atual.
func can_travel_to(point_id: String, world_map: WorldMapData) -> bool:
	return point_id != current_point_id and world_map.are_connected(current_point_id, point_id)

func travel_to(point_id: String, world_map: WorldMapData) -> bool:
	if not can_travel_to(point_id, world_map):
		return false

	current_point_id = point_id
	visited_point_ids[point_id] = true

	changed.emit()

	return true

func is_visited(point_id: String) -> bool:
	return visited_point_ids.has(point_id)

func is_combat_won(point_id: String) -> bool:
	return won_combat_point_ids.has(point_id)

## Só existe vitória/derrota no ponto atual — um combate sempre é aberto a
## partir do ponto onde o jogador está (Passo 1.4). Derrota não muda nada
## por enquanto (nem desmarca uma vitória anterior).
func record_current_combat_result(victory: bool) -> void:
	if not victory:
		return

	won_combat_point_ids[current_point_id] = true

	changed.emit()
