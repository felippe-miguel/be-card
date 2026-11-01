class_name CampaignState
extends RefCounted

## Estado de campanha (docs/CAMPAIGN_EXECUTION_PLAN.md, Passos 1.3/1.5 e
## Etapa 2): o que é específico DESTE jogador e sobrevive à campanha
## inteira — onde ele está no overworld, o que já fez em cada ponto, quais
## cartas e artefatos possui (Etapas 2 e 6), os decks que montou (Etapa 3)
## e quanto ouro tem (Etapa 4). Guarda só ids (nunca WorldPointData/CardData), pra
## serializar direto no save (Etapa 8, to_dict()/from_dict()) e pra uma
## mudança no JSON de uma carta valer na hora.

signal changed

## Versão do formato do save (campo "version"), pra migrações futuras.
const SAVE_VERSION = 1

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

## Coleção de artefatos (Etapa 6): artifact_id -> true (Dictionary como
## set). Cada artefato se possui uma vez só, e o MESMO artefato pode ser
## equipado em vários decks ao mesmo tempo — equipar não "gasta" nada.
var artifacts: Dictionary = {}

## Conjuntos de ids de ponto (point_id -> true) — Dictionary usado como set.
var visited_point_ids: Dictionary = {}

## Combates vencidos ao menos uma vez. Vencer não bloqueia o ponto: dá pra
## refazer o combate quantas vezes quiser (decisão do Passo 1.5), só fica
## marcado — refazer rende menos ouro (ver record_current_combat_result()).
var won_combat_point_ids: Dictionary = {}

## Eventos únicos (EventData.repeatable == false) já resolvidos, por id do
## EVENTO (não do ponto) — Etapa 7. Eventos repetíveis nunca entram aqui.
var completed_event_ids: Dictionary = {}

## starting_collection/starting_decks normalmente vêm de
## load_starting_collection()/load_starting_decks() (já validados contra o
## catálogo). Os decks são duplicados aqui — a campanha nunca altera os
## dados de partida. O deck ativo inicial é o primeiro válido da lista.
func _init(start_point_id: String, starting_collection: Dictionary = {}, starting_decks: Array[DeckList] = [], starting_gold: int = 0, starting_artifacts: Array[String] = []) -> void:
	current_point_id = start_point_id
	visited_point_ids[start_point_id] = true
	collection = starting_collection.duplicate()
	gold = max(0, starting_gold)

	## Antes dos decks: um deck inicial com artefato só é válido se o
	## artefato já estiver na coleção (ver is_deck_valid()).
	for artifact_id in starting_artifacts:
		artifacts[artifact_id] = true

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
static func load_starting_decks(card_database: CardDatabase, artifact_database: ArtifactDatabase, path: String = STARTING_DECKS_PATH) -> Array[DeckList]:
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
		result.append(DeckList.from_dict(deck_data, card_database, artifact_database))

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

## Artefatos iniciais de uma campanha nova, do mesmo STARTING_RESOURCES_PATH
## ({"artifacts": ["<artifact_id>", ...]}). Id desconhecido é ignorado com
## aviso.
static func load_starting_artifacts(artifact_database: ArtifactDatabase, path: String = STARTING_RESOURCES_PATH) -> Array[String]:
	var result: Array[String] = []
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return result

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return result

	for artifact_id in data.get("artifacts", []):
		if not artifact_database.artifacts.has(artifact_id):
			print("Artefato inicial desconhecido ignorado: ", artifact_id)
			continue

		result.append(artifact_id)

	return result

## Lê a coleção inicial de uma campanha nova de STARTING_COLLECTION_PATH
## ({"cards": {"<card_id>": <cópias>}}). Carta que não existe no catálogo
## ou quantidade inválida é descartada com aviso — mesmo espírito dos
## databases e do WorldMapData: um erro no JSON não trava o jogo.
static func load_starting_collection(card_database: CardDatabase, path: String = STARTING_COLLECTION_PATH) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return {}

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return {}

	var result = parse_collection(data.get("cards", {}), card_database, "Coleção inicial")

	print("Coleção inicial carregada: ", result.size(), " cartas diferentes")

	return result

## {"<card_id>": <cópias>} -> coleção validada, usado pela coleção inicial e
## pelo load do save. Carta fora do catálogo ou quantidade inválida é
## descartada com aviso; label diz de onde veio, pra mensagem.
static func parse_collection(raw_cards, card_database: CardDatabase, label: String) -> Dictionary:
	var result: Dictionary = {}

	if not raw_cards is Dictionary:
		push_warning("%s: coleção inválida ignorada" % label)
		return result

	for card_id in raw_cards:
		## JSON sempre devolve número como float — int() aqui, depois de
		## checar que é número mesmo.
		var raw_copies = raw_cards[card_id]

		if not card_database.cards.has(card_id):
			push_warning("%s: carta desconhecida ignorada: %s" % [label, card_id])
			continue

		if not (raw_copies is float or raw_copies is int) or int(raw_copies) < 1:
			push_warning("%s: quantidade inválida pra %s: %s" % [label, card_id, raw_copies])
			continue

		result[card_id] = int(raw_copies)

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

