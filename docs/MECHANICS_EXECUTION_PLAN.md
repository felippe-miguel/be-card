# MECHANICS_EXECUTION_PLAN.md

## Objetivo

Expandir o protótipo de combate 3x3 com um conjunto pequeno, mas combinável, de mecânicas fundamentais.

O objetivo desta etapa **não é criar muitas cartas ou unidades**. É criar um vocabulário mecânico que permita posteriormente criar dezenas de cartas e unidades diferentes combinando poucas primitivas.

A prioridade é validar o design antes de transformar o sistema em um framework excessivamente genérico.

---

# Princípios

## 1. Mecânicas antes de conteúdo

Não adicionar dezenas de cartas para testar variedade.

Primeiro implementar as primitivas:

- Status
- Eventos/Triggers
- Efeitos
- Alvos
- Movimento
- Interações com posição

Depois usar poucas cartas e unidades de teste para validar as combinações.

## 2. Implementação incremental

Cada etapa deve:

1. Implementar uma pequena mecânica.
2. Criar conteúdo mínimo para exercitá-la.
3. Testar no jogo.
4. Corrigir problemas.
5. Somente então avançar.

Não implementar todas as etapas de uma vez.

## 3. Evitar overengineering

Não criar inicialmente um sistema universal de:

`Event -> Condition -> Target -> Modifier -> Effect -> Duration -> Stack Rule`

capaz de representar qualquer coisa imaginável.

O sistema deve crescer conforme as necessidades reais do design.

## 4. A grade 3x3 é parte da identidade do jogo

As mecânicas devem explorar:

- Lane
- Row
- Front
- Middle
- Back
- Adjacent lane
- Adjacent cell
- Same lane
- Distance
- Movement

A posição de uma unidade deve ser capaz de mudar decisões e resultados de combate.

---

# Estado atual (revisão)

Esta seção existe porque o sandbox já evoluiu bastante desde que este documento foi escrito. Antes de seguir o roadmap, aqui está o que já existe — pra não reimplementar por engano — e o que efetivamente falta.

## Já implementado (removido do roadmap)

**Movimento.** Já existem, como cartas de verdade (não só conceito): Reposicionar (1 célula, qualquer direção), Avançar/Recuar (direção fixa), Troca (swap de duas unidades), Teleporte (qualquer célula vazia do próprio lado) — todas sobre `BattleFloor.move_unit()`/`swap_units()`. Isso cobre a essência da antiga "Etapa 5 — Movimento como mecânica" deste documento, removida abaixo. O que falta (mover o **alvo**, não quem joga a carta — Push/Pull) não precisa virar uma etapa própria: quando algum efeito precisar disso (ex.: Knockback, na Etapa 3 atual), ele só chama `move_unit()` diretamente, do mesmo jeito que as cartas já chamam.

**Alvos espaciais.** `TargetSystem.get_pattern_attack_targets()` já resolve padrões relativos à lane do atacante (`lane_front`, `lane_rear`, `adjacent_lanes_furthest`, `primary_plus_adjacent_row`), e `EffectSystem`/cartas já targetam `selected_unit` (com filtro `target_faction`), `all_enemies`, `all_allies`. Isso cobre a essência da antiga "Etapa 6 — Alvos espaciais", removida abaixo. O que falta (padrões geométricos arbitrários, tipo `X . X / . X . / . . .`) não é prioridade agora — os 4 padrões atuais já bastam pra testar se posição influencia decisões.

Por causa disso, **as antigas Etapas 5 e 6 saem do roadmap**. Se algum dia fizerem falta de verdade (um efeito que realmente precise de Push/Pull ou de um padrão geométrico novo), plane-jam a etapa quando surgir a necessidade real — não antes.

## Parcialmente implementado

**Modificador de atributo.** Já existe, mas ad-hoc, não generalizado: `Unit.modify_attack()` (ATK permanente — usado por Flanquear/Linha de Frente/Concentração) e `Unit.set_received_max_hp_bonus()` (HP máximo, só pela aura do Guardião). Não há stacks, nem uma regra própria de consumo, nem uma camada separada visível na UI. É a base sobre a qual a Etapa 1 constrói o conceito de **Status**.

## Não implementado (o que este documento ainda cobre)

- Status com stacks (Strength/Weakness/Poison/Burn/Stun) e a separação clara modificador-vs-status.
- Qualquer sistema de eventos/triggers (`ON_SUMMON`, `ON_ATTACK`, `ON_HIT`, `ON_KILL`, `ON_DEATH` etc.) — hoje não existe nenhum gancho para "reagir" a um acontecimento do combate.
- Ataques como composição de padrão + dano + efeito adicional + trigger (Venomous, Vampiric, Knockback) — hoje um ataque só causa dano (`Unit.attack_unit()`).
- Morte como evento de gameplay (Explosive, Sacrifice, Revenge, Death Spawn).

