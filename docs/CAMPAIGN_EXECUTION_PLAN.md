# CAMPAIGN_EXECUTION_PLAN.md

## Objetivo

Transformar o sandbox de combate atual (uma batalha isolada, resetável, com
o catálogo inteiro do `CardDatabase` servindo de baralho) numa **campanha
persistente num mundo aberto**:

- O jogador explora livremente um **world map** com pontos de interesse:
  combates, mercadores de cartas, mercadores de artefatos, eventos etc.
- Cartas são **colecionadas** ao longo da campanha (compradas, ganhas em
  combates/eventos), até a coleção completa de todas as cartas do jogo.
- Antes de cada combate, o jogador escolhe **com qual deck** vai lutar. Um
  deck é montado a partir das cartas que ele possui na coleção, e ele pode
  manter vários decks diferentes para combates diferentes.

**Isto NÃO é um roguelike de runs.** A ideia anterior (estilo Monster Train/
Slay the Spire: atravessar um caminho fixo construindo UM baralho que
morre junto com a run) foi descartada. Não existe "run", "fim de run" nem
"baralho da run". O progresso (coleção, ouro, artefatos, mapa explorado) é
permanente.

O objetivo desta fase **não é ter arte, mapa bonito ou economia
balanceada**. É validar a estrutura: colecionar cartas dá vontade de
explorar? Montar decks diferentes para combates diferentes vira uma decisão
de verdade?

---

# Princípios

## 1. Loop antes de conteúdo

Não popular o mapa com dezenas de pontos, artefatos ou eventos. Primeiro
implementar as primitivas:

- Coleção do jogador (persiste a campanha inteira)
- Decks montados a partir da coleção + escolha de deck antes do combate
- Combate como encontro, que devolve um resultado ao mundo
- World map com pontos de interesse
- Mercadores (cartas, artefatos)
- Artefatos
- Eventos
- Save em disco

Depois usar pouco conteúdo para validar as combinações.

## 2. Implementação incremental

Mesma disciplina do `MECHANICS_EXECUTION_PLAN.md`:

1. Implementar uma pequena peça do loop.
2. Criar conteúdo mínimo para exercitá-la.
3. Testar no jogo.
4. Corrigir problemas.
5. Somente então avançar.

Esta fase mexe na estrutura de cenas do jogo como um todo (hoje `game.tscn`
é a cena principal E a batalha), então a tentação de pular etapas é maior.
Resistir a ela.

## 3. Separar claramente três camadas de estado

- **Catálogo** (`CardDatabase`/`UnitDatabase`/`BattleDatabase` e, no futuro,
  artefatos/mapa): todo o conteúdo que existe no jogo. Carregado uma vez,
  nunca muda durante a campanha.
- **Estado de Campanha** (novo, `CampaignState` ou nome equivalente,
  `RefCounted`): o que é específico DESTE jogador e sobrevive à campanha
  inteira. Inclui a coleção de cartas, os decks montados, ouro, artefatos
  possuídos, posição no mapa e o estado de cada ponto do mapa (já visitado,
  combate já vencido etc.). É o que vai para o save em disco.
- **Estado de Batalha** (`BattleState`/`Battlefield`/`Deck`/`Mana`): o que
  existe só durante UM combate (unidades no grid, HP/status/turno, pilha de
  compra/mão/descarte). Já existe e não muda de escopo.

Atenção ao nome `Deck`: hoje `Deck` é o embaralhamento **dentro** de um
combate (draw/hand/discard/graveyard). A lista de cartas que o jogador
montou fora do combate é outro conceito. Chamar de `DeckList` (ou
equivalente), nunca reaproveitar `Deck` para as duas coisas. O `Deck` de um
combate nasce a partir de uma `DeckList`.

## 4. Fluxo de cenas

Hoje `game.tscn` é a cena principal e já É a batalha. A campanha precisa de
uma camada acima dela. `Main` troca a tela atual instanciando a cena
filha correspondente (e liberando a anterior). As telas não trocam de
cena sozinhas: emitem sinais (`play_pressed`, `point_entered`,
`battle_finished`...) e `Main` decide o que vem a seguir. Isso mantém o
`CampaignState` num lugar só, sem autoload global, e as telas
desacopladas umas das outras.