func owns_artifact(artifact_id: String) -> bool:
	return artifacts.has(artifact_id)

## Única forma de ganhar um artefato — mercador, recompensa e evento devem
## passar por aqui, igual add_card() pras cartas. Já possuído = nada muda.
func add_artifact(artifact_id: String) -> void:
	if owns_artifact(artifact_id):
		return

	artifacts[artifact_id] = true

	changed.emit()

## Mercador de artefatos (Etapa 6): recusa sem ouro ou se já possui (só dá
## pra ter um de cada).
func buy_artifact(artifact_id: String, price: int) -> bool:
	if owns_artifact(artifact_id) or not can_afford(price):
		return false

	gold -= price
	add_artifact(artifact_id)

	return true

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

## Válido = tem ao menos uma carta, não usa mais cópias de nenhuma carta
## do que a coleção possui, e o artefato equipado (se houver) é um que o
## jogador possui. Hoje coleção e artefatos só crescem, então um deck válido
## continua válido — isso muda se um dia der pra vender/perder algo.
func is_deck_valid(deck_list: DeckList) -> bool:
	if deck_list.get_total_card_count() == 0:
		return false

	if deck_list.artifact_id != "" and not owns_artifact(deck_list.artifact_id):
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

## Ganha (ou, com valor negativo, perde) ouro, sem nunca ficar abaixo de 0.
## Usado pelos eventos (Etapa 7); compras seguem por buy_card()/buy_artifact().
func add_gold(amount: int) -> void:
	gold = max(0, gold + amount)

	changed.emit()

func is_event_completed(event_id: String) -> bool:
	return completed_event_ids.has(event_id)

## Só eventos únicos são marcados (ver EventData.repeatable).
func complete_event(event_id: String) -> void:
	completed_event_ids[event_id] = true

	changed.emit()

## Uma escolha de evento só pode ser feita com ouro pra pagar o que ela
## cobra e sem entregar um artefato que o jogador já tem.
func can_choose_event_choice(event: EventData, choice_index: int) -> bool:
	if choice_index < 0 or choice_index >= event.choices.size():
		return false

	if not can_afford(event.get_gold_cost(choice_index)):
		return false

	for artifact_id in event.get_artifact_ids(choice_index):
		if owns_artifact(artifact_id):
			return false

	return true

## Aplica os efeitos da escolha pelas operações de sempre (add_gold(),
## add_card(), add_artifact()) e marca o evento como resolvido se ele for
## único. Retorna {"applied": false} se a escolha foi recusada (evento
## único já resolvido, sem ouro, artefato repetido) e, se aplicada,
## {"applied": true, "battle": <efeito de batalha ou {}>} — a batalha em si
## é aberta por quem chama (Main), não aqui. O evento conta como resolvido
## ao ESCOLHER, mesmo que a batalha seja perdida depois.
func apply_event_choice(event: EventData, choice_index: int) -> Dictionary:
	if (not event.repeatable and is_event_completed(event.id)) or not can_choose_event_choice(event, choice_index):
		return {"applied": false}

	if not event.repeatable:
		complete_event(event.id)

	for effect in event.choices[choice_index].effects:
		match effect.type:
			"gold":
				add_gold(effect.amount)

			"card":
				add_card(effect.card_id, effect.count)

			"artifact":
				add_artifact(effect.artifact_id)

	return {"applied": true, "battle": event.get_battle_effect(choice_index)}

## Estado serializável (Etapa 8): só ids e números, nunca dados do catálogo.
## Conjuntos viram listas ordenadas (save estável entre execuções).
func to_dict() -> Dictionary:
	var decks: Array[Dictionary] = []

	for deck_list in deck_lists:
		decks.append(deck_list.to_dict())

	return {
		"version": SAVE_VERSION,
		"current_point": current_point_id,
		"gold": gold,
		"collection": collection.duplicate(),
		"artifacts": sorted_keys(artifacts),
		"decks": decks,
		"active_deck": active_deck_index,
		"visited_points": sorted_keys(visited_point_ids),
		"won_combats": sorted_keys(won_combat_point_ids),
		"completed_events": sorted_keys(completed_event_ids),
	}

static func sorted_keys(set: Dictionary) -> Array:
	var keys = set.keys()

	keys.sort()

	return keys

