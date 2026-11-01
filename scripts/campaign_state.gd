class_name CampaignState
extends RefCounted

## Estado de campanha (docs/CAMPAIGN_EXECUTION_PLAN.md, Passos 1.3/1.5 e
## Etapa 2): o que é específico DESTE jogador e sobrevive à campanha
## inteira — onde ele está no overworld, o que já fez em cada ponto, quais
## cartas possui, os decks que montou (Etapa 3) e quanto ouro tem (Etapa
## 4). Artefatos entram nas próximas etapas. Guarda só ids (nunca WorldPointData/CardData), pra
## serializar direto num save no futuro (Etapa 8) e pra uma mudança no
## JSON de uma carta valer na hora.

signal changed

const STARTING_COLLECTION_PATH = "res://data/campaign/starting_collection.json"
const STARTING_DECKS_PATH = "res://data/campaign/starting_decks.json"
const STARTING_RESOURCES_PATH = "res://data/campaign/starting_resources.json"

## Refazer um combate já vencido rende só esta fração do ouro do ponto
## (decisão da versão crua) — ainda vale a pena, mas não vira farm fácil.
const REPEAT_COMBAT_GOLD_FACTOR = 0.5

var current_point_id: String = ""

## Coleção de cartas (Etapa 2): card_id -> cópias possuídas (sempre >= 1;
## carta com 0 cópias simplesmente não aparece aqui). É o que o jogador TEM,
## não o que leva pra batalha — isso é o DeckList (Etapa 3), montado a
## partir daqui.
var collection: Dictionary = {}

## Decks montados (Etapa 3). Regra permissiva por decisão do usuário: sem
## tamanho mínimo/máximo nem limite de cópias por carta — só não dá pra
## usar mais cópias do que a coleção tem, e um deck vazio não é escolhível
## (ver is_deck_valid()).
var deck_lists: Array[DeckList] = []

## Índice em deck_lists do deck levado pra toda batalha, escolhido no
## overworld (não a cada combate — decisão do usuário). -1 = nenhum deck
## válido.
var active_deck_index: int = -1

## Ouro (Etapa 4): ganho vencendo combates, gasto em mercadores.
var gold: int = 0

## Conjuntos de ids de ponto (point_id -> true) — Dictionary usado como set.
var visited_point_ids: Dictionary = {}

## Combates vencidos ao menos uma vez. Vencer não bloqueia o ponto: dá pra
## refazer o combate quantas vezes quiser (decisão do Passo 1.5), só fica
## marcado — refazer rende menos ouro (ver record_current_combat_result()).
var won_combat_point_ids: Dictionary = {}

## starting_collection/starting_decks normalmente vêm de
## load_starting_collection()/load_starting_decks() (já validados contra o
## catálogo). Os decks são duplicados aqui — a campanha nunca altera os
## dados de partida. O deck ativo inicial é o primeiro válido da lista.
func _init(start_point_id: String, starting_collection: Dictionary = {}, starting_decks: Array[DeckList] = [], starting_gold: int = 0) -> void:
	current_point_id = start_point_id
	visited_point_ids[start_point_id] = true
	collection = starting_collection.duplicate()
	gold = max(0, starting_gold)

	for deck_list in starting_decks:
		deck_lists.append(deck_list.duplicate_list())

	for i in range(deck_lists.size()):
		if is_deck_valid(deck_lists[i]):
			active_deck_index = i
			break

## Lê os decks iniciais de STARTING_DECKS_PATH ({"decks": [{"name": ...,
## "cards": {...}}]}) — o primeiro da lista vira o deck ativo de uma
## campanha nova (se for válido). Cada deck valida as próprias cartas em
## DeckList.from_dict().
static func load_starting_decks(card_database: CardDatabase, path: String = STARTING_DECKS_PATH) -> Array[DeckList]:
	var result: Array[DeckList] = []
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return result

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return result

	for deck_data in data.get("decks", []):
		result.append(DeckList.from_dict(deck_data, card_database))

	print("Decks iniciais carregados: ", result.size())

	return result

## Ouro inicial de uma campanha nova, de STARTING_RESOURCES_PATH
## ({"gold": <n>}). Arquivo separado da coleção de propósito: é o lugar dos
## "recursos de partida" que não são cartas (artefatos iniciais, no futuro).
static func load_starting_gold(path: String = STARTING_RESOURCES_PATH) -> int:
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return 0

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return 0

	var raw_gold = data.get("gold", 0)

	if not (raw_gold is float or raw_gold is int) or int(raw_gold) < 0:
		print("Ouro inicial inválido: ", raw_gold)
		return 0

	return int(raw_gold)

