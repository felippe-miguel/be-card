# Gamejam — Architecture

## 1. Objetivo

Projeto de um deckbuilder de combate inspirado estruturalmente em jogos como Monster Train e Slay the Spire.

A prioridade inicial é construir um motor de combate data-driven e extensível. Depois que a base estiver funcionando, regras, conceitos e identidade do jogo serão modificados para criar uma experiência própria.

---

## 2. Filosofia de arquitetura

O projeto separa:

- **Dados/conteúdo**: JSONs que descrevem cartas, unidades e batalhas.
- **Estado do jogo**: objetos que representam o estado atual da partida.
- **Lógica**: sistemas que interpretam efeitos, resolvem alvos etc.
- **Apresentação**: Nodes da Godot responsáveis pela interface e representação visual.

Objetivo principal: adicionar/modificar conteúdo sem precisar alterar código sempre que possível.

Fluxo conceitual:

```text
JSON
  ↓
Data
  ↓
Game State
  ↓
Systems
  ↓
Visual Nodes
```

---

## 3. Estrutura de diretórios atual

```text
res://
├── data/
│   ├── cards/
│   ├── units/
│   └── battles/
│
├── scenes/
│   ├── card.tscn
│   ├── enemy.tscn
│   └── battle_floor.tscn
│
└── scripts/
    ├── card.gd
    ├── card_data.gd
    ├── card_database.gd
    ├── unit.gd
    ├── unit_data.gd
    ├── unit_database.gd
    ├── battle_definition.gd
    ├── battle_database.gd
    ├── battle_state.gd
    ├── battlefield.gd
    ├── floor.gd
    ├── battle_floor_view.gd
    ├── effect_system.gd
    ├── target_system.gd
    ├── game_state.gd
    └── enemy.gd
```

---

## 4. Godot: Nodes vs RefCounted

### Nodes

Usar `Node` ou especializações quando o objeto faz parte da SceneTree ou possui representação visual.

Exemplos:

- `Card` → `Control`
- `Enemy` → `Button`
- `BattleFloorView` → `PanelContainer`

### RefCounted

Usar `RefCounted` para objetos de lógica/estado que não precisam existir na SceneTree.

Exemplos:

- `CardData`
- `CardDatabase`
- `Unit`
- `UnitData`
- `UnitDatabase`
- `BattleDefinition`
- `BattleDatabase`
- `BattleState`
- `Battlefield`
- `BattleFloor`
- `EffectSystem`
- `TargetSystem`
- `GameState`

Essa separação mantém o modelo do jogo independente da interface.

---

## 5. Cards

Cartas são definidas em JSON e carregadas pelo `CardDatabase`.

Exemplo:

```json
{
    "id": "fireball",
    "name": "Bola de Fogo",
    "description": "Cause 12 de dano a um inimigo.",
    "cost": 2,
    "type": "attack",
    "effects": [
        {
            "type": "damage",
            "target": "selected_enemy",
            "amount": 12
        }
    ]
}
```

Fluxo:

```text
card.json
   ↓
CardDatabase
   ↓
CardData
   ↓
Card (visual)
```

O `Card` não contém a lógica específica de dano/cura/etc.

---

## 6. Effects

O `EffectSystem` interpreta os efeitos definidos nos JSONs.

Exemplos atuais:

- `damage`
- `block`
- `heal`
- `summon`

Exemplo:

```json
{
    "type": "damage",
    "target": "selected_enemy",
    "amount": 12
}
```

O efeito não altera diretamente a UI.

Fluxo:

```text
Card
 ↓
Effect
 ↓
EffectSystem
 ↓
BattleState / Unit / Battlefield
```

---

## 7. Targets

O `TargetSystem` resolve quais Units são afetadas por um efeito.

Targets já previstos/implementados parcialmente:

- `enemy`
- `all_enemies`
- `ally`
- `all_allies`
- `player`
- `front_enemy`
- `rear_enemy`
- `selected_enemy`
- `selected_floor`

Targets que poderão existir futuramente:

- `selected_ally`
- `front_enemy_on_selected_floor`
- `rear_enemy_on_selected_floor`
- `random_enemy`
- `random_ally`
- `all_units_on_floor`
- outros conforme as necessidades do jogo

