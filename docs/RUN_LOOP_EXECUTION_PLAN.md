# RUN_LOOP_EXECUTION_PLAN.md

## Objetivo

Transformar o sandbox de combate atual (uma batalha isolada, resetável, com o baralho inteiro do `CardDatabase` sempre disponível) numa **run de deckbuilder de verdade**: uma sequência de combates que o jogador atravessa com o MESMO baralho, ganhando cartas/relíquias entre eles, terminando em vitória (derrotou a run) ou derrota (perdeu um combate).

O objetivo desta fase **não é ter arte, mapa bonito ou economia balanceada**. É validar a estrutura: dá pra jogar uma run do início ao fim, as escolhas entre combates (que carta pegar, que caminho seguir) parecem decisões de verdade?

---

# Princípios

## 1. Loop antes de conteúdo

Não popular o mapa com dezenas de tipos de nó, relíquias ou eventos.

Primeiro implementar as primitivas:

- Estado de Run (persiste entre combates)
- Sequência de combates
- Recompensa entre combates
- Mapa/escolha de caminho
- Relíquias
- Economia/loja

Depois usar pouco conteúdo (algumas relíquias, um tipo de loja simples) pra validar as combinações.

## 2. Implementação incremental

Mesma disciplina do `MECHANICS_EXECUTION_PLAN.md`:

1. Implementar uma pequena peça do loop.
2. Criar conteúdo mínimo pra exercitá-la.
3. Testar no jogo.
4. Corrigir problemas.
5. Somente então avançar.

Não implementar todas as etapas de uma vez — esta fase é estruturalmente maior que o plano de mecânicas de combate (mexe em `Game.gd` como um todo, não só em `BattleState`), então a tentação de pular etapas é maior. Resistir a ela.

## 3. Separar claramente três camadas de estado

Este projeto já mistura um pouco esses conceitos hoje (ver "Estado atual" abaixo). A partir desta fase, manter claro:

- **Catálogo** (`CardDatabase`/`UnitDatabase`/`BattleDatabase`): TODO o conteúdo que existe no jogo, carregado uma vez, nunca muda durante uma run.
- **Estado de Run** (novo — `RunState` ou nome equivalente): o que é específico DESTA run e sobrevive entre combates — o baralho atual do jogador, relíquias possuídas, ouro, progresso no mapa, HP entre combates (se houver). Não existe hoje; hoje cada combate recria um `Deck` a partir do catálogo inteiro.
- **Estado de Batalha** (`BattleState`/`Battlefield`): o que existe só durante UM combate — unidades no grid, HP/status/turno. Já existe e não muda de escopo.

## 4. Evitar overengineering

Não criar um editor de mapa visual, um motor de eventos ramificados genérico, ou um sistema de save em disco antes de precisar. Mapa pode ser uma lista linear de nós no início; eventos podem nem existir ainda.

---

# Estado atual (revisão)

O sandbox hoje (ver `docs/playtest_3x3.md` e `docs/MECHANICS_EXECUTION_PLAN.md`, ambos implementados) é **uma única batalha isolada**:

- `Game._ready()` chama `start_new_battle_state()` uma vez com `test_battle.json` (ou, via "Random", um `BattleDefinition.empty()` populado por `spawn_random_units()`).
- `setup_deck_and_mana()` cria um `Deck` novo a partir de **todo o `CardDatabase`** — não existe conceito de "baralho do jogador" menor que o catálogo inteiro, nem persistência entre combates.
- "Resetar combate"/"Random" recomeçam esse único combate do zero — não avançam pra outro combate, não existe "próxima batalha".
- O loop de 4 waves de inimigos (`MAX_ENEMY_WAVES`) é **dentro** de um único combate, não uma sequência de combates separados.
- Não existe conceito de: baralho persistente menor que o catálogo, recompensa de carta, relíquia, mapa, ouro/economia, ou "a run acabou (vitória/derrota definitiva)".

