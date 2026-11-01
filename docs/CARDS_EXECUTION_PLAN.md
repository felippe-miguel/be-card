# CARDS_EXECUTION_PLAN.md

## Objetivo

Criar uma nova leva de cartas: invocações para as unidades que ainda não
têm carta e feitiços novos baseados nas mecânicas de combate existentes.
Como no Monster Train, os feitiços devem fazer combo com os efeitos das
criaturas, e o conjunto deve sustentar **4 arquétipos de deck**, cada um
focado em duas mecânicas.

Este plano é **paralelo** ao `CAMPAIGN_EXECUTION_PLAN.md` (não substitui
nenhuma etapa dele). Mesma disciplina: um passo de cada vez, parar para o
usuário testar no editor antes do próximo.

---

# Levantamento (base das decisões)

Feito em 2026-11-01 sobre `data/cards/`, `data/units/` e o código de
eventos/status.

| Mecânica | Cartas (antes deste plano) | Unidades |
|---|---|---|
| Movimento / posição | advance, retreat, reposition, swap, teleport, flank | mobile_unit, charger, sentinel, sniper, predator, knockback, venomous_assassin, vanguard_recruit |
| Força / ATK | enrage, flank, frontline, concentration | berserker, executioner, mobile_unit, revenge, vanguard_recruit, venomous_assassin |
| Morte (`on_death`) | **nenhuma** | death_spawn, explosive, revenge, sacrifice, elder_guardian |
| Block | defend | duelist, herald, elder_guardian |
| Cura / HP | heal | vampiric, sacrifice, elder_guardian, guardian (aura) |
| Poison | poison_dart | venomous, venomous_assassin |
| Weakness | weaken | weakener |
| Burn | ignite | **nenhuma** |
| Stun | stun | **nenhuma** |
| `on_kill` | (strike/fireball finalizam) | executioner, predator |
| `on_summon` | 6 cartas de invocar | herald, elder_guardian, vanguard_recruit |

Observações que motivam o plano:

- **Block nunca expira** (`Unit.block` só cai ao absorver dano), então
  acumular block é um arquétipo viável e falta um payoff para ele.
- **`on_card_played` não tem conteúdo nenhum.** Hoje dispara para *todas* as
  unidades vivas (inclusive inimigas) via `BattleState.fire_event_all()` em
  `Game.finish_card_play()`, sem informar qual carta foi jogada. É o gancho
  do combo "quando você joga um feitiço".
- `on_turn_start`/`on_turn_end` e o efeito `remove_status` também não têm
  conteúdo.

## Arquétipos escolhidos (decisão do usuário)

1. **Manobra** — Movimento + Força.
2. **Vingança** — Morte + Força.
3. **Aflição** — Poison + Weakness (Burn/Stun como controle).
4. **Fortaleza** — Block + Cura.

`on_summon` e `on_kill` ficam como apoio desses arquétipos, não como deck
próprio.

## Limitações do código atual que afetam o design

- **Uma carta só executa `effects[0]`** (`Game._on_card_played()`). Cartas
  com dois efeitos ("mova e ganhe Força") ficam fora deste plano.
- `Game._on_card_played()` só roteia `damage`, `heal`, `block`,
  `apply_status`, `cleanse` para `begin_effect_card()`. `remove_status` e
  `modify_attack` existem em `EffectSystem.apply_basic_effect()` mas não
  são jogáveis como carta ainda.
- Alvos de carta: só `selected_unit` (+ `target_faction`), `all_enemies`,
  `all_allies` (`TargetSystem.get_card_targets()`).
- Mana: `STARTING_MANA = 4`. Cartas de invocar vão para o cemitério
  (`Deck.bury()`), então cada uma é jogada uma vez por combate.
- Aliados recebem `ALLY_STAT_MULTIPLIER = 2` em HP e ATK.
- Arte de carta é opcional (`res://resources/images/cards/<id>.png`; sem
  arquivo, a carta só não mostra arte).