Um efeito não deve precisar conhecer diretamente a implementação da interface.

---

## 8. Targeting e GameState

O jogo possui estados conceituais.

Estados atuais:

```text
PLAYER_ACTION
TARGETING_ENEMY
TARGETING_FLOOR
TARGETING_POSITION
ENEMY_ACTION
```

Fluxo de uma carta que exige alvo:

```text
PLAYER_ACTION
    ↓
jogar carta
    ↓
TARGETING_ENEMY
    ↓
selecionar inimigo
    ↓
executar efeito
    ↓
PLAYER_ACTION
```

O mesmo conceito será usado para:

- selecionar inimigos;
- selecionar aliados;
- selecionar andares;
- selecionar posições;
- outras escolhas futuras.

---

## 9. Units

`UnitData` descreve o que uma unidade é.

Exemplo:

```json
{
    "id": "orc",
    "name": "Orc",
    "max_hp": 40,
    "attack": 8
}
```

`Unit` representa uma instância daquela definição em uma batalha.

A distinção é importante:

```text
UnitData
    ↓
"o que é um Skeleton?"
    ↓
Unit #1 — ALLY
Unit #2 — ENEMY
```

### Faction

A faction pertence à instância `Unit`, não à definição `UnitData`.

Atualmente:

```text
ALLY
ENEMY
```

Isso permite que a mesma unidade seja usada por jogadores e inimigos.

Exemplo:

```gdscript
create_unit("skeleton", Unit.Faction.ALLY)
create_unit("skeleton", Unit.Faction.ENEMY)
```

---

## 10. Unit State

Uma `Unit` atualmente possui/conceitualmente possui:

```text
id
name
faction
floor_index
position_index

hp
max_hp
block
```

Também possui sinal:

```gdscript
signal changed
```

Esse sinal é emitido quando HP, Block ou outros dados relevantes mudam.

A UI escuta esse sinal para atualizar sua representação.

Fluxo:

```text
Unit.take_damage()
      ↓
changed.emit()
      ↓
Enemy visual
      ↓
update_display()
```

O modelo não precisa conhecer a existência do botão visual.

---

## 11. Battlefield

O `BattleState` possui um `Battlefield`.

```text
BattleState
└── Battlefield
    ├── Floor 0
    ├── Floor 1
    └── Floor 2
```

O número de floors é definido pela `BattleDefinition`.

---

## 12. BattleFloor

Cada andar possui duas formações independentes:

```text
BattleFloor
├── allies[]
└── enemies[]
```

Cada formação possui posições lógicas:

```text
position 0 = frente
position 1 = segunda posição
position 2 = terceira posição
...
```

A posição lógica é independente da orientação visual.

### Inimigos

Visualmente:

```text
[0] [1] [2] [3]
 ↑
 frente
```

Os inimigos começam visualmente mais à esquerda e avançam para a direita.

### Aliados

Visualmente:

```text
[3] [2] [1] [0]
             ↑
           frente
```

Os aliados começam visualmente mais à direita e avançam para a esquerda.

Assim, em ambos os casos:

```text
position_index == 0
```

significa a unidade da frente.

Não alterar `position_index` apenas para acomodar a orientação visual.

---

## 13. Positioning

Ao adicionar uma unidade atualmente:

```text
add_unit()
    ↓
find_first_free_position()
    ↓
primeiro slot vazio
```

Isso significa que um summon normal não insere automaticamente uma unidade no meio da formação.

Exemplo:

```text
[0] [1] [2]
 A   B   C
```

Se B morrer e as unidades forem reorganizadas:

```text
[0] [1]
 A   C
```

A função `reorder_units()` atualiza os índices.

### Futuro

Poderemos implementar operações diferentes:

```text
add_unit()
add_unit_at(position)
insert_unit_at(position)
remove_unit()
move_unit(from, to)
```

Especialmente para:

- invocar atrás de uma unidade;
- invocar em uma posição específica;
- empurrar unidades;
- puxar unidades;
- reorganizar formação.

Isso não faz parte da implementação atual.

---

## 14. Battlefield Events

`BattleFloor` emite sinais:

```gdscript
signal unit_added(unit: Unit)
signal unit_removed(unit: Unit)
```