## Reconstrói a campanha de um save lido do disco. Tolerante de propósito:
## o catálogo pode ter mudado desde o save, então id que não existe mais é
## descartado com aviso (coleção, decks, artefatos, pontos, eventos), o
## número de cópias de um deck é limitado ao da coleção, e o que ficar
## inconsistente é consertado (ponto atual desconhecido = ponto inicial,
## deck ativo inválido = primeiro deck, sem nenhum deck = fallback_decks,
## normalmente os decks iniciais).
static func from_dict(data: Dictionary, world_map: WorldMapData, card_database: CardDatabase, artifact_database: ArtifactDatabase, event_database: EventDatabase, fallback_decks: Array[DeckList] = []) -> CampaignState:
	var state = CampaignState.new(world_map.start_point_id)

	var raw_point = data.get("current_point", "")

	if world_map.points.has(raw_point):
		state.current_point_id = raw_point
	else:
		push_warning("Save: ponto atual desconhecido (%s), usando o ponto inicial" % str(raw_point))

	var raw_gold = data.get("gold", 0)

	if (raw_gold is float or raw_gold is int) and int(raw_gold) >= 0:
		state.gold = int(raw_gold)
	else:
		push_warning("Save: ouro inválido: %s" % str(raw_gold))

	state.collection = parse_collection(data.get("collection", {}), card_database, "Save")

	for artifact_id in as_array(data.get("artifacts", [])):
		if artifact_database.artifacts.has(artifact_id):
			state.artifacts[artifact_id] = true
		else:
			push_warning("Save: artefato desconhecido ignorado: %s" % str(artifact_id))

	## O ponto atual e o inicial contam como visitados mesmo que o save
	## não diga (o save de uma campanha em andamento sempre os inclui).
	state.visited_point_ids = known_id_set(data.get("visited_points", []), world_map.points, "ponto visitado")
	state.visited_point_ids[world_map.start_point_id] = true
	state.visited_point_ids[state.current_point_id] = true
	state.won_combat_point_ids = known_id_set(data.get("won_combats", []), world_map.points, "combate vencido")
	state.completed_event_ids = known_id_set(data.get("completed_events", []), event_database.events, "evento resolvido")

	var raw_active = data.get("active_deck", -1)
	var raw_decks = as_array(data.get("decks", []))
	var saved_active_new_index = -1

	for i in range(raw_decks.size()):
		if not raw_decks[i] is Dictionary:
			push_warning("Save: deck inválido ignorado: %s" % str(raw_decks[i]))
			continue

		var deck_list = DeckList.from_dict(raw_decks[i], card_database, artifact_database)

		if not state.clamp_deck_to_collection(deck_list):
			continue

		state.deck_lists.append(deck_list)

		if (raw_active is float or raw_active is int) and int(raw_active) == i:
			saved_active_new_index = state.deck_lists.size() - 1

	if state.deck_lists.is_empty():
		push_warning("Save: nenhum deck válido, usando os decks iniciais")

		for fallback in fallback_decks:
			var fallback_copy = fallback.duplicate_list()

			## Save sem coleção utilizável: garante as cartas do deck
			## inicial, senão a campanha ficaria sem nenhum deck válido.
			for card_id in fallback_copy.cards:
				state.collection[card_id] = max(state.get_copies(card_id), fallback_copy.cards[card_id])

			if state.clamp_deck_to_collection(fallback_copy):
				state.deck_lists.append(fallback_copy)

	state.active_deck_index = saved_active_new_index

	if state.active_deck_index < 0 and not state.deck_lists.is_empty():
		push_warning("Save: deck ativo inválido, usando o primeiro deck")
		state.active_deck_index = 0

	return state

## Tolera lista ausente ou de tipo errado no JSON do save.
static func as_array(raw) -> Array:
	return raw if raw is Array else []

## Lista de ids do save -> conjunto só com os que existem em known (um
## Dictionary cujas chaves são os ids válidos); os outros são descartados
## com aviso. label: o que a lista representa, pra mensagem.
static func known_id_set(raw_ids, known: Dictionary, label: String) -> Dictionary:
	var result: Dictionary = {}

	for id in as_array(raw_ids):
		if known.has(id):
			result[id] = true
		else:
			push_warning("Save: %s desconhecido ignorado: %s" % [label, str(id)])

	return result

## Conserta um deck vindo do save pra ele voltar a ser válido: cópias
## limitadas ao que a coleção possui, artefato não possuído removido.
## Retorna false se o deck ficou vazio (e deve ser descartado).
func clamp_deck_to_collection(deck_list: DeckList) -> bool:
	for card_id in deck_list.cards.keys():
		var owned = get_copies(card_id)

		if deck_list.cards[card_id] > owned:
			push_warning("Save: deck \"%s\" usava %d× %s mas a coleção tem %d" % [deck_list.name, deck_list.cards[card_id], card_id, owned])

			if owned > 0:
				deck_list.cards[card_id] = owned
			else:
				deck_list.cards.erase(card_id)

	if deck_list.artifact_id != "" and not owns_artifact(deck_list.artifact_id):
		push_warning("Save: deck \"%s\" usava um artefato não possuído (%s), removido" % [deck_list.name, deck_list.artifact_id])
		deck_list.artifact_id = ""

	if deck_list.get_total_card_count() == 0:
		push_warning("Save: deck \"%s\" ficou vazio e foi descartado" % deck_list.name)
		return false

	return true
