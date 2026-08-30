class_name UnitView
extends Button

const NORMAL_COLOR = Color(1, 1, 1, 1)
const INCREASE_COLOR = Color(0.4, 1, 0.4, 1)
const DECREASE_COLOR = Color(1, 0.4, 0.4, 1)

## row: 0 = Front, 1 = Middle, 2 = Back (ver docs/playtest_3x3.md).
const ROW_NAMES = ["Front", "Middle", "Back"]

@onready var name_label: Label = $Content/NameLabel
@onready var faction_label: Label = $Content/FactionLabel
@onready var hp_label: Label = $Content/HpLabel
@onready var atk_label: Label = $Content/AtkLabel
@onready var block_label: Label = $Content/BlockLabel
@onready var position_label: Label = $Content/PositionLabel
@onready var death_indicator: Label = $DeathIndicator

var unit: Unit

## Efeitos elegíveis para pré-visualizar nesta unidade, armados por
## Game.begin_unit_effect_preview() enquanto uma carta com alvo
## "selected_unit" está pendente (TARGETING_UNIT). Vazio = sem preview
## disponível (unidade não é alvo válido, ou nenhuma carta pendente).
var pending_effects: Array[Dictionary] = []
var effect_armed: bool = false

## true quando o preview foi mostrado de imediato (arm_effect_preview()
## com show_now=true — efeitos "all_enemies"/"all_allies", sem escolha
## de unidade). Nesse caso o preview não deve sumir ao tirar o mouse,
## diferente do caso "selected_unit" (hover-only).
var persistent_preview: bool = false

signal selected(unit: Unit)

func setup(setup_unit: Unit) -> void:
	unit = setup_unit
	unit.changed.connect(_on_unit_changed)
	update_display()

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func update_display() -> void:
	render_display(unit.hp, unit.block)

## Preenche os labels com os valores reais, ou com o resultado
## hipotético de um efeito pendente (destination_hp/destination_block).
## HP e Block ficam vermelhos ao piorar, verdes ao melhorar, na cor
## normal sem mudança. Mostra o indicador de morte quando o HP previsto
## chegaria a zero.
func render_display(destination_hp: int, destination_block: int) -> void:
	name_label.text = unit.name
	faction_label.text = Unit.Faction.keys()[unit.faction]
	atk_label.text = "ATK: " + str(unit.attack)
	position_label.text = "Lane: " + str(unit.lane) + " | Row: " + ROW_NAMES[unit.row]

	hp_label.text = "HP: " + str(destination_hp) + "/" + str(unit.max_hp)
	hp_label.add_theme_color_override("font_color", get_delta_color(destination_hp, unit.hp))

	block_label.text = "Block: " + str(destination_block)
	block_label.add_theme_color_override("font_color", get_delta_color(destination_block, unit.block))

	death_indicator.visible = destination_hp <= 0

func get_delta_color(destination_value: int, current_value: int) -> Color:
	if destination_value < current_value:
		return DECREASE_COLOR

	if destination_value > current_value:
		return INCREASE_COLOR

	return NORMAL_COLOR

## show_now=true mostra o preview de imediato (efeitos "all_enemies"/
## "all_allies", onde não há escolha — todas as unidades afetadas
## já sabem o resultado sem precisar de hover). Por padrão só arma;
## o preview aparece ao passar o mouse (efeitos "selected_unit", onde
## faz sentido comparar unidades antes de escolher).
func arm_effect_preview(effects: Array[Dictionary], show_now: bool = false) -> void:
	pending_effects = effects
	effect_armed = true
	persistent_preview = show_now

	if show_now:
		show_effect_preview()

func disarm_effect_preview() -> void:
	pending_effects = []
	effect_armed = false
	persistent_preview = false
	update_display()

func _on_mouse_entered() -> void:
	if effect_armed:
		show_effect_preview()

func _on_mouse_exited() -> void:
	if effect_armed and not persistent_preview:
		update_display()

## Simula, na ordem em que os efeitos da carta seriam resolvidos de
## verdade (EffectSystem.execute_effect(), um efeito por vez, na ordem
## de CardData.effects), o que aconteceria com esta unidade — sem
## alterar o Unit real. Reusa CombatMath.apply_block() para o dano
## absorver bloco do mesmo jeito que a resolução real.
func show_effect_preview() -> void:
	var preview_hp = unit.hp
	var preview_block = unit.block

	for effect in pending_effects:
		var amount = effect.get("amount", 0)

		match effect.get("type", ""):
			"damage":
				var result = CombatMath.apply_block(amount, preview_block)

				preview_block = result.remaining_block
				preview_hp = max(0, preview_hp - result.remaining_damage)

			"heal":
				preview_hp = min(unit.max_hp, preview_hp + amount)

			"block":
				preview_block += amount

	render_display(preview_hp, preview_block)

func _pressed() -> void:
	selected.emit(unit)

func _on_unit_changed() -> void:
	update_display()