Isso permite que a interface reaja a mudanças no estado.

Fluxo de summon:

```text
summon effect
    ↓
BattleFloor.add_unit()
    ↓
unit_added.emit()
    ↓
BattleFloorView
    ↓
cria representação visual da Unit
```

O `Game` não precisa recriar toda a interface depois de cada alteração.

---

## 15. Summon

Summon já possui o seguinte fluxo conceitual:

```text
Carta
 ↓
summon effect
 ↓
TARGETING_FLOOR
 ↓
jogador escolhe andar
 ↓
UnitDatabase
 ↓
cria Unit
 ↓
Faction.ALLY
 ↓
BattleFloor.add_unit()
 ↓
unit_added
 ↓
UI
```

Exemplo:

```json
{
    "id": "summon_skeleton",
    "name": "Invocar Esqueleto",
    "description": "Invoque um Esqueleto em um andar.",
    "cost": 2,
    "type": "unit",
    "effects": [
        {
            "type": "summon",
            "target": "selected_floor",
            "unit": "skeleton"
        }
    ]
}
```

O `Skeleton` pode ser usado tanto por aliados quanto por inimigos porque sua faction é definida quando a `Unit` é criada.

---

## 16. Battle Definitions

A composição inicial de uma batalha também é data-driven.

Exemplo:

```json
{
    "floors": [
        {
            "units": [
                "slime",
                "slime"
            ]
        },
        {
            "units": [
                "skeleton"
            ]
        },
        {
            "units": [
                "orc"
            ]
        }
    ]
}
```

Fluxo:

```text
battle.json
    ↓
BattleDatabase
    ↓
BattleDefinition
    ↓
BattleState
    ↓
Battlefield
```

O `BattleState` não deve precisar conhecer nomes específicos de unidades.

---

## 17. Visual Debug

Durante o desenvolvimento, os botões das Units mostram:

```text
nome
faction
HP atual / máximo
floor
position
```

Exemplo:

```text
Skeleton
ALLY
HP: 20/20
Floor: 1 | Pos: 0
```

Essa informação é deliberadamente mantida durante o desenvolvimento para facilitar testes de posicionamento, targeting e combate.

---

## 18. Design de combate pretendido

A referência estrutural principal é Monster Train.

O combate deverá ter:

- múltiplos andares;
- unidades aliadas e inimigas;
- formações com posições;
- unidade da frente;
- unidades na retaguarda;
- cartas que afetam unidades;
- cartas que invocam unidades;
- seleção de alvo;
- seleção de andar;
- futuramente seleção de posição;
- turnos/ações automáticas das unidades;
- movimentação/avanço entre andares conforme as regras definidas futuramente.

A implementação deve permanecer genérica o suficiente para permitir alterações posteriores nas regras.

---

## 19. Próximo passo planejado

Adicionar **Attack** às unidades.

Primeira evolução:

```json
{
    "id": "orc",
    "name": "Orc",
    "max_hp": 40,
    "attack": 8
}
```

E no modelo:

```text
Unit
├── attack
├── HP
├── Block
└── ...
```

Depois:

```text
Unit.attack()
    ↓
TargetSystem
    ↓
unidade alvo
    ↓
take_damage()
```

Inicialmente, o ataque deverá testar a regra:

> Uma unidade inimiga ataca a unidade aliada da frente no mesmo andar.

A partir daí será construído o sistema de turnos/ações automáticas.

---

## 20. Decisões importantes

- O projeto será data-driven.
- JSON é usado para conteúdo configurável.
- `UnitData` não define faction.
- `Unit` define faction por instância.
- A mesma unidade pode ser aliada ou inimiga.
- `position_index = 0` sempre representa a frente lógica.
- Aliados são visualmente ordenados da direita para a esquerda.
- Inimigos são visualmente ordenados da esquerda para a direita.
- Summon padrão ocupa o primeiro slot vazio.
- Inserção em posição específica será implementada posteriormente.
- Modelo/estado não deve depender da UI.
- UI reage ao estado por sinais.
- `EffectSystem` interpreta efeitos.
- `TargetSystem` resolve alvos.
- `GameState` controla estados de interação.
- A composição das batalhas é definida externamente.