## Foco desta fase

A pedido explícito: **modificadores de atributo, status, eventos e triggers** (Etapas 1 e 2 abaixo) são a prioridade imediata. Efeitos de ataque e de morte (Etapas 3 e 4) dependem do sistema de triggers da Etapa 2, então vêm na sequência natural depois.

---

# Roadmap

1. **Status e modificadores**
2. **Eventos e triggers**
3. **Efeitos de ataque / contato**
4. **Efeitos de morte**
5. **Combinações e conteúdo de teste**
6. **Playtest de integração**

---

# ETAPA 1 — Status e modificadores

## Objetivo

Criar uma forma simples de unidades possuírem efeitos temporários ou acumuláveis.

Separar conceitualmente:

### Modificador de atributo

Altera diretamente uma característica.

Exemplos:

- +3 ATK
- -2 ATK
- +5 HP máximo
- redução de dano

Já existe uma forma ad-hoc disso (`Unit.modify_attack()`, `Unit.set_received_max_hp_bonus()`) — não precisa recriar, só deixar claro que Status (abaixo) é uma camada conceitualmente diferente, não um substituto.

### Status

Representa um estado de gameplay.

Exemplos:

- Poison
- Burn
- Stun
- Strength
- Weakness

Não criar dezenas de status inicialmente.

## Status iniciais

### Strength

Aumenta o ataque da unidade.

`Strength 2` → `ATK +2`

### Weakness

Reduz o ataque da unidade.

`Weakness 2` → `ATK -2`

### Poison

Causa dano periódico.

Exemplo: `Poison 3` causa 3 de dano no final do turno e depois reduz em 1.

### Burn

Parecido com Poison, mas com comportamento diferente.

Sugestão inicial:

- Causa dano no início/fim do turno.
- Depois é consumido ou reduzido.

O comportamento final pode ser ajustado durante o playtest.

### Stun

Impede a unidade de realizar seu ataque naquele turno.

Deve ser um status temporário.

## Regras importantes

Definir claramente:

- Como status acumulam.
- Como status são removidos.
- Quando status são processados.
- Se status negativos podem coexistir.
- Se Strength e Weakness se anulam ou coexistem.

Preferência inicial:

- Status possuem stacks.
- Aplicar novamente aumenta stacks.
- Cada status define sua própria regra de duração/consumo.
- Não criar sistema complexo de duração universal ainda.

## Conteúdo de teste

### Berserker

Possui Strength.

### Carta: Enrage

Aplicar Strength 3 a uma unidade aliada.

### Carta: Weaken

Aplicar Weakness 2 a uma unidade inimiga.

### Carta: Stun

Aplicar Stun 1 a uma unidade inimiga.

### Carta: Cleanse

Remove um status de uma unidade.

Nota: **Venomous** ("ao atacar, aplica Poison ao alvo") foi movido pra Etapa 2 — é um trigger (`ON_HIT`), não faz sentido implementar antes do sistema de eventos existir. Pra testar Poison/Burn já nesta etapa sem esperar a Etapa 2, considere 1-2 cartas simples que apliquem o status direto (ex.: "Poison Dart", "Ignite"), do mesmo jeito que Enrage/Weaken/Stun já fazem.

## Critérios de aceite

- Status aparecem claramente na UI.
- Stacks podem ser visualizados.
- Strength/Weakness alteram o ATK efetivo.
- Poison causa dano corretamente.
- Stun impede o ataque.
- Aplicar novamente um status segue uma regra consistente.
- Morte continua funcionando normalmente.

---

# ETAPA 2 — Eventos e Triggers

## Objetivo

Permitir que unidades e efeitos reajam a acontecimentos do combate.

Eventos iniciais:

```text
ON_SUMMON
ON_ATTACK
ON_HIT
ON_KILL
ON_DAMAGE_TAKEN
ON_DEATH
ON_TURN_START
ON_TURN_END
ON_CARD_PLAYED
ON_MOVE
```

Implementar nesta ordem:

1. ON_SUMMON
2. ON_ATTACK
3. ON_HIT
4. ON_KILL
5. ON_DEATH
6. ON_MOVE
7. ON_TURN_START
8. ON_TURN_END
9. ON_CARD_PLAYED

## Exemplos

**On Summon:** ao ser invocada, ganha Strength 2.

**On Attack:** ao atacar, ganha Block 2.

**On Hit:** ao acertar, aplica Poison 2.

**On Kill:** ao matar uma unidade, ganha Strength 2.

**On Death:** ao morrer, causa 3 de dano aos inimigos adjacentes.

**On Move:** ao se mover, ganha Strength 1.

## Regra importante

Diferenciar:

`ON_ATTACK`

de

`ON_HIT`

Atacar não significa necessariamente acertar.