```text
Main (cena principal: dono do CampaignState, troca de tela)
 ├── MainMenu      (Jogar / Sair)
 ├── Overworld     (explorar, escolher ponto de interesse)
 ├── DeckBuilder   (montar/editar decks a partir da coleção)
 ├── Merchant      (comprar cartas/artefatos)
 └── Battle        (o game.tscn de hoje — recebe definição de batalha +
                    DeckList + artefatos, devolve o resultado)
```

A batalha não deve conhecer o `CampaignState` inteiro. Ela recebe o que
precisa (definição do combate, lista de cartas do deck escolhido,
artefatos ativos) e emite um resultado (`vitória`/`derrota`), e quem
aplica recompensas/consequências é a camada de campanha.

## 5. Evitar overengineering

Não criar um editor de mapa visual nem um motor genérico de eventos
ramificados antes de precisar. O mapa pode começar como um grafo pequeno
definido em JSON, e os eventos podem começar como "texto + 2 escolhas com
efeitos simples".

---

# Estado atual

O jogo hoje (ver `docs/ARCHITECTURE.md`) é **uma única batalha isolada**:

- `game.tscn` é a cena principal. Abrir o jogo cai direto no combate de
  `test_battle.json` (ou, via botão de debug "Random", um campo sorteado).
- `Game.setup_deck_and_mana()` cria o `Deck` a partir de **todo o
  `CardDatabase`**, uma cópia de cada carta. Não existe coleção, deck
  montado, nem cópias múltiplas de uma carta.
- O combate termina por waves: `MAX_ENEMY_WAVES` reforços inimigos entram
  um por "Rodar turno". Vitória = zerar inimigos depois da última wave,
  derrota = perder todos os aliados. Depois disso só "Resetar"/"Random"
  recomeçam o mesmo combate.
- Não existe: menu principal, overworld, coleção, decks salvos, ouro,
  artefatos, mercador, evento, save em disco, nem uma cena acima da
  batalha.

---

# Roadmap

1. **Overworld cru** (menu principal, mapa, movimento, combate como
   encontro, estado dos pontos), dividido em passos pequenos abaixo
2. **Coleção de cartas** (`CampaignState`)
3. **Decks montados (DeckList) e escolha de deck para o combate**
4. **Mercador de cartas e ouro**
5. **Tela de montagem de deck (DeckBuilder)**
6. **Artefatos e mercador de artefatos**
7. **Eventos**
8. **Save/load em disco**
9. **Playtest de integração da campanha**

O overworld vem primeiro por pedido do usuário: ele é o "esqueleto" onde
todas as outras peças (mercadores, eventos, escolha de deck) vão se
pendurar. Enquanto as Etapas 2-3 não existirem, todo combate continua
usando o baralho de hoje (catálogo inteiro).

---

# ETAPA 1 — Overworld cru

## Objetivo

Uma primeira versão **simples e crua**, sem arte, do loop "menu → mapa →
entrar num ponto → voltar ao mapa". Visual mínimo: botões, linhas e
labels. Nada de personagem andando, câmera ou tilemap.

## Decisão de formato do mapa

O mapa desta versão é um **grafo de pontos clicáveis** (cada ponto é um
botão numa posição fixa da tela, ligado aos vizinhos por linhas). Viajar =
clicar num ponto conectado ao atual, e o deslocamento é instantâneo. É o
formato mais barato de implementar e já valida a exploração livre (ir e
voltar, ciclos, escolha de destino).

Um mapa com personagem andando livremente (tilemap/2D) continua possível
depois. Se for o caso, só a apresentação muda: o grafo de pontos de
interesse e o `CampaignState` continuam valendo.

## Passos

Cada passo é uma mudança pequena, testada no editor e confirmada pelo
usuário antes do próximo.

### Passo 1.1 — Menu principal e cena raiz