## Lê a coleção inicial de uma campanha nova de STARTING_COLLECTION_PATH
## ({"cards": {"<card_id>": <cópias>}}). Carta que não existe no catálogo
## ou quantidade inválida é descartada com aviso — mesmo espírito dos
## databases e do WorldMapData: um erro no JSON não trava o jogo.
static func load_starting_collection(card_database: CardDatabase, path: String = STARTING_COLLECTION_PATH) -> Dictionary:
	var result: Dictionary = {}
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return result

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return result

	var cards: Dictionary = data.get("cards", {})

	for card_id in cards:
		## JSON sempre devolve número como float — int() aqui, depois de
		## checar que é número mesmo.
		var raw_copies = cards[card_id]

		if not card_database.cards.has(card_id):
			print("Coleção inicial: carta desconhecida ignorada: ", card_id)
			continue

		if not (raw_copies is float or raw_copies is int) or int(raw_copies) < 1:
			print("Coleção inicial: quantidade inválida pra ", card_id, ": ", raw_copies)
			continue

		result[card_id] = int(raw_copies)

	print("Coleção inicial carregada: ", result.size(), " cartas diferentes")

	return result

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
## partir do ponto onde o jogador está (Passo 1.4). Vitória rende gold_reward
## na primeira vez e REPEAT_COMBAT_GOLD_FACTOR disso nas seguintes (arredonda
## pra baixo). Derrota não dá nada nem desmarca uma vitória anterior.
## Retorna o ouro ganho, pra quem chama poder avisar o jogador.
func record_current_combat_result(victory: bool, gold_reward: int = 0) -> int:
	if not victory:
		return 0

	var earned = gold_reward

	if is_combat_won(current_point_id):
		earned = int(gold_reward * REPEAT_COMBAT_GOLD_FACTOR)

	won_combat_point_ids[current_point_id] = true
	gold += max(0, earned)

	changed.emit()

	return max(0, earned)

func can_afford(price: int) -> bool:
	return price >= 0 and gold >= price

## Compra uma cópia de card_id (mercador de cartas — Etapa 4): debita o
## ouro e cresce a coleção pelo mesmo add_card() de sempre. Recusa sem ouro
## suficiente.
func buy_card(card_id: String, price: int) -> bool:
	if not can_afford(price):
		return false

	gold -= price
	add_card(card_id)

	return true

## Única forma de crescer a coleção — mercador (Etapa 4), recompensa de
## combate e eventos devem todos passar por aqui, não por um caminho próprio.
func add_card(card_id: String, copies: int = 1) -> void:
	if copies < 1:
		return

	collection[card_id] = get_copies(card_id) + copies

	changed.emit()

func get_copies(card_id: String) -> int:
	return collection.get(card_id, 0)

func get_total_card_count() -> int:
	var total = 0

	for card_id in collection:
		total += collection[card_id]

	return total

## Válido = tem ao menos uma carta e não usa mais cópias de nenhuma carta
## do que a coleção possui. Hoje a coleção só cresce, então um deck válido
## continua válido — isso muda se um dia der pra vender/perder carta.
func is_deck_valid(deck_list: DeckList) -> bool:
	if deck_list.get_total_card_count() == 0:
		return false

	for card_id in deck_list.cards:
		if deck_list.get_copies(card_id) > get_copies(card_id):
			return false

	return true

func get_active_deck() -> DeckList:
	if active_deck_index < 0 or active_deck_index >= deck_lists.size():
		return null

	return deck_lists[active_deck_index]

## Grava um deck editado no DeckBuilder (Etapa 5), que sempre trabalha numa
## cópia (DeckList.duplicate_list()) — cancelar a edição não mexe em nada
## aqui. index -1 = deck novo (vai pro fim da lista). Recusa deck inválido
## ou com nome já usado por outro deck (ver is_deck_name_taken()).
## Se ainda não havia deck ativo, o salvo vira o ativo. Retorna o índice
## onde o deck ficou, ou -1 se recusado.
func save_deck(index: int, deck_list: DeckList) -> int:
	if not is_deck_valid(deck_list):
		return -1

	deck_list.name = normalize_deck_name(deck_list.name)

	if is_deck_name_taken(deck_list.name, index):
		return -1

	if index < 0 or index >= deck_lists.size():
		deck_lists.append(deck_list)
		index = deck_lists.size() - 1
	else:
		deck_lists[index] = deck_list

	if active_deck_index < 0:
		active_deck_index = index

	changed.emit()

	return index

## Nome como ele é salvo: sem espaços nas pontas, e "Sem nome" se ficar
## vazio — usado tanto por save_deck() quanto pela checagem de nome
## repetido, pra os dois concordarem.
static func normalize_deck_name(deck_name: String) -> String:
	var trimmed = deck_name.strip_edges()

	return trimmed if trimmed != "" else "Sem nome"

## Dois decks não podem ter o mesmo nome (decisão do usuário) — comparação
## sem diferenciar maiúsculas/minúsculas e sem espaços nas pontas.
## except_index = o próprio deck sendo editado, que não conta como
## repetido dele mesmo (-1 = deck novo, compara com todos).
func is_deck_name_taken(deck_name: String, except_index: int = -1) -> bool:
	var wanted = normalize_deck_name(deck_name).to_lower()

	for i in range(deck_lists.size()):
		if i != except_index and deck_lists[i].name.strip_edges().to_lower() == wanted:
			return true

	return false

## O último deck que sobrar não pode ser apagado — sem nenhum deck não dá
## pra entrar em combate. Apagar o deck ativo passa a ativar o primeiro
## válido que restar; apagar um deck antes do ativo só reajusta o índice.
func can_delete_deck(index: int) -> bool:
	return index >= 0 and index < deck_lists.size() and deck_lists.size() > 1

func delete_deck(index: int) -> bool:
	if not can_delete_deck(index):
		return false

	deck_lists.remove_at(index)

	if index == active_deck_index:
		active_deck_index = -1

		for i in range(deck_lists.size()):
			if is_deck_valid(deck_lists[i]):
				active_deck_index = i
				break
	elif index < active_deck_index:
		active_deck_index -= 1

	changed.emit()

	return true

## Recusa deck inexistente ou inválido (ver is_deck_valid()).
func select_deck(index: int) -> bool:
	if index < 0 or index >= deck_lists.size() or not is_deck_valid(deck_lists[index]):
		return false

	active_deck_index = index

	changed.emit()

	return true
