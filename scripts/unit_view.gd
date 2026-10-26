class_name UnitView
extends Button

const NORMAL_COLOR = Color(1, 1, 1, 1)
const INCREASE_COLOR = Color(0.4, 1, 0.4, 1)
const DECREASE_COLOR = Color(1, 0.4, 0.4, 1)

## row: 0 = Front, 1 = Middle, 2 = Back (ver docs/playtest_3x3.md).
const ROW_NAMES = ["Front", "Middle", "Back"]

## Hover de combate (docs/playtest_3x3.md): passar o mouse numa unidade
## destaca em vermelho quem seria atingido pelo ataque dela e em verde
## quem recebe a aura dela (Guardião) — ver Game._on_unit_hover_started().
## Não tem relação com o preview de efeito de carta acima (esse já
## recolore os labels de HP/Block; isto aqui destaca o "quadro" inteiro
## de outras unidades).
const TARGET_HIGHLIGHT_COLOR = Color(0.85, 0.25, 0.25, 1)
const BUFF_HIGHLIGHT_COLOR = Color(0.35, 0.85, 0.35, 1)
const HIGHLIGHT_BG_COLOR = Color(0.16, 0.16, 0.16, 1)

## Efeito de dano da resolução de turno (Game.play_turn_replay()) — sem
## sprites de unidade ainda, isto é só um flash vermelho na própria
## UnitView de quem levou o golpe, um "pulso" de escala em quem atacou (pra
## separar visualmente atacante de alvo quando vários eventos acontecem em
## sequência) e um número de dano subindo e sumindo — ver play_hit_flash()/
## play_attack_pulse()/show_damage_popup().
const HIT_FLASH_COLOR = Color(1, 0.35, 0.35, 1)
const HIT_FLASH_DURATION = 0.3
const ATTACK_PULSE_SCALE = 1.08
const ATTACK_PULSE_DURATION = 0.15
const DAMAGE_POPUP_COLOR = Color(1, 0.35, 0.35, 1)
const DAMAGE_POPUP_RISE = 30.0
const DAMAGE_POPUP_DURATION = 0.6

@onready var name_label: Label = $Content/NameLabel
@onready var faction_label: Label = $Content/FactionLabel
@onready var hp_label: Label = $Content/HpLabel
@onready var atk_label: Label = $Content/AtkLabel
@onready var block_label: Label = $Content/BlockLabel
@onready var position_label: Label = $Content/PositionLabel
@onready var status_label: Label = $Content/StatusLabel
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

## true enquanto Game.preview_checkbox (preview de "rodar o turno" inteiro)
## está ligado — ver set_turn_preview()/disable_turn_preview(), chamados
## por Game.update_turn_preview()/clear_turn_preview(). Enquanto isto for
## true, "voltar ao normal" depois de um preview de carta (tirar o mouse de
## cima, cancelar a carta) deve restaurar ESTE preview, não os valores
## reais — ver restore_base_display(), usado no lugar de update_display()
## nesses pontos. Sem isto, passar o mouse numa carta de dano com o
## checkbox ligado e depois tirar o mouse fazia a unidade "esquecer" o
## preview de turno e voltar a mostrar HP/Block atuais.
var turn_preview_active: bool = false
var turn_preview_hp: int = 0
var turn_preview_block: int = 0

## Reaproveitada por set_highlight()/clear_highlight() — criada uma vez,
## só a border_color muda entre vermelho (alvo de ataque) e verde
## (recebendo aura).
var highlight_style: StyleBoxFlat = null

var hit_flash_tween: Tween
var attack_pulse_tween: Tween

signal selected(unit: Unit)

## Emitidos em todo mouse_entered/exited, independente de haver preview
## de carta armado — ver Game._on_unit_hover_started()/_ended().
signal hover_started(unit: Unit)
signal hover_ended(unit: Unit)

func setup(setup_unit: Unit) -> void:
	unit = setup_unit
	unit.changed.connect(_on_unit_changed)
	update_display()

func _ready() -> void:
	## Pro pulso de ataque (play_attack_pulse()) escalar a partir do centro
	## do slot, não do canto superior esquerdo — mesma técnica de Card.gd.
	pivot_offset = size / 2.0

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func update_display() -> void:
	render_display(unit.hp, unit.block)

## Mostra o preview de "rodar o turno" (Game.update_turn_preview()) e
## lembra esses valores como a baseline de "repouso" enquanto ele estiver
## ligado — ver turn_preview_active acima.
func set_turn_preview(hp: int, block: int) -> void:
	turn_preview_active = true
	turn_preview_hp = hp
	turn_preview_block = block

	render_display(hp, block)

func disable_turn_preview() -> void:
	turn_preview_active = false

	update_display()

## "Repouso" de verdade: os valores reais, a menos que o preview de turno
## esteja ligado, caso em que ele é a baseline correta a restaurar (ver
## turn_preview_active). Usado em vez de update_display() direto sempre
## que um preview de CARTA termina (hover sai de cima, carta cancelada),
## pra não "pisar" num preview de turno que já estava ativo antes.
func restore_base_display() -> void:
	if turn_preview_active:
		render_display(turn_preview_hp, turn_preview_block)
	else:
		update_display()