---

# Roadmap

```text
Passo 1 — 20 cartas de invocar                   (só JSON)
Passo 2 — Feitiços só com JSON                   (só JSON)
Passo 3 — Combo com feitiço + Desarmar           (código pequeno + JSON)
Passo 4 — Efeitos novos, um por vez              (código + JSON)
```

---

# PASSO 1 — Cartas de invocar das unidades com mecânica

**Status: implementado, aguardando teste do usuário no editor.**

Só as **20 unidades com mecânica** ganham carta (decisão do usuário). As
12 unidades genéricas/de inimigo (`bandit`, `bat`, `dragon`, `enemy_archer`,
`enemy_mage`, `goblin`, `orc`, `skeleton`, `slime`, `tank`, `troll`,
`wolf`) continuam sem carta — várias são cópias de unidades aliadas
(`enemy_archer`≈`archer`, `enemy_mage`≈`mage`, `bandit`≈padrão do
`lancer`, `bat`≈padrão do `assassin`) e algumas ficariam fortes demais com
o multiplicador ×2 (Dragão: 200 HP / 20 ATK).

Arquivos `data/cards/summon_<unit_id>.json`, mesmo formato dos summons
antigos (`"type": "unit"`, efeito `summon` com `"target":
"selected_position"`). HP/ATK abaixo já com ×2.

| Arquétipo | Unidade | HP/ATK | Custo | Preço (village_market) |
|---|---|---|---|---|
| Manobra | mobile_unit (Unidade Móvel) | 28/8 | 2 | 40 |
| Manobra | charger (Investida) | 32/10 | 2 | 40 |
| Manobra | sentinel (Sentinela) | 36/8 | 2 | 40 |
| Manobra | sniper (Franco-Atirador) | 24/10 | 2 | 40 |
| Manobra | predator (Predador) | 30/12 | 2 | 40 |
| Manobra | knockback (Empurrão) | 30/8 | 2 | 40 |
| Manobra/Aflição | venomous_assassin (Assassino Venenoso) | 32/16 | 3 | 50 |
| Força | berserker | 36/12 | 2 | 40 |
| Força | executioner (Executor) | 36/14 | 3 | 50 |
| Força | vanguard_recruit (Recruta da Linha de Frente) | 28/8 | 1 | 25 |
| Vingança | death_spawn (Ovo de Esqueleto) | 20/4 → Skeleton 40/12 | 2 | 40 |
| Vingança | explosive (Explosivo) | 24/8 | 1 | 25 |
| Vingança | revenge (Vingança) | 24/8 | 1 | 25 |
| Vingança | sacrifice (Sacrifício) | 24/8 | 1 | 25 |
| Aflição | venomous (Venenoso) | 28/8 | 2 | 40 |
| Aflição | weakener (Enfraquecedor) | 28/8 | 2 | 40 |
| Fortaleza | duelist (Duelista) | 32/10 | 2 | 40 |
| Fortaleza | herald (Arauto) | 28/6 | 2 | 40 |
| Fortaleza | vampiric (Vampírico) | 32/10 | 2 | 40 |
| Fortaleza | elder_guardian (Guardião Ancião) | 44/6 | 3 | 50 |

Unidades de Vingança custam 1 de propósito (fodder para sacrifício).
Regra de preço: custo 1 → 25, custo 2 → 40, custo 3 → 50 (segue os summons
já existentes no mercador).

## Critérios de aceite

- As 20 cartas aparecem na Feira da Vila com nome e preço.
- Compradas e postas num deck, cada uma invoca a unidade certa na célula
  escolhida.
- `on_summon` funciona ao invocar (Recruta na Front ganha Strength 2,
  Arauto dá Block aos adjacentes, Guardião Ancião ganha Block 5).
- Ovo de Esqueleto vira Skeleton ao morrer.

---

# PASSO 2 — Feitiços só com JSON