**Nota sobre a documentação existente**: `docs/ARCHITECTURE.md` e partes de `AGENTS.md` (seção "Current status"/"Possible future directions") descrevem uma arquitetura BEM mais antiga (formações lineares com `position_index`/push, `GameState` com `TARGETING_POSITION`/`COMBAT_PHASE`, `EnemySpawner` automático, múltiplos floors) que foi **substituída** pelo sandbox 3x3 de `docs/playtest_3x3.md` e tudo que veio depois. `Pyre`, `GameState`, `EnemySpawner`, `BattleDatabase` com múltiplos floors por batalha são hoje **código morto/vestigial** — instanciados ou definidos, mas não usados pelo fluxo real de `game.gd`. Não usar `ARCHITECTURE.md` como referência do que existe agora nessas áreas; confiar no código atual (`game.gd`, `battle_state.gd`, etc.). Atualizar `ARCHITECTURE.md` faz parte do trabalho desta fase (ver Etapa 1).

---

# Roadmap

1. **Estado de Run e baralho persistente**
2. **Sequência de combates (sem mapa ainda)**
3. **Recompensa de carta entre combates**
4. **Mapa com nós e escolha de caminho**
5. **Relíquias**
6. **Economia e loja**
7. **Playtest de integração da run completa**

---

# ETAPA 1 — Estado de Run e baralho persistente

## Objetivo

Criar o conceito de "baralho do jogador nesta run", menor e distinto do catálogo inteiro, e um objeto de estado (`RunState`, `RefCounted`, mesmo padrão de `BattleState`) que sobrevive entre combates.

## Mecânicas

- `RunState` guarda: a lista de `CardData` que o jogador realmente tem (o "baralho de run" — não confundir com `Deck.draw_pile`/`hand`/etc., que continuam sendo o embaralhamento **dentro** de um combate).
- `Game.setup_deck_and_mana()` para de usar `card_database.cards` inteiro — passa a receber a lista de `RunState` como ponto de partida do `Deck` de cada combate.
- Um "baralho inicial" pequeno e fixo (ex.: 10-12 cartas simples — Golpe, Defesa, Cura, um Reposicionar, um summon básico) definido em dados (`data/runs/starter_deck.json` ou equivalente), não o catálogo inteiro.
- "Resetar combate"/"Random" continuam existindo como ferramentas de DEBUG (não fazem parte do loop de run) — mas passam a reconstruir o `Deck` a partir do `RunState` atual, não do catálogo inteiro.

## Conteúdo de teste

- Um baralho inicial pequeno (10-12 cartas) definido em dado.
- Um botão de debug "Nova Run" que cria um `RunState` novo com esse baralho inicial e inicia o primeiro combate.

## Critérios de aceite

- É possível iniciar uma run com um baralho MENOR que o catálogo inteiro.
- O baralho jogado num combate é exatamente o de `RunState`, não `CardDatabase.cards` inteiro.
- Resetar o combate atual não altera `RunState` (o baralho da run continua o mesmo).

---

# ETAPA 2 — Sequência de combates (sem mapa ainda)

## Objetivo

Substituir "uma batalha isolada" por "uma sequência linear de combates", sem ainda ter um mapa visual ou ramificação — só validar que dá pra completar combate 1, avançar pro combate 2, etc., até vencer ou perder a run inteira.

## Mecânicas

- `RunState` guarda o índice do combate atual (`current_encounter_index`) e a lista de combates da run (pode ser, por enquanto, uma lista fixa de `BattleDefinition`s ou ids de `data/battles/*.json`, sorteada ou fixa).
- Vencer um combate (`BattleState.is_victory()`) avança `current_encounter_index` e inicia o próximo combate automaticamente (ou via um botão "Continuar").
- Perder um combate (`BattleState.is_defeat()`) encerra a RUN (não só o combate) — tela/mensagem de "Run perdida", só então libera "Nova Run".
- Vencer o ÚLTIMO combate da lista = "Run vencida".
- HP entre combates: decidir (e documentar aqui, depois de decidido com o usuário) se as unidades aliadas curam totalmente entre combates ou mantêm o HP — Slay the Spire cura o jogador entre combates normais mas não elites/bosses; este projeto pode simplificar pra "cura total entre combates" na primeira versão.

## Conteúdo de teste

- 3-4 combates fixos em sequência (reaproveitar `BattleDefinition`s já existentes/variações simples), o último um pouco mais difícil.