## Preenche os labels com os valores reais, ou com o resultado
## hipotético de um efeito pendente (destination_hp/destination_block).
## HP e Block ficam vermelhos ao piorar, verdes ao melhorar, na cor
## normal sem mudança. Mostra o indicador de morte quando o HP previsto
## chegaria a zero.
func render_display(destination_hp: int, destination_block: int) -> void:
	name_label.text = unit.name
	faction_label.text = Unit.Faction.keys()[unit.faction]
	atk_label.text = "ATK: " + str(unit.get_effective_attack())
	position_label.text = "Lane: " + str(unit.lane) + " | Row: " + ROW_NAMES[unit.row]

	hp_label.text = "HP: " + str(destination_hp) + "/" + str(unit.max_hp)
	hp_label.add_theme_color_override("font_color", get_delta_color(destination_hp, unit.hp))

	block_label.text = "Block: " + str(destination_block)
	block_label.add_theme_color_override("font_color", get_delta_color(destination_block, unit.block))

	## Só ocupa espaço na célula quando há algum status ativo — a maioria
	## das unidades não tem nenhum, e VBoxContainer ignora filhos invisíveis
	## no layout, então isto não altera o tamanho das células sem status
	## (ver docs/MECHANICS_EXECUTION_PLAN.md Etapa 1).
	status_label.text = unit.get_status_summary()
	status_label.visible = not status_label.text.is_empty()

	## Garante que um preview_attack() anterior nunca fique "preso" com a
	## cor de delta depois de um update de verdade (ex: outra mudança
	## qualquer nesta unidade enquanto Linha de Frente estava armada) —
	## fora de preview_attack(), o ATK é sempre mostrado na cor normal.
	atk_label.add_theme_color_override("font_color", NORMAL_COLOR)

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
	restore_base_display()

func _on_mouse_entered() -> void:
	if effect_armed:
		show_effect_preview()

	hover_started.emit(unit)

func _on_mouse_exited() -> void:
	if effect_armed and not persistent_preview:
		restore_base_display()

	hover_ended.emit(unit)

## color = TARGET_HIGHLIGHT_COLOR (alvo de ataque) ou BUFF_HIGHLIGHT_COLOR
## (recebendo aura) — troca só a cor da borda, reaproveitando o mesmo
## StyleBoxFlat. Sobrescreve o stylebox "normal" do Button; clear_
## highlight() remove a sobrescrita, voltando ao tema default.
func set_highlight(color: Color) -> void:
	if highlight_style == null:
		highlight_style = StyleBoxFlat.new()
		highlight_style.bg_color = HIGHLIGHT_BG_COLOR
		highlight_style.set_corner_radius_all(4)
		highlight_style.set_border_width_all(3)

	highlight_style.border_color = color

	add_theme_stylebox_override("normal", highlight_style)

func clear_highlight() -> void:
	remove_theme_stylebox_override("normal")

## Preview do ATK de cartas como Linha de Frente (docs/playtest_3x3.md
## seção 5) — modify_attack() não é um "efeito" no formato que
## show_effect_preview() simula (só dano/cura/bloqueio), então isto é um
## caminho à parte, mas reaproveita get_delta_color() pro mesmo esquema
## de cor visual.
func preview_attack(new_attack: int) -> void:
	atk_label.text = "ATK: " + str(new_attack)
	atk_label.add_theme_color_override("font_color", get_delta_color(new_attack, unit.attack))

func clear_attack_preview() -> void:
	atk_label.text = "ATK: " + str(unit.get_effective_attack())
	atk_label.add_theme_color_override("font_color", NORMAL_COLOR)

## Flash vermelho rápido — chamado em quem LEVOU um ataque durante a
## reprise de "Rodar turno" (Game.play_turn_replay()). Guarda o tween numa
## var própria (em vez de só criar um novo) porque várias unidades podem
## atacar o mesmo alvo no mesmo turno — sem matar o tween anterior, dois
## tweens brigariam pela mesma propriedade "modulate" ao mesmo tempo.
func play_hit_flash() -> void:
	if hit_flash_tween != null:
		hit_flash_tween.kill()

	modulate = HIT_FLASH_COLOR

	hit_flash_tween = create_tween()
	hit_flash_tween.tween_property(self, "modulate", NORMAL_COLOR, HIT_FLASH_DURATION)

## Pulso rápido de escala — chamado em quem DEU um ataque durante a
## reprise de turno, só pra separar visualmente "quem agiu" de "quem foi
## atingido" quando vários eventos se sucedem rápido.
func play_attack_pulse() -> void:
	if attack_pulse_tween != null:
		attack_pulse_tween.kill()

	scale = Vector2(ATTACK_PULSE_SCALE, ATTACK_PULSE_SCALE)

	attack_pulse_tween = create_tween()
	attack_pulse_tween.tween_property(self, "scale", Vector2.ONE, ATTACK_PULSE_DURATION)

## Número de dano subindo e sumindo por cima do slot — um Label avulso,
## criado e destruído a cada chamada (não há porque reaproveitar: vários
## podem se acumular se a mesma unidade levar mais de um golpe no turno).
func show_damage_popup(amount: int) -> void:
	if amount <= 0:
		return

	var popup = Label.new()

	popup.text = "-%d" % amount
	popup.add_theme_color_override("font_color", DAMAGE_POPUP_COLOR)
	popup.add_theme_font_size_override("font_size", 20)
	popup.z_index = 50
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.position = size * 0.5 - Vector2(10, 10)

	add_child(popup)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - DAMAGE_POPUP_RISE, DAMAGE_POPUP_DURATION)
	tween.tween_property(popup, "modulate:a", 0.0, DAMAGE_POPUP_DURATION)
	tween.chain().tween_callback(popup.queue_free)

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
