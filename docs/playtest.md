# Implementar Sandbox de Combate 3x3 para Playtest

Quero fazer um playtest de game design no meu jogo Godot atual.

## Contexto do jogo

O projeto é um deckbuilder de combate inspirado estruturalmente em Monster Train e Slay the Spire, mas quero desenvolver uma identidade própria.

O jogo já possui uma estrutura de combate, unidades, cartas, floors, targeting etc. **Não quero que você recrie a arquitetura existente.**

Antes de alterar qualquer coisa:

1. Leia `AGENTS.md`, se existir.
2. Leia `docs/ARCHITECTURE.md`, se existir.
3. Inspecione a estrutura atual do projeto.
4. Entenda como as unidades, cartas, batalha e UI estão implementadas atualmente.
5. Adapte-se à arquitetura existente.

Este trabalho é especificamente um **protótipo de game design**, então priorize velocidade de implementação e facilidade de teste, mas sem destruir a arquitetura atual. E lembre-se de que esse teste está em uma branch separada da amster, então não tenha medo de mudar alguns conceitos se necessário.

---

# Objetivo do protótipo

Quero testar um novo modelo de combate:

## Um único andar contendo 3 lanes

Cada lado do combate possui uma grade 3x3:

```text
        Lane 0   Lane 1   Lane 2

Front   [     ] [     ] [     ]
Middle  [     ] [     ] [     ]
Back    [     ] [     ] [     ]
```

Existem duas grades:

```text
ALLY GRID       ENEMY GRID
3 x 3           3 x 3
```

Não quero múltiplos floors neste protótipo.

Cada unidade ocupa exatamente uma célula.

A posição deve ser representada logicamente por algo equivalente a:

```text
lane
row
```

onde:

```text
lane = 0, 1, 2

row:
0 = Front
1 = Middle
2 = Back
```

Use a representação mais compatível com o código atual se já existir um sistema de posição.

---

# Objetivo principal do teste

Quero descobrir se é divertido escolher:

1. **qual unidade invocar**
2. **onde posicioná-la**
3. **como a posição dela altera seu comportamento**
4. **como os padrões de ataque interagem com as três lanes**
5. **se cartas de reposicionamento criam decisões interessantes**

Portanto, precisamos de uma implementação simples que permita testar isso rapidamente.

Não precisamos de deckbuilding completo, progressão, economia, animações complexas etc.

---

# 1. Tabuleiro

Transforme o campo de batalha atual para este sandbox 3x3.

Visualmente quero algo próximo de:

```text
                    ENEMIES

             LANE 0   LANE 1   LANE 2
             ┌──────┬──────┬──────┐
FRONT        │      │      │      │
             ├──────┼──────┼──────┤
MIDDLE       │      │      │      │
             ├──────┼──────┼──────┤
BACK         │      │      │      │
             └──────┴──────┴──────┘


                    ALLIES

             LANE 0   LANE 1   LANE 2
             ┌──────┬──────┬──────┐
FRONT        │      │      │      │
             ├──────┼──────┼──────┤
MIDDLE       │      │      │      │
             ├──────┼──────┼──────┤
BACK         │      │      │      │
             └──────┴──────┴──────┘
```

A implementação visual pode ser adaptada ao layout atual.

É importante que seja muito fácil identificar:

- lane;
- row;
- posição da unidade;
- faction.

Se o projeto já possui debug de `position_index`, mantenha ou adapte para mostrar algo como:

```text
Lane: 1
Row: Front
```

---

# 2. Posicionamento

Neste sandbox, preciso poder colocar unidades em qualquer célula disponível.

Não quero, por enquanto, a regra antiga de simplesmente adicionar na primeira posição vazia.

Preciso conseguir testar:

```text
Front / Left
Front / Center
Front / Right

Middle / Left
Middle / Center
Middle / Right

Back / Left
Back / Center
Back / Right
```

Idealmente o summon deve permitir escolher uma célula.

Se for muito trabalhoso adaptar o sistema de cartas existente para isso, crie temporariamente uma interação simples de sandbox que permita:

- selecionar uma unidade;
- selecionar uma célula;
- colocar a unidade naquela célula.

A prioridade é poder testar o game design.

---

# 3. Ataques NÃO são mais restritos à mesma lane

Este é um ponto muito importante.

Uma unidade não deve necessariamente atacar apenas o inimigo diretamente alinhado com ela.

