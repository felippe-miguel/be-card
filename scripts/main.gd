extends Node

## Cena raiz do jogo (docs/CAMPAIGN_EXECUTION_PLAN.md, Passo 1.1): dona da
## tela atual. As telas nunca trocam de cena sozinhas — só emitem sinais
## (play_pressed, back_to_menu_pressed...), e é Main quem decide qual tela
## vem a seguir. A partir do Passo 1.3 também é Main quem guarda o
## CampaignState entre uma tela e outra, sem precisar de autoload global.

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const OVERWORLD_SCENE: PackedScene = preload("res://scenes/overworld.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/game.tscn")
const POINT_PLACEHOLDER_SCENE: PackedScene = preload("res://scenes/point_placeholder.tscn")
const CARD_MERCHANT_SCENE: PackedScene = preload("res://scenes/card_merchant.tscn")
const DECK_BUILDER_SCENE: PackedScene = preload("res://scenes/deck_builder.tscn")

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

## Ouro inicial, lido uma vez de data/campaign/starting_resources.json.
var starting_gold: int = 0

## Estoques dos mercadores de cartas (data/merchants/*.json), por id.
var merchant_database: MerchantDatabase

## Campanha em andamento — criada do zero a cada "Jogar" (não existe save
## nem "continuar" ainda, ver Etapa 8 do plano), e é ela, não a tela, que
## lembra onde o jogador está quando o overworld é recriado.
var campaign_state: CampaignState

func _ready() -> void:
	world_map = WorldMapData.load_from_file()

	card_database = CardDatabase.new()
	card_database.load_cards()

	starting_collection = CampaignState.load_starting_collection(card_database)
	starting_decks = CampaignState.load_starting_decks(card_database)
	starting_gold = CampaignState.load_starting_gold()

	merchant_database = MerchantDatabase.new()
	merchant_database.load_merchants(card_database)

	show_main_menu()

func show_main_menu() -> void:
	var menu: MainMenu = MAIN_MENU_SCENE.instantiate()

	menu.play_pressed.connect(_on_play_pressed)
	menu.quit_pressed.connect(_on_quit_pressed)

	switch_to(menu)

## notice: mensagem curta mostrada no topo do overworld ao chegar (ex: o
## ouro ganho num combate). "" = nenhuma.
func show_overworld(notice: String = "") -> void:
	var overworld: Overworld = OVERWORLD_SCENE.instantiate()

	overworld.setup(world_map, campaign_state, card_database, notice)
	overworld.back_to_menu_pressed.connect(show_main_menu)
	overworld.point_entered.connect(_on_point_entered)
	overworld.deck_edit_requested.connect(show_deck_builder)

	switch_to(overworld)

## A batalha recebe só os ids do deck ativo (um por cópia), não o
## CampaignState — ela não precisa saber nada da campanha além disso.
func show_battle(battle_id: String) -> void:
	var active_deck = campaign_state.get_active_deck()

	## Sem deck válido não tem como lutar — com os decks iniciais em JSON
	## isso só acontece se todos estiverem inválidos/vazios.
	if active_deck == null:
		print("Nenhum deck válido selecionado — combate não iniciado.")
		return

	var battle: Game = BATTLE_SCENE.instantiate()

	battle.setup_battle(battle_id, active_deck.get_card_ids())
	battle.battle_finished.connect(_on_battle_finished)

	switch_to(battle)

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

	builder.setup(campaign_state, card_database, deck_index)
	builder.closed.connect(show_overworld)

	switch_to(builder)

func show_card_merchant(point: WorldPointData, merchant: MerchantData) -> void:
	var screen: CardMerchant = CARD_MERCHANT_SCENE.instantiate()

	screen.setup(point, merchant, campaign_state, card_database)
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

func _on_play_pressed() -> void:
	campaign_state = CampaignState.new(world_map.start_point_id, starting_collection, starting_decks, starting_gold)

	show_overworld()

func _on_quit_pressed() -> void:
	get_tree().quit()

## Só chegam aqui pontos com WorldPointData.can_enter(). Combate abre a
## batalha; mercador de cartas com estoque definido abre a loja (Etapa 4).
## O resto (mercador de artefatos, evento, mercador sem estoque) ainda abre
## o placeholder — cada um troca por uma tela de verdade na sua etapa.
func _on_point_entered(point_id: String) -> void:
	var point: WorldPointData = world_map.points[point_id]

	match point.type:
		"combat":
			show_battle(point.battle_id)

		"card_merchant":
			var merchant: MerchantData = merchant_database.merchants.get(point.merchant_id)

			if merchant != null:
				show_card_merchant(point, merchant)
			else:
				print("Mercador sem estoque definido: ", point.merchant_id)
				show_point_placeholder(point)

		_:
			show_point_placeholder(point)

## Registra o resultado no ponto atual (de onde a batalha foi aberta) e
## volta pro overworld no mesmo ponto — campaign_state nunca saiu de Main,
## então o overworld recriado já sabe onde o jogador está e o que já fez.
func _on_battle_finished(victory: bool) -> void:
	var point: WorldPointData = world_map.points[campaign_state.current_point_id]
	var earned = campaign_state.record_current_combat_result(victory, point.gold_reward)
	var notice = ""

	if victory:
		notice = "Vitória em %s: +%d ouro" % [point.name, earned]

	show_overworld(notice)
