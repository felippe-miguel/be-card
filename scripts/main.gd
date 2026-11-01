extends Node

## Cena raiz do jogo (docs/CAMPAIGN_EXECUTION_PLAN.md, Passo 1.1): dona da
## tela atual. As telas nunca trocam de cena sozinhas — só emitem sinais
## (new_campaign_pressed, back_to_menu_pressed...), e é Main quem decide qual tela
## vem a seguir. A partir do Passo 1.3 também é Main quem guarda o
## CampaignState entre uma tela e outra, sem precisar de autoload global.

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const OVERWORLD_SCENE: PackedScene = preload("res://scenes/overworld.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/game.tscn")
const POINT_PLACEHOLDER_SCENE: PackedScene = preload("res://scenes/point_placeholder.tscn")
const MERCHANT_SCENE: PackedScene = preload("res://scenes/merchant.tscn")
const DECK_BUILDER_SCENE: PackedScene = preload("res://scenes/deck_builder.tscn")
const EVENT_SCENE: PackedScene = preload("res://scenes/event.tscn")

## Tela atualmente instanciada como filha de Main — liberada a cada troca
## (switch_to()), então só existe uma tela viva por vez.
var current_screen: Node = null

## Catálogo do overworld, carregado uma vez — repassado ao Overworld a cada
## vez que ele é instanciado (ver show_overworld()).
var world_map: WorldMapData

## Catálogo de cartas, carregado uma vez — usado pra validar a coleção e os
## decks iniciais e pra mostrar nome das cartas fora da batalha. A batalha
## (Game) ainda carrega o próprio catálogo: ela só recebe ids de carta
## (setup_battle()), então unificar os dois não é necessário por enquanto.
var card_database: CardDatabase

## Coleção inicial já validada (card_id -> cópias), lida uma vez de
## data/campaign/starting_collection.json e copiada pra cada campanha nova.
var starting_collection: Dictionary

## Decks iniciais já validados, lidos uma vez de
## data/campaign/starting_decks.json — cada campanha nova recebe cópias.
var starting_decks: Array[DeckList] = []

## Ouro e artefatos iniciais, lidos uma vez de
## data/campaign/starting_resources.json.
var starting_gold: int = 0
var starting_artifacts: Array[String] = []

## Catálogo de artefatos (data/artifacts/*.json) — Etapa 6.
var artifact_database: ArtifactDatabase

## Estoques dos mercadores (data/merchants/*.json), por id.
var merchant_database: MerchantDatabase

## Eventos (data/events/*.json), por id — Etapa 7.
var event_database: EventDatabase

## Campanha em andamento — criada do zero em "Nova campanha" ou lida do save
## em "Continuar", e é ela, não a tela, que lembra onde o jogador está quando
## o overworld é recriado.
var campaign_state: CampaignState

## Onde o save fica. Variável (não só a constante) pra um teste poder usar
## outro arquivo sem tocar no save real.
var save_path: String = CampaignSave.SAVE_PATH

## Ouro pago se a batalha em andamento veio de uma escolha de evento e for
## vencida (Etapa 7); -1 = a batalha atual é a de um ponto de combate. Evento
## com batalha não passa por record_current_combat_result(): o ponto atual é
## o do evento, não um combate vencível.
var event_battle_gold: int = -1

func _ready() -> void:
	world_map = WorldMapData.load_from_file()

	card_database = CardDatabase.new()
	card_database.load_cards()

	artifact_database = ArtifactDatabase.new()
	artifact_database.load_artifacts()

	starting_collection = CampaignState.load_starting_collection(card_database)
	starting_decks = CampaignState.load_starting_decks(card_database, artifact_database)
	starting_gold = CampaignState.load_starting_gold()
	starting_artifacts = CampaignState.load_starting_artifacts(artifact_database)

	merchant_database = MerchantDatabase.new()
	merchant_database.load_merchants(card_database, artifact_database)

	event_database = EventDatabase.new()
	event_database.load_events(card_database, artifact_database)

	show_main_menu()