## Critérios de aceite

- Dá pra jogar do combate 1 ao último combate sem reiniciar manualmente nada.
- Perder qualquer combate no meio encerra a run (não só o combate).
- Vencer o último combate mostra vitória de run.

---

# ETAPA 3 — Recompensa de carta entre combates

## Objetivo

Ao vencer um combate (exceto o último, ou incluindo — decidir com o usuário), oferecer uma escolha de carta que se soma ao `RunState.deck` permanentemente.

## Mecânicas

- Tela/painel simples de recompensa: sorteia 2-3 `CardData` de um pool maior que o baralho inicial (o catálogo inteiro pode servir de pool, ou um subconjunto "cartas de recompensa" vs. "cartas iniciais").
- Jogador escolhe 1 (ou pula, se quiser permitir pular).
- A carta escolhida entra em `RunState.deck` — no PRÓXIMO combate, o `Deck` desse combate já nasce com ela.

## Conteúdo de teste

- Pool de recompensa = catálogo inteiro (simplificação inicial) ou um subconjunto deliberado.

## Critérios de aceite

- A carta escolhida aparece no baralho do combate seguinte.
- Pular (se permitido) não adiciona nada.
- O baralho cresce ao longo da run (não reresetamos pro baralho inicial a cada combate).

---

# ETAPA 4 — Mapa com nós e escolha de caminho

## Objetivo

Trocar "sequência linear fixa" por um mapa simples com ramificação — o jogador escolhe ENTRE 2-3 caminhos possíveis a cada passo, não segue uma única ordem fixa.

## Mecânicas

- Grafo simples de nós (pode ser gerado em código, não precisa de editor visual): cada nó tem um tipo (`combat` no início; outros tipos vêm nas etapas seguintes) e uma lista de nós alcançáveis a partir dele.
- UI mínima: lista/coluna de nós disponíveis a partir da posição atual, jogador clica em um pra iniciar esse combate.
- `RunState` guarda a posição atual no mapa em vez de um índice linear.

## Conteúdo de teste

- Um mapa pequeno (8-12 nós, só tipo `combat`), gerado uma vez por run.

## Critérios de aceite

- Existe mais de um caminho possível a partir de um nó.
- A escolha de caminho é do jogador, não automática.
- Terminar o mapa (chegar num nó final) conta como vitória de run.

---

# ETAPA 5 — Relíquias

## Objetivo

Introduzir efeitos passivos de RUN INTEIRA (não de unidade, não de combate único) — o equivalente a "keepsakes"/"relics" de Slay the Spire/Monster Train.

## Mecânicas

- `RelicData`/`Relic` (mesmo padrão data-driven de `UnitData`/`CardData`): id, nome, descrição, efeito.
- `RunState` guarda a lista de relíquias possuídas.
- Efeitos iniciais (poucos, simples, reaproveitando o que já existe): "+1 mana inicial em todo combate", "compra +1 carta na mão inicial", "+X HP máximo em toda unidade aliada ao iniciar o combate". Evitar qualquer coisa que exija um novo sistema — cada efeito deve mapear pra algo que `Game.setup_deck_and_mana()`/`BattleState.create_unit()` já sabe fazer.
- Obtidas como alternativa à recompensa de carta (Etapa 3) — nós de recompensa oferecem carta OU relíquia, não as duas.

## Conteúdo de teste

- 3-4 relíquias simples cobrindo os efeitos acima.

## Critérios de aceite

- Uma relíquia ativa continua tendo efeito em TODOS os combates seguintes da run, não só no combate em que foi obtida.
- Múltiplas relíquias acumulam corretamente (2 relíquias de "+1 mana" resultam em +2).

---

# ETAPA 6 — Economia e loja

## Objetivo

Introduzir um recurso (ouro) e um nó de loja onde gastá-lo.

## Mecânicas

- `RunState.gold`, ganho ao vencer combates (quantidade fixa ou por tipo de combate).
- Nó de tipo `shop`: oferece um pequeno número de cartas/relíquias à venda por um preço fixo, e talvez "remover uma carta do baralho" (Slay the Spire tem isso — decidir se entra nesta fase ou fica pra depois).
- Comprar debita `RunState.gold` e aplica o mesmo efeito de "ganhar carta"/"ganhar relíquia" das etapas anteriores — não um sistema novo.