Queremos um sistema baseado em **padrões de ataque**.

O padrão deve ser relativo à posição da unidade atacante.

Exemplo conceitual:

```text
. X .
. X .
. X .
```

significa uma coluna/padrão vertical.

Outro:

```text
X . X
. X .
. . .
```

pode representar um ataque em V.

O sistema deve conseguir transformar um padrão relativo à unidade atacante em células reais do grid inimigo.

Não precisa criar um editor visual de padrões agora.

Pode representar os padrões como dados simples.

Por exemplo, algo conceitualmente semelhante a:

```text
[
    Vector2(0, 0),
    Vector2(-1, 1),
    Vector2(1, 1)
]
```

A representação exata deve respeitar a arquitetura atual do projeto.

---

# 4. Padrões de ataque para o playtest

Crie estas unidades de teste.

## Guerreiro

```text
HP: 20
ATK: 6
```

Ataque:

### Golpe

Ataca o primeiro inimigo da mesma lane, procurando da Front para a Back.

Objetivo:

Testar o comportamento básico de lane.

---

# Arqueiro

```text
HP: 10
ATK: 4
```

Ataque:

### Flecha

Ataca o inimigo mais distante da mesma lane, procurando da Back para a Front.

Objetivo:

Testar como a profundidade da posição influencia a unidade.

---

# Lanceiro

```text
HP: 14
ATK: 4
```

Ataque:

### Estocada

Ataca os dois primeiros inimigos da mesma lane.

Objetivo:

Testar múltiplos alvos na mesma lane.

---

# Mago

```text
HP: 8
ATK: 5
```

Ataque:

### Explosão

Ataca o primeiro inimigo encontrado na sua lane e também inimigos adjacentes a esse alvo nas lanes vizinhas.

Exemplo conceitual:

```text
X X X
. X .
. . .
```

O alvo principal é o centro do padrão.

Se o alvo estiver em uma lane lateral, o padrão deve naturalmente ser limitado pelo grid.

Objetivo:

Testar interação entre lanes.

---

# Assassino

```text
HP: 7
ATK: 8
```

Ataque:

### Emboscada

Procura o inimigo mais distante entre as duas lanes adjacentes à sua própria lane.

Exemplo:

Se estiver na lane central:

```text
X . X
. . .
. . .
```

Se estiver na lane esquerda, pode procurar na lane imediatamente à direita.

Objetivo:

Testar se a posição horizontal muda radicalmente o comportamento da unidade.

---

# Guardião

```text
HP: 25
ATK: 3
```

Ataque:

### Guarda

Ataque frontal normal da própria lane.

Passiva:

Aliados adjacentes recebem um pequeno bônus defensivo.

Para o primeiro protótipo, pode ser algo simples como:

```text
Aliados adjacentes recebem +2 HP máximo
```

ou outro bônus equivalente que seja fácil de implementar.

Objetivo:

Testar se posicionamento cria formações interessantes.

---

# 5. Cartas de teste

Não precisamos de um sistema de deck completo.

Crie um conjunto pequeno de cartas ou ações que possam ser usadas repetidamente durante o sandbox.

## Reposicionar

```text
Mova uma unidade 1 célula em qualquer direção.
```

Não permita sair do grid.

---

## Flanquear

```text
Mova uma unidade para uma lane adjacente.
Ela recebe +3 ATK temporariamente.
```

Se implementar duração temporária for trabalhoso, pode simplesmente deixar o bônus durante o teste atual.

---

## Avançar

```text
Mova uma unidade uma posição em direção à Front.
```

---

## Recuar

```text
Mova uma unidade uma posição em direção à Back.
```

---

## Troca

```text
Troque a posição de duas unidades aliadas.
```

---

## Linha de Frente

```text
Aliados na Front recebem +3 ATK.
```

---

## Concentração

```text
Aliados que estejam na mesma lane recebem +2 ATK.
```

---

## Teleporte

```text
Mova uma unidade para qualquer célula vazia do grid aliado.
```

Esta carta é propositalmente poderosa.

Quero descobrir durante o playtest se liberdade total de posicionamento é interessante ou quebra o sistema.

---

# 6. Formação inicial para o teste

Configure uma batalha inicial com:

## Aliados

```text
             L0          L1          L2

Front      Guerreiro   Guardião    Assassino

Middle        [ ]         [ ]         [ ]

Back        Arqueiro      [ ]         Mago
```

