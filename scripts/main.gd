extends Node

## Cena raiz do jogo (docs/CAMPAIGN_EXECUTION_PLAN.md, Passo 1.1): dona da
## tela atual. As telas nunca trocam de cena sozinhas — só emitem sinais
## (play_pressed, back_to_menu_pressed...), e é Main quem decide qual tela
## vem a seguir. A partir do Passo 1.3 também é Main quem guarda o
## CampaignState entre uma tela e outra, sem precisar de autoload global.

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const OVERWORLD_SCENE: PackedScene = preload("res://scenes/overworld.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/game.tscn")

## Tela atualmente instanciada como filha de Main — liberada a cada troca
## (switch_to()), então só existe uma tela viva por vez.
var current_screen: Node = null

## Catálogo do overworld, carregado uma vez — repassado ao Overworld a cada
## vez que ele é instanciado (ver show_overworld()).
var world_map: WorldMapData

## Campanha em andamento — criada do zero a cada "Jogar" (não existe save
## nem "continuar" ainda, ver Etapa 8 do plano), e é ela, não a tela, que
## lembra onde o jogador está quando o overworld é recriado.
var campaign_state: CampaignState

func _ready() -> void:
	world_map = WorldMapData.load_from_file()

	show_main_menu()

func show_main_menu() -> void:
	var menu: MainMenu = MAIN_MENU_SCENE.instantiate()

	menu.play_pressed.connect(_on_play_pressed)
	menu.quit_pressed.connect(_on_quit_pressed)

	switch_to(menu)

func show_overworld() -> void:
	var overworld: Overworld = OVERWORLD_SCENE.instantiate()

	overworld.setup(world_map, campaign_state)
	overworld.back_to_menu_pressed.connect(show_main_menu)
	overworld.point_entered.connect(_on_point_entered)

	switch_to(overworld)

func show_battle(battle_id: String) -> void:
	var battle: Game = BATTLE_SCENE.instantiate()

	battle.setup_battle(battle_id)
	battle.battle_finished.connect(_on_battle_finished)

	switch_to(battle)

## queue_free() (não free()) porque quem chama isto normalmente está
## reagindo a um sinal emitido de dentro da própria tela que vai ser
## liberada — liberar na hora destruiria o emissor no meio da emissão.
func switch_to(screen: Node) -> void:
	if current_screen != null:
		current_screen.queue_free()

	current_screen = screen
	add_child(screen)

func _on_play_pressed() -> void:
	campaign_state = CampaignState.new(world_map.start_point_id)

	show_overworld()

func _on_quit_pressed() -> void:
	get_tree().quit()

## Só pontos de combate chegam aqui hoje (WorldPointData.can_enter()); os
## outros tipos ganham tela própria no Passo 1.6.
func _on_point_entered(point_id: String) -> void:
	var point: WorldPointData = world_map.points[point_id]

	if point.type == "combat":
		show_battle(point.battle_id)

## Registra o resultado no ponto atual (de onde a batalha foi aberta) e
## volta pro overworld no mesmo ponto — campaign_state nunca saiu de Main,
## então o overworld recriado já sabe onde o jogador está e o que já fez.
func _on_battle_finished(victory: bool) -> void:
	campaign_state.record_current_combat_result(victory)

	show_overworld()