- `scenes/main.tscn` (`Main`, script `main.gd`) vira a cena principal do
  projeto (`run/main_scene`), no lugar de `game.tscn`.
- `scenes/main_menu.tscn`: título + botões **Jogar** e **Sair**. Emite
  `play_pressed`/`quit_pressed`.
- `scenes/overworld.tscn`: placeholder vazio (título "Overworld" + botão
  "Voltar ao menu", que emite `back_to_menu_pressed`).
- `Main` mostra o menu ao abrir. Jogar → troca pro overworld. Sair →
  fecha o jogo. Voltar ao menu → troca pro menu.
- `game.tscn` fica fora do fluxo neste passo (continua abrível direto no
  editor com F6 pra testar combate).

Critério: abrir o jogo mostra o menu, Jogar leva ao overworld vazio, dá
para voltar ao menu, Sair fecha o jogo.

### Passo 1.2 — Mapa em dado, desenhado na tela

- `data/world/overworld.json`: lista de pontos (`id`, `name`, `type`,
  `position` em pixels de tela) e lista de conexões (pares de ids).
  Começar com 6-8 pontos, todos `combat` ou sem tipo, com pelo menos um
  ciclo.
- `WorldPointData` + `WorldMapData` (`RefCounted`, `from_dict()`, mesmo
  padrão de `UnitData`/`BattleDefinition`) e um loader simples. Um único
  mapa por enquanto, então não precisa de database com vários mapas.
- `Overworld` desenha cada ponto como um `Button` posicionado e cada
  conexão como uma linha (`Line2D` ou `_draw()`).

Critério: o mapa do JSON aparece na tela, e mudar o JSON muda o mapa.

### Passo 1.3 — CampaignState e movimento

- `CampaignState` (`RefCounted`), criado por `Main` ao clicar Jogar (=
  nova campanha), com `current_point_id` (começa num ponto inicial
  definido no JSON).
- `Overworld` recebe o `CampaignState` e o `WorldMapData` (de `Main`), e
  destaca o ponto atual (cor/label "Você está aqui").
- Clicar num ponto **conectado** ao atual move o jogador para lá. Pontos
  não conectados ficam desabilitados. Movimento em qualquer direção,
  inclusive voltar.

Critério: dá para andar pelo grafo nos dois sentidos, e só por conexões
existentes.

### Passo 1.4 — Entrar num ponto de combate

- Pontos `combat` ganham um campo `battle` (id de `data/battles/*.json`).
- **Decidido:** chegar num ponto não entra nele. Clicar no ponto ATUAL
  (marcado "— entrar") faz o overworld emitir `point_entered`, então dá
  pra passar por um combate sem lutar. `Main` troca para a batalha
  (`game.tscn`) passando o id da batalha do ponto (`Game.setup_battle()`).
- `Game` para de carregar `test_battle` fixo no `_ready()` e passa a
  receber o id de fora (com `test_battle` como fallback quando a
  cena é aberta direto no editor, para o sandbox continuar funcionando).
- No fim do combate (vitória ou derrota), aparece um botão "Voltar ao
  mapa". `Game` emite `battle_finished(victory: bool)` e `Main` volta ao
  overworld, no mesmo ponto.
- O botão de menu do combate (hoje só "Sair do jogo") ganha "Voltar ao
  mapa" (fugir do combate conta como derrota).

Critério: dá para entrar num combate pelo mapa, lutar, e voltar ao mapa
com o `CampaignState` intacto.

### Passo 1.5 — Estado dos pontos

- `CampaignState` guarda pontos visitados e combates vencidos.
- O overworld mostra isso de forma crua (ex.: "✔" no nome de um combate
  vencido, cor diferente para visitado).
- **Decidido:** combate vencido pode ser refeito quantas vezes quiser,
  só fica marcado com ✔. Recompensa por repetir é decidida na Etapa 4,
  quando houver ouro.
- Derrota: volta ao mapa sem consequência além de não marcar vitória.
  Revisar quando houver recompensas.

Critério: o mapa lembra o que já foi feito enquanto o jogo está aberto.