Todos usam efeitos e alvos já roteados por `Game._on_card_played()`; não
precisa de código. Tipo `"attack"` para dano/debuff ofensivo, `"skill"`
para o resto (mesmo critério das cartas atuais). Adicionar também ao
`village_market.json` (preço sugerido: ~20 para custo 0–1, ~30–35 para
custo 2, ajustar com o usuário).

| id sugerido | Nome | Arquétipo | Custo | Efeito (JSON) |
|---|---|---|---|---|
| `war_cry` | Grito de Guerra | Manobra/Força | 2 | `apply_status`, `all_allies`, `strength`, 1 |
| `ritual` | Ritual | Vingança | 0 | `damage`, `selected_unit`, `target_faction: ally`, 99 (mata o aliado e dispara o `on_death` dele) |
| `toxic_cloud` | Nuvem Tóxica | Aflição | 2 | `apply_status`, `all_enemies`, `poison`, 2 |
| `curse` | Maldição | Aflição | 2 | `apply_status`, `all_enemies`, `weakness`, 1 |
| `spreading_flames` | Chamas Alastrantes | Aflição | 2 | `apply_status`, `all_enemies`, `burn`, 2 |
| `wall` | Muralha | Fortaleza | 2 | `block`, `all_allies`, 4 |
| `fortify` | Fortificar | Fortaleza | 2 | `block`, `selected_unit`, `target_faction: ally`, 12 |
| `mass_heal` | Cura em Massa | Fortaleza | 2 | `heal`, `all_allies`, 4 |

Pontos a verificar ao implementar:

- `Ritual`: confirmar que dano em aliado via `selected_unit` +
  `target_faction: ally` funciona de ponta a ponta (click, preview do
  `UnitView`, morte, `on_death`, `check_battle_end()` se era o último
  aliado). Pelo código (`TargetSystem.get_card_targets()` /
  `matches_target_faction()`) deve funcionar.
- Cartas `all_enemies`/`all_allies` com `apply_status` entram em
  `PendingAction.CONFIRM` via `begin_effect_card()`; confirmar que o
  preview (`UnitView.arm_effect_preview()`) não quebra com `apply_status`.

## Critérios de aceite

- Cada carta aparece no mercador, entra num deck e faz o que descreve.
- Ritual matando Ovo de Esqueleto/Explosivo/Vingança/Sacrifício dispara o
  `on_death` correspondente.

---

# PASSO 3 — Combo com feitiço (`on_card_played`) + Desarmar

**Aprovado pelo usuário.** Mudança pequena de código, depois conteúdo.

## Código

1. `Game.finish_card_play()` passa um contexto para o evento, por exemplo
   `{"card_type": card.data.type}` (ou um booleano `is_spell`), e dispara
   **só para aliados** — quem jogou a carta é o jogador. Hoje usa
   `fire_event_all("on_card_played")`, que inclui inimigos; trocar por um
   disparo por facção (adicionar parâmetro de facção ao `fire_event_all()`
   ou um helper equivalente — a menor mudança coerente).
2. `BattleState.trigger_condition_met()` hoje só conhece a chave `row`.
   Adicionar **uma** chave nova, `card_type`, comparada com o contexto do
   evento. "Feitiço" = qualquer carta que não seja de invocar (`type !=
   "unit"`); decidir na implementação se a condição é
   `{"card_type": "spell"}` (traduzido) ou lista de tipos — preferir
   `"spell"` como valor especial, que é o que o design pede. Para isso
   `trigger_condition_met()` precisa receber o contexto do evento
   (hoje recebe só `unit` e `condition`).
3. Liberar `remove_status` e `modify_attack` em `Game._on_card_played()`
   (adicionar ao `match` que chama `begin_effect_card()`), e garantir que
   o preview não quebre com eles.
4. Atualizar `docs/ARCHITECTURE.md` (Events and triggers: contexto de
   `on_card_played`, chave de condição nova; Cards: efeitos roteados).