func show_main_menu() -> void:
	var menu: MainMenu = MAIN_MENU_SCENE.instantiate()

	menu.setup(CampaignSave.exists(save_path))
	menu.continue_pressed.connect(_on_continue_pressed)
	menu.new_campaign_pressed.connect(_on_new_campaign_pressed)
	menu.quit_pressed.connect(_on_quit_pressed)

	switch_to(menu)

## notice: mensagem curta mostrada no topo do overworld ao chegar (ex: o
## ouro ganho num combate). "" = nenhuma.
func show_overworld(notice: String = "") -> void:
	## Voltar ao mapa (de qualquer tela) é um ponto de autosave — ver
	## save_campaign().
	save_campaign()

	var overworld: Overworld = OVERWORLD_SCENE.instantiate()

	overworld.setup(world_map, campaign_state, card_database, artifact_database, notice)
	overworld.back_to_menu_pressed.connect(show_main_menu)
	overworld.point_entered.connect(_on_point_entered)
	overworld.deck_edit_requested.connect(show_deck_builder)

	switch_to(overworld)

## A batalha recebe só os ids do deck ativo (um por cópia) e o artefato
## equipado nele (ArtifactData ou null), não o CampaignState — ela não
## precisa saber nada da campanha além disso.
func show_battle(battle_id: String) -> bool:
	var active_deck = campaign_state.get_active_deck()

	## Sem deck válido não tem como lutar — com os decks iniciais em JSON
	## isso só acontece se todos estiverem inválidos/vazios.
	if active_deck == null:
		print("Nenhum deck válido selecionado — combate não iniciado.")
		return false

	var battle: Game = BATTLE_SCENE.instantiate()

	battle.setup_battle(battle_id, active_deck.get_card_ids(), artifact_database.artifacts.get(active_deck.artifact_id))
	battle.battle_finished.connect(_on_battle_finished)

	switch_to(battle)

	return true

## Evento com dado definido (Etapa 7). Escolher aplica os efeitos no
## CampaignState (dentro da própria tela); só a escolha com batalha precisa
## de Main.
func show_event(event_data: EventData) -> void:
	var screen: Event = EVENT_SCENE.instantiate()

	screen.setup(event_data, campaign_state, card_database, artifact_database)
	screen.back_pressed.connect(show_overworld)
	screen.battle_requested.connect(_on_event_battle_requested)

	switch_to(screen)

## Voltar daqui não registra nada — o placeholder não tem resultado, só
## devolve o jogador pro mapa no mesmo ponto.
func show_point_placeholder(point: WorldPointData) -> void:
	var placeholder: PointPlaceholder = POINT_PLACEHOLDER_SCENE.instantiate()

	placeholder.setup(point)
	placeholder.back_pressed.connect(show_overworld)

	switch_to(placeholder)

## deck_index -1 = deck novo. Salvar/apagar/cancelar sempre voltam pro
## overworld, com o aviso que o DeckBuilder mandar (ex: "Deck X salvo").
func show_deck_builder(deck_index: int) -> void:
	var builder: DeckBuilder = DECK_BUILDER_SCENE.instantiate()

	builder.setup(campaign_state, card_database, artifact_database, deck_index)
	builder.closed.connect(show_overworld)

	switch_to(builder)

## Mesma tela pra mercador de cartas e de artefatos — ela mostra as seções
## que o estoque (MerchantData) tiver.
func show_merchant(point: WorldPointData, merchant: MerchantData) -> void:
	var screen: Merchant = MERCHANT_SCENE.instantiate()

	screen.setup(point, merchant, campaign_state, card_database, artifact_database)
	screen.back_pressed.connect(show_overworld)

	switch_to(screen)

## queue_free() (não free()) porque quem chama isto normalmente está
## reagindo a um sinal emitido de dentro da própria tela que vai ser
## liberada — liberar na hora destruiria o emissor no meio da emissão.
func switch_to(screen: Node) -> void:
	if current_screen != null:
		current_screen.queue_free()

	current_screen = screen
	add_child(screen)