Junto deste passo, a pedido do usuário: Esc no overworld volta ao menu
principal; na batalha, Esc sem nada pendente abre um menu modal
centralizado (Continuar / Fugir pro mapa / Sair do Jogo).

### Passo 1.6 — Pontos de outros tipos (placeholders)

- Adicionar ao JSON pontos `card_merchant`, `artifact_merchant` e `event`.
- Entrar num deles abre um painel simples "Mercador de cartas — em breve"
  com botão "Voltar". Só placeholder, sem lógica.
- Cada tipo com um visual mínimo diferente (cor/ícone de texto) no mapa.

Critério: o mapa já tem a "cara" dos tipos de ponto que as próximas
etapas vão preencher.

Feito: 3 pontos novos (Feira da Vila, Santuário Antigo, Mascate Errante),
cor de texto por tipo, e uma tela `PointPlaceholder` genérica (Voltar ou
Esc volta ao mapa). Com isso a Etapa 1 está completa.

## Fora do escopo da Etapa 1

- Arte, animação de viagem, personagem andando, câmera/scroll do mapa.
- Recompensas (ouro/cartas): vêm na Etapa 4.
- Áreas bloqueadas por progresso.
- Save em disco (o progresso some ao fechar o jogo, por enquanto).
- Mudar regras do combate (waves, multiplicador de aliados): o combate
  continua igual ao sandbox de hoje.

---

# ETAPA 2 — Coleção de cartas

## Objetivo

Adicionar ao `CampaignState` (criado no Passo 1.3) o conceito de
**coleção**: quais cartas (e quantas cópias de cada) o jogador possui. A
coleção começa pequena e é distinta do catálogo inteiro.

## Mecânicas

- `CampaignState` guarda a coleção como `card_id -> cópias possuídas`.
  Ids, não instâncias de `CardData`: o catálogo continua sendo a fonte de
  verdade do conteúdo da carta, e ids serializam direto pro save
  (Etapa 8).
- Coleção inicial definida em dado (`data/campaign/starting_collection.json`
  ou equivalente), não em código.
- Operações mínimas: adicionar carta à coleção, consultar quantas cópias
  possui. Remover/vender fica para depois, se fizer falta.

## Conteúdo de teste

- Uma coleção inicial pequena (ex.: 12-15 cartas simples, algumas com 2-3
  cópias: Golpe, Defesa, Cura, um Reposicionar, um summon básico).

## Critérios de aceite

- Uma campanha nova começa com a coleção inicial.
- A coleção é menor que o catálogo e suporta múltiplas cópias da mesma
  carta.

Feito: coleção inicial de 14 cartas (8 diferentes) em
`data/campaign/starting_collection.json`, validada contra o catálogo, e um
painel "Coleção" cru (só leitura) no overworld pra conferir no editor.

---

# ETAPA 3 — Decks montados (DeckList) e escolha de deck para o combate

## Objetivo

Separar "cartas que eu tenho" (coleção) de "cartas que levo para esta
batalha" (deck), e fazer o combate usar o deck escolhido em vez do catálogo
inteiro.

## Mecânicas

- `DeckList` (`RefCounted`): nome + lista de `card_id` (com repetição para
  cópias). Vários `DeckList` ficam guardados no `CampaignState`.
- Validação de deck contra a coleção: um deck não pode usar mais cópias de
  uma carta do que o jogador possui.
- **Decidido:** regras permissivas por enquanto. Sem tamanho mínimo/máximo
  nem limite de cópias por carta; só não dá pra usar mais cópias do que a
  coleção tem, e deck vazio não é escolhível.
- `Game` recebe um `DeckList` junto da `BattleDefinition` (Passo 1.4) e
  `setup_deck_and_mana()` monta o `Deck` do combate a partir dele, em vez
  do catálogo inteiro. Isso inclui criar uma instância de `CardData` por
  cópia. Hoje cada `CardData` é uma instância única por tipo de carta, e
  `Game.render_hand()` usa essa referência como identidade, então cópias
  repetidas precisam de instâncias distintas (ou outra identidade) para a
  mão não confundir duas cópias da mesma carta.