Não transformar isso num motor genérico de condições (ver princípio de
"menor primitiva" do `MECHANICS_EXECUTION_PLAN.md`).

## Conteúdo — unidades novas de combo (uma por arquétipo)

Unidades novas em `data/units/` + carta de invocar de cada uma (custo 2,
preço 40). Stats sugeridos na faixa das unidades de mecânica (antes do ×2:
~12–16 HP, 3–4 ATK), ajustar no teste.

| id sugerido | Nome | Arquétipo | Trigger |
|---|---|---|---|
| `battle_apprentice` | Aprendiz de Batalha | Manobra/Força | `on_card_played` + `card_type: spell` → `apply_status` `self` `strength` 1 |
| `cultist` | Cultista | Vingança | `on_card_played` + spell → `block` `self` 2 |
| `alchemist` | Alquimista | Aflição | `on_card_played` + spell → `apply_status` `lane_enemies` `poison` 1 |
| `cleric` | Clérigo | Fortaleza | `on_card_played` + spell → `heal` `adjacent_allies` 2 |

## Conteúdo — carta

| id sugerido | Nome | Arquétipo | Custo | Efeito |
|---|---|---|---|---|
| `disarm` | Desarmar | Aflição/controle | 1 | `remove_status`, `selected_unit`, `target_faction: enemy`, `strength` |

## Critérios de aceite

- Jogar um feitiço dispara o trigger das 4 unidades de combo; jogar uma
  carta de invocar **não** dispara.
- Unidades inimigas com `on_card_played` (se alguma surgir via wave) não
  reagem às cartas do jogador.
- Desarmar remove a Força de um inimigo (ex.: Berserker inimigo).
- O preview de turno continua correto depois dos triggers.

---

# PASSO 4 — Efeitos novos (um de cada vez, parando para teste entre eles)

Cada um é um efeito novo em `EffectSystem.apply_basic_effect()` (ou caso
especial, se precisar de estado do `BattleState`), roteado em
`Game._on_card_played()`, com a carta JSON correspondente. Ordem sugerida
(do mais simples ao maior):

| Ordem | id sugerido | Nome | Arquétipo | Custo | Efeito novo |
|---|---|---|---|---|---|
| 4.1 | `double_strength` | Fúria Dobrada | Força | 1 | Dobra os stacks de Strength de um aliado |
| 4.2 | `detonate_toxin` | Detonar Toxina | Aflição | 1 | Causa dano igual ao Poison do alvo inimigo e remove o Poison |
| 4.3 | `shield_bash` | Golpe de Escudo | Fortaleza | 1 | O aliado escolhido causa dano igual ao próprio Block no primeiro inimigo da lane dele (o Block não é consumido — decidir no teste) |
| 4.4 | `raise_dead` | Reerguer | Vingança | 2 | Revive o último aliado morto numa célula vazia escolhida |

Notas:

- 4.3 precisa de um alvo derivado (primeiro inimigo da lane do aliado);
  reaproveitar `TargetSystem` em vez de procurar no grid à mão.
- 4.4 é o maior: precisa que o `BattleState` guarde os aliados mortos
  (id da unidade) — `BattleState.on_unit_died()` é o ponto natural — e um
  fluxo de clique de célula como o do summon (`PendingAction.SPAWN`).
  Lembrar de `clone_for_simulation()` se o estado novo afetar a simulação.
- Atualizar `docs/ARCHITECTURE.md` (lista de efeitos) a cada efeito novo.

---

# Fora do escopo deste plano

- Cartas com múltiplos efeitos (`effects[1..]`).
- Unidades de Burn e Stun para o arquétipo Aflição (próxima leva).
- Cartas de invocar para as 12 unidades genéricas/de inimigo.
- Arte das cartas novas.
- Balanceamento fino de custo/preço (ajustar depois dos testes).
- Decks iniciais por arquétipo em `data/campaign/starting_decks.json`
  (pode virar um passo extra depois do Passo 4, se o usuário quiser).