Se não existir alvo válido:

- ON_ATTACK acontece.
- ON_HIT não acontece.

## Conteúdo de teste

- **Duelist:** ao atacar, Gain Block 2.
- **Venomous:** ao acertar, Apply Poison 2.
- **Executioner:** ao matar, Gain Strength 2.
- **Explosive:** ao morrer, Damage adjacent enemies for 3.
- **Mobile Unit:** ao se mover, Gain Strength 1.

## Critérios de aceite

- Eventos são disparados no momento correto.
- ON_ATTACK não depende de causar dano.
- ON_HIT só ocorre quando existe contato/dano válido.
- ON_DEATH ocorre uma única vez.
- ON_MOVE ocorre quando a posição realmente muda.
- Triggers podem gerar efeitos sem quebrar o fluxo normal do combate.

---

# ETAPA 3 — Efeitos de ataque / contato

## Objetivo

Transformar ataque em uma combinação de:

```text
Target Pattern
+
Damage
+
Additional Effects
+
Triggers
```

O ataque deixa de ser apenas:

`Attack -> Damage`

e passa a poder representar:

`Attack -> Target -> Damage -> Apply Poison`

ou:

`Attack -> Target -> Damage -> Move target`

## Efeitos iniciais

- Damage
- Heal
- GainBlock
- ApplyStatus
- RemoveStatus
- ModifyAttack
- Move

Não criar efeitos especiais individualmente quando puderem ser representados por essas primitivas.

## Exemplos

**Venomous**
```text
Attack
Target: Front
Damage: ATK
OnHit:
    Apply Poison 2
```

**Vampiric**
```text
Attack
Target: Front
Damage: ATK
OnHit:
    Heal self by damage dealt
```

**Knockback**
```text
Attack
Target: Front
Damage: ATK
OnHit:
    Move target 1 row backward
```

**Piercing**
```text
Attack
Target Pattern: First 2 enemies in lane
Damage: ATK
```

Nota: Piercing já existe hoje (Lanceiro, `attack_pattern_count = 2` sobre `lane_front`) — não precisa recriar, só serve de exemplo de como o padrão de alvo já é independente do dano. Knockback reaproveita `BattleFloor.move_unit()` direto (o mesmo que as cartas de movimento já usam) como consequência de um `OnHit`, não precisa de mecânica de movimento nova.

## Critérios de aceite

- Um ataque pode produzir dano e efeitos adicionais.
- Efeitos adicionais não precisam ser codificados especificamente dentro da unidade.
- Ataques em área conseguem aplicar efeitos aos múltiplos alvos.
- ON_HIT funciona individualmente para cada alvo atingido.
- Movimento causado por ataque respeita a grade.

---

# ETAPA 4 — Efeitos de morte

## Objetivo

Explorar a morte como evento de gameplay.

A morte deixa de ser apenas a remoção de uma unidade.

## Mecânicas

**Explosive:** ao morrer, causa dano aos inimigos adjacentes.

**Sacrifice:** ao morrer, cura um aliado.

**Revenge:** ao morrer, todos os aliados ganham Strength 1.

**Death Spawn:** ao morrer, invoca outra unidade em sua célula.

## Atenção

Resolver corretamente:

- Ordem dos efeitos.
- Múltiplas mortes simultâneas.
- Morte causada por efeito de morte.
- Cadeias de mortes.
- Loops infinitos.

## Conteúdo de teste

Criar:

- Explosive unit
- Death-buff unit
- Death-summon unit

Testar:

1. Uma unidade morre sozinha.
2. Duas unidades morrem simultaneamente.
3. Uma morte causa outra morte.

## Critérios de aceite

- ON_DEATH dispara corretamente.
- Cada unidade dispara seu evento apenas uma vez.
- Cadeias de morte são processadas corretamente.
- Não existem loops infinitos.
- A ordem dos efeitos é determinística.

---

# ETAPA 5 — Combinações

## Objetivo

Validar se as primitivas realmente geram variedade.

Não adicionar dezenas de mecânicas. Criar conteúdo que combine as existentes.

## Combinações obrigatórias

### Movimento + Trigger

Ao se mover, ganha Strength.

### Movimento + Ataque

Se avançou neste turno, causa +3 dano.

### Ataque + Status

Ao acertar, aplica Poison.

### Ataque + Movimento

Ao acertar, empurra o alvo.

### Morte + Área

Ao morrer, causa dano aos inimigos adjacentes.

### Posição + Modificador

Na Back, ganha +4 ATK.

### Posição + Targeting

Na Back, ataca o inimigo mais distante.

### Summon + Posição

Ao ser invocado na Front, ganha Strength.

### Adjacent + Buff

Aliados adjacentes ganham Block.

### Kill + Movimento

Ao matar, avança uma célula.

---

# ETAPA 6 — Playtest de integração