- **Decidido:** o deck NÃO é escolhido a cada combate. O overworld tem um
  indicador "Deck: <nome>" ao lado de "Coleção". Clicar abre um painel
  pra escolher o deck ativo (e, na Etapa 5, criar/editar decks), que vale
  pra todo combate até ser trocado.
- Decks iniciais em `data/campaign/starting_decks.json` (fácil de editar).
  O primeiro ("Inicial", igual à coleção inicial) começa ativo.

## Conteúdo de teste

- 2 decks de debug com composições diferentes (ex.: um focado em summons,
  outro em dano/status).

## Critérios de aceite

- O baralho jogado num combate é exatamente o do `DeckList` escolhido.
- Duas cópias da mesma carta funcionam na mão (compra, animação, descarte)
  sem se confundir.
- Um deck que usa mais cópias do que a coleção possui é recusado.
- Resetar o combate não altera a coleção nem os decks.

Feito: 3 decks iniciais (Inicial, Invocações, Ataque), painel de decks no
overworld, e a batalha montando o `Deck` a partir dos ids do deck ativo,
com uma instância de `CardData` por cópia (`CardData.copy()`).

---

# ETAPA 4 — Mercador de cartas e ouro

## Objetivo

Introduzir o recurso (ouro) e o principal jeito de crescer a coleção:
comprar cartas.

## Mecânicas

- `CampaignState.gold`, ganho em combates (valor definido no ponto de
  combate do mapa, ver Passo 1.4).
- Ponto de tipo `card_merchant`: oferece um conjunto de cartas por preço.
  Comprar debita ouro e adiciona uma cópia à coleção (Etapa 2).
- Estoque de cada mercador definido em dado (quais cartas vende, preço).
  Pode ser fixo no início. Rotação/reabastecimento fica para depois.
- **Decidido (versão crua):** cada ponto de combate define o ouro no JSON
  do mapa (`"gold"`), e refazer um combate já vencido dá metade. Estoque
  fixo e infinito, preço por carta em `data/merchants/<id>.json`. Ouro
  inicial em `data/campaign/starting_resources.json` (50).
- Recompensa de combate em carta (além de ouro) usa a MESMA operação
  "adicionar à coleção". Não criar um sistema novo.
- Colecionar até a coleção completa: o catálogo inteiro precisa ser
  obtível de algum jeito (mercadores, combates ou eventos). Manter isso em
  mente ao distribuir estoque/recompensas.

## Conteúdo de teste

- 2 mercadores com estoques diferentes, preços fixos.

## Critérios de aceite

- Ouro acumula entre combates.
- Comprar sem ouro suficiente é bloqueado.
- A carta comprada aparece na coleção e pode ser colocada num deck.

Feito: 1 mercador (Feira da Vila) com 18 cartas, tela `CardMerchant`, ouro
no topo do overworld e aviso "Vitória em X: +N ouro" ao voltar do combate.
Um segundo mercador e recompensa em carta ficam pra quando fizerem falta.

---

# ETAPA 5 — Tela de montagem de deck (DeckBuilder)

## Objetivo

Dar ao jogador uma UI de verdade para criar, editar, renomear e apagar
decks a partir da coleção (até aqui, decks eram de debug).

## Mecânicas

- Tela com a coleção (cartas possuídas, cópias disponíveis/em uso) e o
  deck sendo editado.
- Adicionar/remover cartas respeitando a coleção e as regras de deck
  (Etapa 3).
- Acessível fora do combate (no mapa). Também oferecer a escolha de deck
  antes de entrar num combate, se ainda não existir na UI.
- Reaproveitar a visual `Card` (`card.tscn`) para mostrar as cartas.
- **Decidido:** a edição é uma tela própria (`DeckBuilder`), aberta pelo
  painel de decks do overworld ("Editar" em cada deck, "Criar novo deck").
  O painel continua só pra escolher o deck ativo.
- **Decidido:** dois decks não podem ter o mesmo nome (sem diferenciar
  maiúsculas/minúsculas). Com nome repetido, o Salvar fica desabilitado e
  aparece um aviso.

