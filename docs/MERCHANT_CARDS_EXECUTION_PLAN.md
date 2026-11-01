# MERCHANT_CARDS_EXECUTION_PLAN.md

## Objetivo

Trocar as listas de texto de carta/artefato por **cartas de verdade**, do
mesmo jeito que aparecem na mão em combate (arte, nome, custo, descrição,
preview de ATK/HP de invocação). No mercador, elas ficam num grid de **3
colunas**, com preço e botão de compra embaixo de cada carta.

Junto disso, como no Monster Train:

- **Tooltip de palavras-chave no hover.** Ao passar o mouse numa carta,
  aparecem blocos extras ao lado dela explicando cada mecânica que a carta
  usa. Uma carta que aplica Poison ganha um bloco "Poison: …", Fúria
  Dobrada ganha um bloco "Strength: …".
- **Destaque colorido e em negrito no texto.** Cada palavra-chave define no
  próprio JSON a cor em que aparece. Sempre que ela surge numa descrição,
  aparece nessa cor e em negrito (ex.: Poison sempre em roxo).

O tooltip e o destaque valem em todo lugar onde uma carta ou um artefato é
mostrado: **mercador, mão em combate e DeckBuilder**.

O plano traz ainda duas mudanças de conteúdo decididas junto com esta
feature:

- **Linguagem de gamer brasileiro:** o texto é em português, mas os termos
  de mecânica que o jogador usa em inglês ficam em inglês ("aplica Poison
  3", "On Hit: …"). Um termo só fica em português se for mais comum assim.
- **ATK/HP de unidade na escala do jogador**: os stats dos JSON são
  dobrados, e o combate passa a **dividir os inimigos pela metade** em vez
  de dobrar os aliados. Assim, o que a carta mostra é exatamente o que o
  jogador vê na unidade dele em combate.

Este plano é **paralelo** ao `CAMPAIGN_EXECUTION_PLAN.md` e ao
`CARDS_EXECUTION_PLAN.md`. A disciplina é a mesma: um passo de cada vez, e
parar para o usuário testar no editor antes do próximo.

---

# Levantamento (base das decisões)

Feito em 2026-11-01 sobre `scripts/merchant.gd`, `scripts/deck_builder.gd`,
`scripts/card.gd`, `scenes/card.tscn`, `scripts/battle_state.gd`,
`data/cards/`, `data/units/` e `data/artifacts/`.

- **Merchant hoje** (`Merchant.render_rows()`): uma `VBoxContainer` dentro de
  um `ScrollContainer`, com uma linha `HBoxContainer` por item (texto com
  nome/mana/descrição, "Você tem: N", botão "Comprar — P ouro"). Artefatos
  e cartas usam o mesmo `create_row()`. O estado é atualizado por
  `refresh_rows()` em `CampaignState.changed`, sem recriar as linhas.
- **DeckBuilder hoje**: coleção à esquerda e deck à direita, ambas listas de
  texto. Na coleção, cada linha tem nome + mana, "no deck: x / y" e "+". No
  deck, cada linha tem nome ×N e "−". Toda edição é refeita em `refresh()`.
  O artefato do deck é um `OptionButton` + `Label` com a descrição
  (`ArtifactBar`).
- **`Card` (`card.tscn`)** é um `Control` de 220×335 com posição livre. O
  hover anima `position` a partir de `rest_position` (sobe `HOVER_LIFT`,
  escala `HOVER_SCALE`) e muda o `z_index`. Ele foi feito para a mão, que
  posiciona as cartas manualmente (`Game.layout_hand()`). **Dentro de um
  `Container` isso brigaria com o layout**, porque o container reposiciona
  o filho. Clicar emite `played(card)`.
- A descrição da carta é um **`Label`** (`DescriptionLabel`, com
  `LabelSettings` de fonte 10, centralizado, autowrap). Um `Label` não
  suporta cor por trecho. Para isso é preciso um **`RichTextLabel` com
  BBCode**.
- `Card.setup(card_data, unit_database)` já aceita um `UnitDatabase`
  opcional para o preview "ATK x / HP y" de invocação. **`Main` não tem um
  `UnitDatabase`**: só o `Game` carrega o dele (`Game._ready()`).
- **Stats:** `BattleState.create_unit()` multiplica ATK/HP de toda unidade
  aliada por `ALLY_STAT_MULTIPLIER = 2` e **depois** soma os bônus de
  artefato (`ally_max_hp_bonus`/`ally_attack_bonus`). O
  `SummonPreviewLabel` mostra o valor base da `UnitData`, ou seja, metade
  do que o aliado tem de verdade em combate.
- **Artefatos** (`data/artifacts/`): `id`, `name`, `description` e um
  `effect` (`ally_max_hp`, `ally_attack`, `max_mana`, `hand_size`). Nenhum
  desses efeitos é uma mecânica do glossário hoje, então o tooltip de
  artefato começa vazio. O destaque de texto funciona mesmo assim.
- O viewport é 1800×980. Três colunas de 220 px mais os espaçamentos ocupam
  ~720 px, o que deixa espaço lateral de sobra para o tooltip.
- **Mecânicas que uma carta pode referenciar**, tiradas dos dados (não do
  texto):

  | Fonte no JSON | Palavra-chave |
  |---|---|
  | `apply_status` / `remove_status` / `double_status` com `status` | `strength`, `weakness`, `poison`, `burn`, `stun` |
  | `detonate_poison` | `poison` |
  | `block`, `shield_bash` | `block` |
  | `cleanse` | `cleanse` |
  | `summon` → `UnitData.initial_statuses` | o status (ex.: Berserker → `strength`) |
  | `summon` → `UnitData.triggers[].event` | `on_hit`, `on_death`, `on_kill`, `on_summon`, `on_move`, `on_attack`, `on_card_played` |
  | `summon` → `UnitData.triggers[].effect` | o mesmo mapeamento das linhas acima (ex.: Venenoso → `poison`) |

- **Termos no conteúdo hoje:** os status já aparecem em inglês nas descrições
  (Strength, Poison, Block, Weakness, Burn, Stun, Cleanse), às vezes em
  minúscula ("stacks de strength"). `Unit.STATUS_DISPLAY_NAMES` também
  está em inglês. **Os eventos estão em português** ("Ao acertar" ×5, "Ao
  morrer" ×5, "Ao matar" ×2, "Ao ser invocado" ×2), e há 2 "bloqueio" em
  português.
- `TargetSystem.PATTERN_DESCRIPTIONS` já descreve cada padrão de ataque em
  português, só que via `describe_pattern()`, que é método de instância.

## Decisões de design deste plano

1. **As palavras-chave do tooltip saem de `effects`, nunca do texto da
   descrição.** Os efeitos são a fonte de verdade sobre o que a carta faz.
2. **O glossário é conteúdo, então fica em JSON** (`data/keywords/`), com
   `KeywordDatabase` no mesmo molde de `CardDatabase`/`ArtifactDatabase`.
   Cada entrada tem nome, explicação e **cor de destaque**.
3. **Os nomes das mecânicas ficam em inglês, e a explicação em português.**
   Ex.: título "Poison", explicação "No fim do turno, a unidade sofre dano
   igual aos stacks de Poison e perde 1 stack." Nenhum termo do glossário
   inicial é mais comum em português no vocabulário do jogador, então
   todos ficam em inglês, incluindo os eventos (On Hit, On Death…).
4. **Os nomes de carta não mudam.** Os que estão em inglês ("Poison Dart",
   "Enrage") continuam em inglês, e os em português ("Fúria Dobrada",
   "Fortificar") continuam em português.
5. **O destaque colorido é feito por casamento de texto.** O nome do
   glossário (e apelidos opcionais) é procurado na descrição e embrulhado em
   `[b][color]`. Isso é independente do tooltip: pinta qualquer descrição
   que cite a palavra, mesmo que o efeito não a gere.
6. **A derivação de palavras-chave é domínio, e o BBCode/tooltip é
   apresentação.** `CardData.get_keyword_ids()` devolve ids, sem tocar em UI.
   Montar BBCode e desenhar e posicionar blocos fica nos Nodes.
7. **O tooltip é um componente reutilizável** (`KeywordTooltip`), que sabe
   se posicionar ao lado de qualquer `Control`. `Card` e `ArtifactCard` só
   pedem "mostra ao meu lado" / "esconde".
8. **Dentro de um `Container`, o `Card` não vai direto.** Ele fica num
   "holder" (`Control` com `custom_minimum_size` do tamanho da carta), com
   `rest_position = Vector2.ZERO`. Assim o hover continua funcionando sem
   brigar com o container. Isso vale para o grid do mercador e para o do
   DeckBuilder.
9. **Os stats dos JSON ficam na escala do jogador.** Todo `attack`/`max_hp`
   em `data/units/` é dobrado uma vez. Em combate, aliados usam o valor do
   JSON como está, e inimigos usam metade. O preview de invocação e o
   tooltip mostram o valor do JSON, que é o que o jogador vai ver.
10. **Posição/movimento não ganham explicação por enquanto** (Front/Back,
    lane, auras, `advance_attack_bonus`, `back_row_attack_bonus`).

---

# Roadmap

```text
Passo 1  — Stats na escala do jogador                (JSON + BattleState)
Passo 2  — Grid de cartas reais no Merchant          (cena + script)
Passo 3  — Glossário de palavras-chave + derivação   (JSON + domínio, sem UI)
Passo 4  — Padronizar os termos no conteúdo          (conteúdo)
Passo 5  — KeywordTooltip no hover do Card           (apresentação)
Passo 6  — Bloco da unidade invocada no tooltip      (apresentação)
Passo 7  — Destaque colorido e em negrito            (apresentação)
Passo 8  — Tooltip e destaque na mão do combate      (ligação + ajustes)
Passo 9  — ArtifactCard + artefatos em grid no Merchant
Passo 10 — DeckBuilder com cartas e artefato visuais
Passo 11 — Documentação                              (ARCHITECTURE/AGENTS)
```

O Passo 1 vem primeiro porque é independente e corrige o número que o
preview vai mostrar no grid do Passo 2.

---

## Passo 1 — Stats na escala do jogador

**Meta:** o combate fica numericamente **idêntico** ao de hoje, mas os JSON de
unidade passam a guardar o valor que o aliado tem em combate.

- `data/units/*.json`: dobrar `attack` e `max_hp` de **todas** as
  unidades, inclusive as que hoje só aparecem como inimigas (bandit,
  goblin, dragon…), já que unidade não tem facção. Os outros números **não
  mudam**: `initial_statuses`, `aura_adjacent_ally_max_hp_bonus`,
  `back_row_attack_bonus`, `advance_attack_bonus` e os valores dos
  `triggers`. Eles nunca foram multiplicados.
- `BattleState`: `ALLY_STAT_MULTIPLIER` é trocado por
  `ENEMY_STAT_DIVISOR = 2`. Em `create_unit()`, quem é `ENEMY` usa
  `max(1, valor / ENEMY_STAT_DIVISOR)` em ATK e HP. Os bônus de artefato
  continuam somados só nos aliados, como hoje. O comentário que explica a
  compensação das waves vai junto para a constante nova.
- Como todo valor do JSON fica par, a metade do inimigo é exatamente o
  valor de hoje. Uma unidade nova com valor ímpar arredonda para baixo, e
  isso vai documentado no comentário.
- Conferir as descrições de unidades que citem ATK/HP numérico. Se houver,
  ajustar para a nova escala.
- Conferir quem mais lê `UnitData.attack`/`max_hp` direto, fora do
  `create_unit()`: o debug de spawn no `Game` e o `SummonPreviewLabel`.

**Teste:** headless, comparar ATK/HP de aliado e de inimigo criados por
`create_unit()` antes e depois (tem que dar igual). No editor, um combate
normal: o preview "ATK/HP" da carta de invocação agora bate com o
`UnitView` da unidade invocada. Com artefato de +HP/+ATK equipado, o bônus
continua aparecendo só uma vez.

## Passo 2 — Grid de cartas reais no Merchant

**Meta:** a seção "Cartas" do mercador mostra cartas `card.tscn` num grid de 3
colunas, cada uma com "Você tem: N" e "Comprar — P ouro" embaixo. Os
artefatos ficam em lista até o Passo 9.

- `Main` passa a carregar um `UnitDatabase` uma vez (como já faz com
  `CardDatabase`) e o repassa ao `Merchant.setup()`. Assim a carta de
  invocação mostra o preview ATK/HP, igual no combate. O `Game` continua
  carregando o próprio, porque também abre direto pelo editor.
- `merchant.tscn`: `Rows` continua sendo a `VBoxContainer` das seções. A
  seção "Cartas" passa a criar um `GridContainer` (`columns = 3`,
  centralizado com `size_flags_horizontal = SHRINK_CENTER`, separação
  ~24 px horizontal / ~32 px vertical).
- `Merchant.create_card_tile(card_id)` substitui `create_card_row()`: uma
  `VBoxContainer` com
  - o holder `Control` (`custom_minimum_size = Card.size`) contendo a
    instância de `card.tscn` com `setup(card_data, unit_database)`;
  - uma `HBoxContainer` com o label "Você tem: N" e o botão de compra.
  `card_buy_buttons`/`card_owned_labels` continuam iguais, então
  `refresh_rows()` não muda.
- O clique na carta (`played`) **não é conectado**: comprar continua sendo
  pelo botão, para evitar compra acidental.
- **Corte do hover:** o `ScrollContainer` corta o que sair da área dele
  (`clip_contents`). A carta da primeira linha, ao subir `HOVER_LIFT` e
  escalar, pode ser cortada no topo. Há duas saídas: dar margem superior ao
  grid ≥ `HOVER_LIFT`, ou expor `hover_lift` no `Card` (padrão
  `HOVER_LIFT`) e usar um valor menor no mercador. Começar pela margem; a
  segunda só se ficar ruim.
- O custo de mana fica sempre com a cor normal. `set_affordable()` é sobre
  mana em combate, não sobre ouro: quem indica "não dá pra pagar" no
  mercador é o botão desabilitado.
- Ordem: a de hoje (preço crescente, depois nome).

**Teste no editor:** entrar no mercador de cartas pelo mapa. As cartas
aparecem com arte, custo e preview de invocação. O hover cresce e sobe sem
ser cortado nem empurrar o layout. Comprar atualiza "Você tem" e o ouro, e
os botões ficam desabilitados sem ouro. O scroll funciona com muitas
cartas. Esc/Voltar continua voltando ao mapa.

## Passo 3 — Glossário de palavras-chave + derivação

**Meta:** dado um `CardData` (ou `ArtifactData`), saber quais palavras-chave
ele usa, já com nome, explicação e cor. Ainda sem nada na tela.

- `data/keywords/<id>.json`, um por palavra-chave:
  ```json
  {
    "id": "poison",
    "name": "Poison",
    "aliases": ["envenenado", "envenenada"],
    "color": "#7b2fbf",
    "description": "No fim do turno, a unidade sofre dano igual aos stacks de Poison e perde 1 stack."
  }
  ```
  - `name`: nome exibido, em inglês. É o título do bloco do tooltip e o
    texto procurado no destaque.
  - `aliases` (opcional): outras formas que também recebem destaque.
    Começa vazio na maioria. Serve para flexões em português que alguma
    descrição use.
  - `color` (opcional): cor do destaque, em hex. Sem `color`, a
    palavra-chave tem tooltip mas não é pintada.
  - `description`: a regra **como o código faz hoje**, em português (ver a
    seção "Stats, modifiers and statuses" do ARCHITECTURE: Poison decai 1,
    Burn é consumido inteiro, Stun pula um ataque, Block nunca expira…).
- Ids, nomes e cores iniciais. As cores foram escolhidas por este plano e o
  usuário valida no teste. Elas são **escuras** o bastante para contrastar
  com a moldura clara da carta, onde o texto é quase preto. Os eventos
  dividem uma cor neutra comum, para se distinguirem dos status sem
  competir com eles.

  | id | Nome | Cor |
  |---|---|---|
  | `strength` | Strength | vermelho `#b03a2e` |
  | `weakness` | Weakness | cinza-azulado `#566573` |
  | `poison` | Poison | roxo `#7b2fbf` |
  | `burn` | Burn | laranja `#c0560f` |
  | `stun` | Stun | amarelo-escuro `#9a7d0a` |
  | `block` | Block | azul `#1f6fb2` |
  | `cleanse` | Cleanse | verde-água `#138d75` |
  | `on_hit` | On Hit | dourado-escuro `#7d5a1e` |
  | `on_death` | On Death | dourado-escuro `#7d5a1e` |
  | `on_kill` | On Kill | dourado-escuro `#7d5a1e` |
  | `on_summon` | On Summon | dourado-escuro `#7d5a1e` |
  | `on_move` | On Move | dourado-escuro `#7d5a1e` |
  | `on_attack` | On Attack | dourado-escuro `#7d5a1e` |
  | `on_card_played` | On Card Played | dourado-escuro `#7d5a1e` |

- `KeywordData` (`id`, `name`, `aliases`, `color: Color`, `has_color`,
  `description`, `from_dict()`) e `KeywordDatabase.load_keywords()`,
  copiando o padrão de `CardDatabase`. Cor inválida gera `push_warning` e
  fica sem cor.
- `CardData.get_keyword_ids(unit_database: UnitDatabase = null) ->
  Array[String]`: percorre `effects` com o mapeamento do levantamento. Para
  `summon`, se `unit_database` vier, inclui também os
  `initial_statuses`/`triggers` da unidade. O resultado sai sem repetição,
  na ordem da primeira aparição. O mapeamento de um efeito fica num
  helper estático (`CardData.keywords_of_effect(effect)`), reutilizado
  pelo efeito da carta, pelo `effect` de cada trigger e por
  `ArtifactData.get_keyword_ids()`. Esta última devolve vazio para os 4
  artefatos de hoje, mas já fica pronta para artefatos com mecânica.
- Um id sem entrada no glossário é ignorado em silêncio na hora de mostrar.
  Isso deixa a derivação tolerante a conteúdo novo.

**Teste:** headless, carregar todos os cards e imprimir `id → keyword ids`.
Conferir à mão: `poison_dart → [poison]`, `double_strength → [strength]`,
`summon_venomous → [on_hit, poison]`, `summon_berserker → [strength]`,
`detonate_toxin → [poison]`, `fortify → [block]`. Conferir também que
todo id derivado de todas as cartas existe no glossário.

## Passo 4 — Padronizar os termos no conteúdo

**Meta:** em todo texto visível, as mecânicas aparecem com o mesmo nome do
glossário. Isso garante que o destaque do Passo 7 encontre todas elas.

- Passada nos `description` de `data/cards/`, `data/units/`,
  `data/events/` e `data/artifacts/`:
  - eventos: "Ao acertar um ataque, aplica Poison 2 no alvo" → "On Hit:
    aplica Poison 2 no alvo atingido". Da mesma forma, "Ao morrer" → "On
    Death:", "Ao matar" → "On Kill:", "Ao ser invocado" → "On Summon:".
  - "bloqueio" → "Block".
  - capitalização: "stacks de strength" → "stacks de Strength", e o mesmo
    para os outros status.
- **Nomes de carta não mudam** (decisão 4). Ids também não.
- `Unit.STATUS_DISPLAY_NAMES` já está em inglês e não muda. O glossário é
  a referência, e esta tabela deve bater com ele.

**Teste:** `grep` por "Ao acertar"/"Ao morrer"/"Ao matar"/"Ao ser
invocado"/"bloqueio" nos JSON não acha mais nada. Ler as descrições
alteradas no editor (mercador do Passo 2) para conferir que ficaram
naturais.

## Passo 5 — KeywordTooltip no hover do Card

**Meta:** no mercador, o hover numa carta mostra ao lado dela um bloco por
palavra-chave (título + explicação), empilhados na vertical.

- `scenes/keyword_tooltip.tscn` + `scripts/keyword_tooltip.gd`:
  `VBoxContainer` com um `PanelContainer` por bloco (título em negrito na
  cor da palavra-chave, descrição com autowrap, largura fixa ~240 px). O
  fundo do bloco é **claro**, no tom da moldura da carta, para as mesmas
  cores de destaque funcionarem nos dois lugares. `mouse_filter = IGNORE`
  em tudo, senão o tooltip "rouba" o mouse e a carta pisca entre
  hover/não-hover. `top_level = true` e `z_index` alto, para não herdar a
  escala do hover, não ser cortado por containers e ficar por cima de
  cartas vizinhas. API:
  - `set_keywords(keywords: Array[KeywordData])`;
  - `show_beside(target: Control)`: à direita do `target`, alinhado ao
    topo, ou à esquerda se passar da borda direita do viewport. Na
    vertical, é preso dentro do viewport. O cálculo usa o
    `get_global_rect()` do momento, então funciona com scroll e com a carta
    em movimento na mão;
  - `hide_tooltip()`.
  Com a lista vazia, `show_beside()` não mostra nada.
- `Card.setup(card_data, unit_database = null, keyword_database = null)`:
  sem `keyword_database`, não há tooltip nem destaque, e o comportamento
  atual continua intacto. Com ele, o `Card` cria um `KeywordTooltip` filho
  e resolve os `KeywordData` uma vez no `setup()`.
- Visibilidade no `Card`: `show_beside(self)` em `_on_mouse_entered()`.
  `hide_tooltip()` em `_on_mouse_exited()`, em `set_pending(true)` e em
  `play_discard_exit()`. Nada aparece quando o hover é ignorado
  (`any_card_pending`/`is_leaving`).
- `Main` carrega o `KeywordDatabase` e o repassa ao `Merchant`.

**Teste no editor:** hover em Poison Dart mostra "Poison". Fúria Dobrada
mostra "Strength". Uma carta sem mecânica especial (ex.: Strike) não mostra
tooltip. Na coluna da direita, o tooltip vira para a esquerda. Na última
linha visível, ele não sai da tela por baixo. Rolar e passar o mouse de
novo deixa o tooltip na posição certa.

## Passo 6 — Bloco da unidade invocada no tooltip

**Meta:** como no Monster Train, uma carta de invocação mostra também um
bloco com a unidade: nome, ATK/HP, padrão de ataque e o texto dela. As
palavras-chave da unidade vêm logo abaixo.

- `KeywordTooltip` ganha um bloco de cabeçalho opcional
  (`set_unit(unit_data, pattern_text)`) desenhado antes dos blocos de
  palavra-chave.
- O padrão de ataque usa `TargetSystem.PATTERN_DESCRIPTIONS`. Tornar
  `describe_pattern()` `static`: ela não usa estado da instância, e assim
  o `Card` não precisa de um `TargetSystem`/`BattleState`.
- ATK/HP mostrados: os da `UnitData`, que depois do Passo 1 são os que o
  aliado tem em combate (fora bônus de artefato).

**Teste no editor:** hover em Invocar Venenoso mostra o bloco Venenoso
(ATK/HP, "Mira o primeiro inimigo da própria lane…", descrição), depois
"On Hit" e "Poison". Hover em Invocar Berserker mostra a unidade e
"Strength".

## Passo 7 — Destaque colorido e em negrito

**Meta:** toda palavra-chave com `color` aparece **em negrito e na cor dela**
na descrição da carta, nas descrições do tooltip e no texto da unidade do
Passo 6.

- `card.tscn`: `DescriptionLabel` vira `RichTextLabel` (`bbcode_enabled`,
  `fit_content`, `scroll_active = false`, `mouse_filter = IGNORE`, autowrap).
  Fonte, tamanho, cor e espaçamento são reproduzidos via
  `theme_override_*`, porque `LabelSettings` não vale para
  `RichTextLabel`. A fonte em negrito (`bold_font`) é a mesma família em
  peso bold. O texto vai centralizado com `[center]` e mantém o visual
  atual.
- `scripts/keyword_text.gd` (`class_name KeywordText`, estático, camada de
  apresentação): `to_bbcode(text: String, keyword_database:
  KeywordDatabase) -> String`.
  1. Escapa os `[` do texto original, para que conteúdo não vire BBCode
     sem querer.
  2. Para cada palavra-chave com cor, monta um `RegEx` com `name` +
     `aliases`, sem diferenciar maiúsculas, e com fronteira de palavra que
     respeita acentos (`(?<!\p{L})` … `(?!\p{L})`, porque `\b` falha com
     letras acentuadas). Os termos mais longos são testados primeiro, para
     "On Card Played" não ser cortado errado por outro termo.
  3. Inclui no trecho destacado o número que vier logo em seguida ("Poison
     3" inteiro).
  4. Embrulha em `[b][color=#hex]…[/color][/b]`.
  Os regex são compilados uma vez e guardados no `KeywordDatabase` ou num
  cache estático do `KeywordText`, não a cada carta.
- `Card.setup()` usa `KeywordText.to_bbcode()` quando tem
  `keyword_database`, e texto puro quando não tem. `KeywordTooltip` usa o
  mesmo helper nas descrições dos blocos e da unidade. Assim, "Cleanse:
  remove Poison, Burn…" também sai colorido.
- O nome da carta **não** é destacado ("Poison Dart" no título fica na cor
  normal), só a descrição.

**Teste no editor:** Poison Dart com "Poison 3" em roxo e negrito. Fúria
Dobrada com "Strength" destacado, na descrição e no título do bloco do
tooltip. Uma palavra que só contém o termo dentro de outra (ex.:
"Blocker", "Stunned", se não forem apelidos) **não** é destacada.
Maiúscula/minúscula casa. Conferir que a descrição continua centralizada e
cabendo na moldura com o negrito.

## Passo 8 — Tooltip e destaque na mão do combate

**Meta:** a mesma explicação e o mesmo destaque nas cartas da mão.

- `Game` carrega um `KeywordDatabase` (como faz com o `unit_database`, pois
  abre sozinho pelo editor) e passa em `card.setup()` no `render_hand()`.
- Conferir os casos da mão: cartas sobrepostas (o tooltip fica por cima
  das vizinhas pelo `z_index` do Passo 5); carta pendente aguardando alvo
  (sem tooltip); carta saindo da mão (sem tooltip); a mão fica embaixo,
  então o tooltip tende a subir (o clamp vertical do Passo 5 resolve isso).
- O preview de turno e o replay não mudam.

**Teste no editor:** combate pelo mapa e direto pela cena `game.tscn`.
Hover nas cartas da mão, inclusive as das pontas. Jogar uma carta com
alvo (o tooltip some e não volta enquanto estiver pendente). Cancelar com
Esc e passar o mouse de novo. As descrições destacadas aparecem na mão.

## Passo 9 — ArtifactCard + artefatos em grid no Merchant

**Meta:** artefatos aparecem como cartas, com arte, nome e descrição
destacada, no mesmo grid de 3 colunas do mercador.

- `scenes/artifact_card.tscn` + `scripts/artifact_card.gd` (`class_name
  ArtifactCard`): mesmo tamanho e moldura do `Card`, mas **sem custo** e sem
  preview de invocação, com uma marca visual de "Artefato" (rótulo pequeno
  no rodapé ou outra cor de moldura, a decidir no teste). A arte segue a
  mesma convenção, `res://resources/images/artifacts/<id>.png`, e sem
  arquivo some como no `Card`. A descrição é um `RichTextLabel` com
  `KeywordText.to_bbcode()`.
- Hover: o mesmo crescer/subir do `Card` (escala + elevação a partir de
  `rest_position`) e `KeywordTooltip.show_beside(self)` com
  `ArtifactData.get_keyword_ids()`. Ele é vazio hoje, então não aparece
  tooltip, só o destaque. Não há sinal de clique.
- Para não duplicar a animação de hover entre `Card` e `ArtifactCard`: se a
  cópia ficar em poucas linhas (`animate_to()` + entrar/sair), copiar e
  comentar a origem. Se crescer, extrair para um helper. Decidir na hora
  pelo tamanho real.
- `Merchant`: a seção "Artefatos" usa `GridContainer` de 3 colunas com
  tiles `ArtifactCard` + "Já possui" + botão. Mesmo holder e mesma lógica
  de `refresh_rows()`.

**Teste no editor:** mercador de artefatos mostra os 4 como cartas. O hover
cresce sem cortar. Comprar desabilita com "Já possui". Mercador misto
(cartas + artefatos) mostra os dois grids.

## Passo 10 — DeckBuilder com cartas e artefato visuais

**Meta:** a coleção do DeckBuilder vira um grid de cartas com tooltip e
destaque, e o artefato equipado aparece como `ArtifactCard`.

- `Main` repassa `UnitDatabase` e `KeywordDatabase` ao `DeckBuilder.setup()`.
- **Coleção (coluna esquerda):** `Rows` (`VBoxContainer`) vira um
  `GridContainer` de 3 colunas. Cada tile é o holder com o `Card` + "no
  deck: x / y" + botão "+" (desabilitado como hoje). **Clicar na carta
  também adiciona uma cópia** (`played` → `_on_add_pressed`), como é comum
  em deckbuilders. O botão continua lá para quem preferir. Cada cópia
  extra só muda o contador, não duplica a carta no grid.
- **Deck (coluna direita):** continua uma lista compacta (nome ×N + "−"),
  porque um deck de 20–30 cartas em tamanho cheio não caberia ao lado da
  coleção. Hover numa linha mostra o `KeywordTooltip` da carta ao lado da
  linha (sem a carta inteira). Dá para trocar por um preview da carta
  inteira depois do teste, se fizer falta.
- `refresh()` hoje recria todas as linhas a cada "+"/"−". Com cartas
  instanciadas, isso passa a recriar dezenas de `Card`, e o hover pode
  "piscar" sob o mouse. Para evitar, a coleção é criada uma vez (como o
  mercador), e `refresh()` só atualiza contadores/botões. A lista do deck
  pode continuar sendo recriada.
- **Artefato:** o `OptionButton` continua sendo o seletor. O
  `ArtifactDescription` (`Label`) é trocado por um `ArtifactCard` do
  artefato selecionado (ou nada, em "Nenhum"), possivelmente em escala
  menor para não empurrar as colunas, a ajustar no teste.
- Largura: a coluna da coleção precisa de ~720 px para 3 colunas. Com 1800
  px de viewport isso cabe junto da coluna do deck. Se apertar, a coluna
  do deck fica com largura fixa e a coleção expande.

**Teste no editor:** abrir "Editar" e "Criar novo deck" pelo overworld.
Clicar na carta e no "+" adiciona, e "−" remove. O contador "no deck"
atualiza sem recriar a carta sob o mouse. O tooltip aparece na coleção e
nas linhas do deck. Trocar o artefato atualiza o `ArtifactCard`.
Salvar/Cancelar/Apagar/Esc continuam iguais.

## Passo 11 — Documentação

- `ARCHITECTURE.md`:
  - "Units": stats na escala do jogador e `ENEMY_STAT_DIVISOR` no lugar de
    `ALLY_STAT_MULTIPLIER`. Atualizar também as outras menções a
    `ALLY_STAT_MULTIPLIER` (seções de artefatos e battle flow).
  - "Gold and merchants" e "DeckBuilder": grids de cartas, holder,
    `ArtifactCard`, `UnitDatabase`/`KeywordDatabase` vindos de `Main`.
  - "Cards": `get_keyword_ids()`, glossário, `KeywordTooltip`,
    `KeywordText` e o `DescriptionLabel` como `RichTextLabel`.
  - "Data-driven design": a regra de linguagem (texto em português, termos
    de mecânica em inglês com o nome exato do glossário, nomes de carta
    livres).
  - Estrutura de pastas (`data/keywords/`, `keyword_tooltip.tscn`,
    `artifact_card.tscn`, `resources/images/artifacts/`) e lista de cenas.
- `CARDS_EXECUTION_PLAN.md`/`CAMPAIGN_EXECUTION_PLAN.md`: nota curta onde
  citam `ALLY_STAT_MULTIPLIER`.
- `AGENTS.md`: atualizar "Current status" e acrescentar a regra de
  linguagem do conteúdo.

---

# Decisões já tomadas com o usuário (2026-11-01)

- **Linguagem:** texto em português, mas termos de mecânica comuns em inglês
  ficam em inglês (Poison, Strength, Block, On Hit…). Um termo só vai para
  o português se for mais comum assim. Nomes de carta não mudam.
- **Posição/movimento** ficam sem explicação no tooltip por enquanto.
- **ATK/HP:** dobrar tudo nos JSON e, em combate, dividir os inimigos pela
  metade em vez de dobrar os aliados.
- **Destaque:** cor definida no JSON de cada palavra-chave, mais negrito,
  aplicados sempre que ela aparece numa descrição. As cores iniciais são
  deste plano (Passo 3), e o usuário ajusta no teste.
- **Artefatos e DeckBuilder** também mostram cartas e tooltip (Passos 9 e
  10).

# Detalhes a confirmar no teste (não bloqueiam)

- Cores finais da tabela do Passo 3.
- Marca visual que distingue um `ArtifactCard` de um `Card` (Passo 9).
- Tamanho do `ArtifactCard` no DeckBuilder e se a lista do deck precisa de
  preview da carta inteira no hover (Passo 10).