## Objetivo

Criar um pequeno sandbox onde todas as mecânicas possam ser testadas juntas.

Não precisa ser um combate completo e balanceado.

O objetivo é responder:

> O jogo ficou mais interessante porque agora existe mais interação entre as decisões?

## Conteúdo recomendado

### Unidades

10–12 unidades de teste.

Distribuir entre:

- Frontline
- Backline
- Posicionamento
- Poison
- Buff
- Debuff
- On-hit
- On-death
- Movement
- Area attack

### Cartas

15–20 cartas de teste.

Distribuir entre:

- Damage
- Heal
- Buff
- Debuff
- Move
- Push
- Pull
- Swap
- Teleport
- Status
- Summon
- Area effects

---

# Perguntas do playtest

## Posicionamento

- Eu penso onde colocar a unidade?
- Mudar uma unidade de posição muda significativamente o combate?
- Existem posições claramente dominantes?
- Existe motivo para ocupar a Back?
- Existe motivo para ocupar a Front?

## Movimento

- Eu movo unidades porque quero, ou apenas porque preciso corrigir erros?
- Push/Pull criam decisões interessantes?
- Movimento cria combos?

## Status

- Consigo entender o que cada status faz?
- Os stacks são fáceis de acompanhar?
- Status mudam minhas decisões?

## Triggers

- Consigo prever quando eles vão acontecer?
- Existe sensação de "combo"?
- As interações são descobertas de forma divertida ou parecem arbitrárias?

## Ataques

- Os padrões espaciais são fáceis de entender?
- Ataques em área parecem diferentes de ataques normais?
- A posição do atacante influencia o resultado de forma interessante?

## Conteúdo

A pergunta mais importante:

> Com poucas unidades e cartas, o sistema já consegue produzir situações diferentes?

Se a resposta for sim, o sistema está no caminho certo.

---

# O que NÃO implementar ainda

Não implementar nesta fase:

- Deckbuilding completo.
- Relíquias.
- Economia.
- Shop.
- Progressão.
- Meta-progression.
- Bosses complexos.
- Dezenas de status.
- Dezenas de keywords.
- Sistema universal de scripting.
- Editor de cartas.
- Modding externo.
- Multiplayer.
- Efeitos extremamente específicos.
- Padrões geométricos de alvo além dos 4 já existentes (ver "Estado atual").
- Push/Pull dedicados, fora do que um efeito específico precisar (ver Etapa 3).

Esses elementos podem vir depois que o núcleo de combate estiver validado.

---

# Critério de sucesso da fase

Ao final desta fase, deve ser possível criar uma unidade conceitualmente assim:

```text
Venomous Assassin

ATK: 8

Target:
    Enemy
    Adjacent Lane
    Furthest

OnHit:
    Apply Poison 2

OnMove:
    Gain Strength 1

Position:
    Back -> +3 ATK
```

E outra completamente diferente:

```text
Guardian

ATK: 3

OnSummon:
    Gain Block 5

Passive:
    Adjacent allies take less damage

OnDeath:
    Heal adjacent allies
```

Sem precisar criar uma nova implementação de sistema para cada unidade.

(O padrão de Target acima — "Enemy, Adjacent Lane, Furthest" — já existe hoje como `adjacent_lanes_furthest`, usado pelo Assassino. O resto — OnHit/OnMove/Position modifier — é o que as Etapas 1-4 entregam.)

---

# Regra para futuras mecânicas

Antes de adicionar uma nova mecânica, perguntar:

1. Ela pode ser construída usando as primitivas existentes?
2. Ela cria uma decisão nova para o jogador?
3. Ela interage com posicionamento?
4. Ela cria combinações interessantes?
5. Ela vale a complexidade adicional?

Se uma nova mecânica puder ser expressa pelas existentes, **não criar uma nova mecânica**.

Exemplo:

Não criar:

`PoisonousAttackEffect`

se já existe:

`OnHit -> ApplyStatus(Poison)`.

---

# Ordem de execução para o Claude Code

Executar estritamente nesta sequência:

```text
1. Status
   ↓
2. Eventos / Triggers
   ↓
3. Efeitos de ataque
   ↓
4. Efeitos de morte
   ↓
5. Combinações
   ↓
6. Playtest
```

Após cada etapa:

- Rodar o jogo.
- Testar manualmente.
- Corrigir regressões.
- Verificar se a mecânica é compreensível.
- Somente então avançar.

---

# Regra final

O objetivo não é construir o sistema de cartas mais genérico possível.

O objetivo é construir **um conjunto pequeno de mecânicas que, combinadas com a grade 3x3, produzam decisões interessantes**.

Se uma implementação tecnicamente elegante não gerar novas possibilidades de design, ela não é prioridade.

Se uma mecânica simples gerar muitas combinações interessantes, ela merece prioridade.