## Critérios de aceite

- Dá para montar um deck novo do zero, salvá-lo e usá-lo no próximo
  combate.
- Não é possível montar um deck inválido.

Feito: tela `DeckBuilder` crua (listas com "+"/"−", sem a visual `Card`
ainda), edição numa cópia com Salvar/Cancelar, renomear e apagar (o último
deck não pode ser apagado).

---

# ETAPA 6 — Artefatos e mercador de artefatos

## Objetivo

Introduzir efeitos passivos permanentes da campanha (não de unidade, não
de um combate único).

## Mecânicas

- `ArtifactData`/`ArtifactDatabase` no mesmo padrão data-driven de
  `UnitData`/`CardData`: id, nome, descrição, efeito.
- `CampaignState` guarda os artefatos possuídos.
- Global vs. por deck: **decidir com o usuário** se todo artefato possuído
  vale em todo combate ou se o jogador escolhe quais artefatos acompanham
  cada deck (o que conversa bem com "decks diferentes para combates
  diferentes").
- Efeitos iniciais simples que reaproveitam o que já existe: "+1 mana
  inicial", "+1 carta na mão inicial", "+X HP máximo nas unidades aliadas
  ao iniciar o combate". Cada efeito deve mapear para algo que
  `Game.setup_deck_and_mana()`/`BattleState.create_unit()` já sabe fazer.
- Ponto de tipo `artifact_merchant`, mesma lógica do mercador de cartas
  (Etapa 4).

## Conteúdo de teste

- 3-4 artefatos simples cobrindo os efeitos acima, e 1 mercador de
  artefatos.

## Critérios de aceite

- Um artefato ativo tem efeito em todo combate em que estiver ativo, não
  só no combate em que foi obtido.
- Múltiplos artefatos acumulam corretamente (2× "+1 mana" = +2).

---

# ETAPA 7 — Eventos

## Objetivo

Pontos do mapa com escolhas fora de combate.

## Mecânicas

- Ponto de tipo `event`: texto + 2-3 escolhas, cada uma com efeitos
  simples sobre o `CampaignState` (ganhar/perder ouro, ganhar carta,
  ganhar artefato, iniciar um combate especial).
- Eventos definidos em dado. Sem árvore de diálogo ramificada nesta etapa.
- Evento único vs. repetível: definido por evento, no dado.

## Conteúdo de teste

- 2-3 eventos simples.

## Critérios de aceite

- Cada escolha aplica exatamente o efeito descrito.
- Um evento único não pode ser repetido.

---

# ETAPA 8 — Save/load em disco

## Objetivo

Uma campanha longa e permanente precisa sobreviver a fechar o jogo, ao
contrário de uma run curta. Por isso o save é uma etapa obrigatória aqui,
não algo opcional.

## Mecânicas

- Serializar o `CampaignState` (coleção, decks, ouro, artefatos, posição e
  estado dos pontos do mapa) para `user://`, em JSON.
- Salvar só ids (cartas, artefatos, pontos, encontros), nunca dados do
  catálogo, para mudar uma carta no JSON do catálogo não quebrar saves
  antigos.
- Salvar automaticamente fora de combate (ao voltar ao mapa, ao comprar).
  Save no meio de um combate não entra nesta etapa.
- Campo de versão no save, para migrações futuras.

## Critérios de aceite

- Fechar e reabrir o jogo mantém todo o progresso de campanha.
- Um card_id que não existe mais no catálogo não quebra o load (é
  ignorado, com aviso no console).

Nota: se ficar chato perder progresso a cada sessão de playtest, esta etapa
pode ser antecipada para logo depois da Etapa 1 ou 2.

---

# ETAPA 9 — Playtest de integração da campanha

## Objetivo

Jogar um trecho de campanha do começo ao fim: explorar o mapa → combates →
ouro/cartas → mercadores → montar decks diferentes → artefatos → eventos →
salvar e continuar.

## Perguntas do playtest

- Explorar o mapa parece livre, ou na prática todo mundo faz o mesmo
  caminho?
- Vale a pena ter mais de um deck? Algum combate pede um deck diferente do
  "melhor deck geral"?
- Colecionar cartas dá vontade de explorar mais pontos do mapa?
- A economia (ouro ganho vs. preços) deixa as compras parecendo escolhas,
  ou dá para comprar tudo sem pensar?
- Perder um combate parece uma consequência justa sem ser punitiva demais?

## Critério de sucesso da fase

Ao final desta fase, deve ser possível começar uma campanha nova, explorar
livremente um mapa pequeno, vencer combates com decks diferentes montados a
partir da coleção, comprar cartas e artefatos, resolver eventos, fechar o
jogo e continuar de onde parou.

---

# Perguntas de design em aberto

Decidir com o usuário quando a etapa correspondente chegar (não antes),
e então registrar a decisão neste documento:

- Formato do mapa: grafo de pontos clicáveis na versão crua (Etapa 1).
  Personagem andando livremente pode vir depois, só mudando a
  apresentação.
- Consequência de derrota num combate (Passo 1.4/1.5).
- Recompensa de combate repetido: decidido na Etapa 4 (metade do ouro).
  Revisitar se virar farm.
- Regras de deck mais rígidas (tamanho mínimo/máximo, limite de cópias)
  podem voltar a ser discutidas depois. Hoje são permissivas (Etapa 3).
- Artefatos globais ou equipados por deck (Etapa 6).
- De onde vêm as unidades aliadas iniciais de um combate. Hoje
  `test_battle.json` já pré-posiciona aliados, e unidades também entram via
  cartas de summon. Na campanha, o encontro define os aliados iniciais, ou
  o jogador começa só com o que o deck invoca?
- Cartas de summon vão para o cemitério (`Deck.bury()`) e saem do combate.
  Isso continua igual, mas vale reavaliar quando decks forem montados à mão.
- `ALLY_STAT_MULTIPLIER` (aliados nascem com 2× ATK/HP) e o loop de waves
  são compensações temporárias do sandbox. Revisar quando encontros
  definirem sua própria dificuldade.

---

# O que NÃO implementar ainda

- Arte/animações/VFX/som de mapa e telas novas (polimento vem depois do
  loop validado).
- Editor visual de mapa.
- Múltiplos personagens/classes jogáveis.
- Árvores de diálogo ramificadas.
- Elites/bosses com mecânicas próprias (combates continuam usando o que já
  existe).
- Balanceamento definitivo de economia, raridade de cartas e preços.
- Raridade/pacotes de cartas (booster) — só se o design pedir depois.
- Multiplayer/troca de cartas.

---

# Regra para futuras mecânicas

Antes de adicionar uma nova mecânica de campanha, perguntar:

1. Ela pode ser construída com as primitivas existentes (`CampaignState`,
   coleção, `DeckList`, o mesmo `Deck`/`Mana`/`BattleState` de sempre)?
2. Ela cria uma decisão nova para o jogador?
3. Ela interage com o que já existe (coleção, decks, mapa, artefatos)?
4. Ela vale a complexidade adicional?

Se uma nova mecânica puder ser expressa pelas existentes, não criar uma
nova mecânica.

---

# Ordem de execução

Executar nesta sequência, uma etapa (ou, na Etapa 1, um passo) por vez:

```text
1. Overworld cru (passos 1.1 → 1.6)
   ↓
2. Coleção de cartas
   ↓
3. DeckList e escolha de deck
   ↓
4. Mercador de cartas e ouro
   ↓
5. DeckBuilder
   ↓
6. Artefatos
   ↓
7. Eventos
   ↓
8. Save/load
   ↓
9. Playtest de integração
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

O objetivo é transformar o sandbox de combate isolado numa campanha
jogável, com o mínimo de peças novas que isso exige, e descobrir jogando
se colecionar cartas e montar decks diferentes para combates diferentes
produz decisões interessantes antes de aprofundar qualquer uma dessas
peças.

Se uma implementação tecnicamente elegante não gerar novas decisões de
jogador, ela não é prioridade.