func _on_new_campaign_pressed() -> void:
	set_campaign_state(CampaignState.new(world_map.start_point_id, starting_collection, starting_decks, starting_gold, starting_artifacts))

	show_overworld()

## "Continuar": o save foi validado pelo menu (CampaignSave.exists()), mas
## pode ter mudado no disco desde então — se não der pra ler, volta ao menu.
func _on_continue_pressed() -> void:
	var data = CampaignSave.read(save_path)

	if data.is_empty():
		show_main_menu()
		return

	set_campaign_state(CampaignState.from_dict(data, world_map, card_database, artifact_database, event_database, starting_decks))

	show_overworld("Campanha carregada.")

## Autosave (Etapa 8): toda mudança do CampaignState (viagem, compra, deck
## salvo/apagado/ativado, escolha de evento, resultado de combate) emite
## `changed`, então ligar o save a esse sinal cobre todas de uma vez.
## Nunca acontece no meio de uma batalha, porque a batalha não toca no
## CampaignState — só o resultado dela, depois.
func set_campaign_state(state: CampaignState) -> void:
	campaign_state = state
	campaign_state.changed.connect(save_campaign)

func save_campaign() -> void:
	if campaign_state != null:
		CampaignSave.write(campaign_state, save_path)

func _on_quit_pressed() -> void:
	get_tree().quit()

## Só chegam aqui pontos com WorldPointData.can_enter(). Combate abre a
## batalha; mercador (de cartas ou de artefatos) com estoque definido abre a
## loja (Etapas 4 e 6), evento com dado definido abre a tela de evento
## (Etapa 7). O resto (mercador/evento sem dado) ainda abre o placeholder.
func _on_point_entered(point_id: String) -> void:
	var point: WorldPointData = world_map.points[point_id]

	match point.type:
		"combat":
			show_battle(point.battle_id)

		"card_merchant", "artifact_merchant":
			var merchant: MerchantData = merchant_database.merchants.get(point.merchant_id)

			if merchant != null:
				show_merchant(point, merchant)
			else:
				print("Mercador sem estoque definido: ", point.merchant_id)
				show_point_placeholder(point)

		"event":
			var event_data: EventData = event_database.events.get(point.event_id)

			if event_data != null:
				show_event(event_data)
			else:
				print("Evento sem dado definido: ", point.event_id)
				show_point_placeholder(point)

		_:
			show_point_placeholder(point)

## A escolha do evento já foi aplicada (e o evento marcado como resolvido, se
## único) — aqui só se abre a batalha. Se não houver deck válido, a luta não
## acontece mas o evento continua resolvido; volta pro mapa com um aviso.
func _on_event_battle_requested(battle_id: String, gold: int) -> void:
	event_battle_gold = gold

	if not show_battle(battle_id):
		event_battle_gold = -1
		show_overworld("Sem deck válido: a batalha não aconteceu.")

## Registra o resultado no ponto atual (de onde a batalha foi aberta) e
## volta pro overworld no mesmo ponto — campaign_state nunca saiu de Main,
## então o overworld recriado já sabe onde o jogador está e o que já fez.
func _on_battle_finished(victory: bool) -> void:
	if event_battle_gold >= 0:
		finish_event_battle(victory)
		return

	var point: WorldPointData = world_map.points[campaign_state.current_point_id]
	var earned = campaign_state.record_current_combat_result(victory, point.gold_reward)
	var notice = ""

	if victory:
		notice = "Vitória em %s: +%d ouro" % [point.name, earned]

	show_overworld(notice)

## Batalha de um evento: vitória paga o ouro do efeito, derrota não custa
## nada além de a escolha já estar feita (o evento único não volta).
func finish_event_battle(victory: bool) -> void:
	var gold = event_battle_gold
	var notice = "Derrota no desafio."

	event_battle_gold = -1

	if victory:
		campaign_state.add_gold(gold)
		notice = "Vitória no desafio: +%d ouro" % gold

	show_overworld(notice)