## Conteúdo de teste

- Uma loja simples com 3-4 itens à venda, preços fixos.

## Critérios de aceite

- Ouro acumula entre combates.
- Comprar um item indisponível (sem ouro suficiente) é bloqueado.
- O item comprado tem exatamente o mesmo efeito que teria como recompensa gratuita (Etapas 3/5).

---

# ETAPA 7 — Playtest de integração da run completa

## Objetivo

Jogar (ou simular, via smoke test headless) uma run inteira do começo ao fim: mapa → combates → recompensas → relíquias → loja → vitória ou derrota de run, tudo junto.

## Perguntas do playtest

- Uma run inteira é rápida o suficiente pra iterar (não deveria demorar mais que alguns minutos neste estágio de sandbox)?
- As escolhas entre combates (carta vs. relíquia, caminho A vs. B, comprar ou economizar) parecem decisões de verdade?
- O baralho cresce de um jeito que ainda é gerenciável, ou vira uma pilha aleatória sem identidade?
- Perder no meio de uma run parece uma consequência justa (dava pra ver vindo) ou arbitrária?

## Critério de sucesso da fase

Ao final desta fase, deve ser possível: começar uma run nova, jogar vários combates em sequência com o MESMO baralho (que cresce com escolhas do jogador), escolher caminhos diferentes no mapa, obter e sentir o efeito de relíquias, gastar ouro numa loja, e terminar a run (vitória ou derrota) — tudo sem precisar reiniciar o processo do zero a cada combate como hoje.

---

# O que NÃO implementar ainda

Não implementar nesta fase:

- Arte/animações/VFX/som.
- Save em disco (persistir uma run entre sessões do jogo) — a run vive só enquanto o jogo está aberto, por enquanto.
- Múltiplos personagens/classes jogáveis (diferentes baralhos iniciais/identidades).
- Eventos narrativos ramificados (nó de tipo `event` com escolhas de texto) — pode vir depois que o resto do loop estiver validado.
- Elites/bosses com mecânicas próprias — combates continuam usando o que já existe (spawn de inimigos aleatórios/fixos).
- Balanceamento definitivo de economia (preços, quantidade de ouro, raridade de cartas).
- Editor visual de mapa.
- Multiplayer.

Esses elementos podem vir depois que o núcleo do loop de run estiver validado.

---

# Regra para futuras mecânicas

Mesma regra do `MECHANICS_EXECUTION_PLAN.md`: antes de adicionar uma nova mecânica de run, perguntar:

1. Ela pode ser construída usando as primitivas existentes (`RunState`, o mesmo `Deck`/`Mana`/`BattleState` de sempre)?
2. Ela cria uma decisão nova pro jogador?
3. Ela interage com o que já existe (baralho, relíquias, mapa)?
4. Ela vale a complexidade adicional?

Se uma nova mecânica puder ser expressa pelas existentes, não criar uma nova mecânica.

---

# Ordem de execução para o Claude Code

Executar estritamente nesta sequência:

```text
1. Estado de Run e baralho persistente
   ↓
2. Sequência de combates
   ↓
3. Recompensa de carta
   ↓
4. Mapa com nós
   ↓
5. Relíquias
   ↓
6. Economia e loja
   ↓
7. Playtest de integração
```

Após cada etapa:

- Rodar o jogo.
- Testar manualmente.
- Corrigir regressões.
- Verificar se a mecânica é compreensível.
- Somente então avançar.

---

# Regra final

O objetivo não é construir o sistema de progressão mais completo possível.

O objetivo é transformar o sandbox de combate isolado numa run jogável do início ao fim, com o mínimo de peças novas que isso exige — e descobrir, jogando, se a estrutura escolhida (mapa, recompensas, relíquias, economia) produz decisões interessantes antes de aprofundar qualquer uma delas.

Se uma implementação tecnicamente elegante não gerar novas decisões de jogador, ela não é prioridade.