## Inimigos

```text
             L0          L1          L2

Front        Tank         [ ]        Tank

Middle        [ ]       Archer        [ ]

Back          [ ]         Mage        [ ]
```

Crie versões simples de:

```text
Tank
Archer
Mage
```

para servir apenas como inimigos de teste.

Não precisam ter comportamento complexo.

---

# 7. Sandbox / Debug UI

Quero que seja extremamente fácil experimentar.

Se possível, adicionar controles de debug para:

- spawnar qualquer unidade aliada;
- spawnar qualquer unidade inimiga;
- remover uma unidade;
- selecionar uma unidade;
- mover uma unidade;
- executar ataque da unidade selecionada;
- executar turno de todos os inimigos;
- resetar o combate.

Também seria útil mostrar:

```text
Turn
Faction
Unit
Lane
Row
HP
ATK
```

Não precisa ficar bonito.

Este é um ambiente de **playtest de mecânica**.

---

# 8. Não implementar ainda

NÃO quero neste trabalho:

- progressão;
- cartas raras;
- deckbuilding complexo;
- recompensas;
- mapa;
- economia;
- animações elaboradas;
- VFX elaborados;
- múltiplos andares;
- movimento automático entre floors;
- sistema definitivo de turnos;
- status effects complexos;
- bosses;
- balanceamento definitivo.

O objetivo é apenas criar um **sandbox funcional para testar o grid 3x3 e os padrões de ataque**.

---

# 9. Regras importantes de arquitetura

Não crie uma arquitetura paralela se o projeto atual já possui sistemas equivalentes.

Reutilize e adapte:

- `Unit`
- `UnitData`
- `UnitView`
- `BattleState`
- `BattleFloor` / equivalente atual
- `TargetSystem`
- `EffectSystem`
- databases existentes

Se os nomes tiverem mudado no projeto atual, use os nomes existentes.

A lógica de gameplay deve continuar separada da apresentação.

A UI pode representar as células do grid, mas o estado da posição deve existir no modelo de jogo.

---

# 10. Data-driven

Sempre que possível, mantenha os dados das unidades e ataques configuráveis.

Idealmente quero conseguir futuramente escrever algo conceitualmente semelhante a:

```json
{
  "id": "mage",
  "name": "Mago",
  "attack": 5,
  "max_hp": 8,
  "attack_pattern": "area_front"
}
```

ou até:

```json
{
  "attack_pattern": [
    [0, 0],
    [-1, 1],
    [1, 1]
  ]
}
```

Mas não force esse formato se o sistema atual já possui uma solução melhor.

---

# 11. Critério de sucesso

Considerarei o trabalho concluído quando eu puder iniciar o jogo e fazer algo parecido com:

1. Ver o grid 3x3.
2. Ver aliados e inimigos posicionados em células.
3. Spawnar uma unidade em qualquer célula vazia.
4. Mover uma unidade.
5. Selecionar uma unidade.
6. Executar seu ataque.
7. Ver claramente quais células são atingidas.
8. Ver o dano aplicado.
9. Trocar a posição da unidade.
10. Executar o mesmo ataque novamente e observar que o comportamento mudou devido à nova posição.
11. Testar as cartas de reposicionamento.
12. Resetar o cenário e repetir rapidamente.

A parte mais importante do protótipo é:

> **A mesma unidade deve poder apresentar comportamentos diferentes dependendo de onde está posicionada.**

---

# 12. Processo de implementação

Não tente implementar tudo de uma vez.

Faça em etapas:

### Etapa 1

Grid 3x3 funcional.

### Etapa 2

Unidades ocupando células.

### Etapa 3

Posicionamento livre.

### Etapa 4

Sistema de padrões de ataque.

### Etapa 5

Implementar as 6 unidades de teste.

### Etapa 6

Implementar as cartas de reposicionamento.

### Etapa 7

Criar o cenário inicial.

### Etapa 8

Adicionar debug controls.

Após cada etapa, teste o jogo.

Se alguma parte da arquitetura atual tornar uma dessas etapas diferente do descrito aqui, adapte a implementação ao projeto atual em vez de duplicar sistemas.

## Importante

Não faça mudanças arquiteturais grandes sem necessidade.

O objetivo deste trabalho é criar rapidamente um **protótipo jogável para validar a ideia do grid 3x3**, não finalizar o sistema definitivo de combate.
