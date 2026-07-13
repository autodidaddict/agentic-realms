# 1. NPC Autonomy & Separation of Responsibilities

- **Status**: Accepted
- **Date**: 2026-07-13
- **Deciders**: Kevin Hoffman
- **Related**: features 009 (NPC behaviors), 010 (NPC conversations), 011 (room ticks), 015 (behavior groups), 018 (external NPC brains); Constitution Principles I (Cluster-Correct) & II (Event-Sourcing Invariants)

## Context

NPC autonomy has been built in independent layers that now coexist on the same
NPC, and it was not written down how they divide responsibility:

- **Behaviors / behavior groups (009 / 015)** — data-authored `(trigger, [actions])`
  tuples on NPC blueprints (and rooms), interpreted server-side by
  `AgenticRealms.World.Behaviors.Interpreter` / `ActionExecutor`. Today's
  vocabulary: triggers `player_entered` / `player_left` / `tick`; actions `say`
  / `emote`. Behavior **groups** are named bundles that compose by **union** at
  spawn (`BehaviorGroups.compose/2`) — e.g. `orc` ∪ `shopkeeper`. The effective
  list is frozen onto the clone at spawn.
- **Conversations (010)** — `chat <npc>` produces a server-side, LLM-generated
  reply grounded in the NPC's lore, ephemeral, with read-only tools. Reactive to
  a player's message.
- **Remote brains (018)** — one durable Temporal workflow per NPC. It reads the
  NPC's identity/lore and surroundings and submits actions through an
  authenticated HTTP **contract**. The contract exposes exactly three routes
  today: `GET /api/npc/:id/identity`, `GET /api/npc/:id/surroundings`,
  `POST /api/npc/:id/move`. A brain is started on `EntityCloned{kind: :npc}` and
  terminated on `EntityRemoved`. The game remains the **sole writer** of world
  state (Principle II); the brain is untrusted and reaches the world only through
  the validated contract.

The recurring question — and the trigger for this ADR — is: **when an NPC needs
to do something, which layer owns it?** Concretely: if an orc-shopkeeper sells a
potion, who runs the transaction, and what does the remote brain have to do with
it?

## Decision

Treat NPC autonomy as **three parallel layers on different channels and
timescales**, not a sequential hand-off. Each layer owns a distinct kind of
responsibility, and world mutation always flows through server-authoritative
Elixir.

### The three layers

| Layer | Owns | Cadence | Powered by | Trust |
|---|---|---|---|---|
| **Behaviors / groups** (009/015) | Authored **reflexes & scripted voice** — deterministic stimulus→response | Instant, in-band (event/tick loop) | Plain Elixir (`Behaviors.Interpreter`) | Trusted (in-process) |
| **World mechanics** (core domain) | The **rules of the world** — movement validation, combat resolution, trades, inventory/currency, HP changes | Instant, in-band | Plain Elixir, event-sourced, sole writer | Trusted (in-process) |
| **Remote brain** (018) | **Volition** — open-ended, goal-directed choice and (future) contextual narration that no rule encodes | Slow, out-of-band (Temporal loop) | External LLM/logic, via the validated contract | Untrusted (network, bearer-token) |

### The boundary principle

> **Mechanics are Elixir. The brain supplies intent and reaction — never
> mechanics.**

Anything deterministic and rule-bound (a move's legality, combat math, a trade,
moving an item, changing HP or currency) is executed by regular
server-authoritative Elixir and event-sourced. It needs no LLM and **must not**
be delegated to an external brain, because (a) the game is the sole writer
(Principle II) and (b) an external LLM is slow, costly, and non-deterministic.
The brain's job is the choice with no fixed rule — *whether* to trade, *where* to
wander, *whom* to pursue or flee, *what* to say about what just happened.

### Rules for the seam

When deciding where a new NPC capability belongs:

1. **Guaranteed, local, event-triggered reaction → a behavior.** If an author
   wants it to happen every time, deterministically (a greeting, an ambient
   emote, a canned refusal), it is a behavior. No LLM, instant, frozen at spawn.
2. **A rule of the world → core Elixir domain.** If it mutates world state under
   validation (move, attack resolution, trade, HP/currency), it is a command →
   event → projector, with the aggregate as sole writer. Reused identically
   whether a player, a behavior, or a brain triggers it.
3. **A judgment call → the remote brain.** If it requires weighing the situation
   and choosing among open-ended options, it is the brain's, expressed only
   through contract verbs the game validates.
4. **The brain observes; it does not compute.** The brain learns about mechanical
   outcomes by **perception**, then may choose a follow-up — it never runs the
   mechanic itself.

### How the brain learns what happened (the notification model)

Because the brain only perceives and acts through the contract, it finds out
about a mechanical outcome (a trade, an attack, a player arriving) in one of two
ways:

- **Pull (current 018 behavior)**: the brain's next `surroundings` read reflects
  the new world state; it infers the event from perception.
- **Push (sanctioned extension)**: the game sends the NPC's Temporal workflow a
  **signal** (e.g. `TradeCompleted{buyer, item, price}`) so the brain reacts
  without polling. Temporal signals are the intended mechanism.

In both cases the mechanic already ran in Elixir; the brain is merely informed
and decides a considered next action.

### Worked example — the orc-shopkeeper

Blueprint composed from `orc` ∪ `shopkeeper` behavior groups:

- **Reflexes (behaviors, Elixir, instant):** on `player_entered` it both
  `emote`s "sizes you up with a low growl" (orc) **and** `say`s "Coin first,
  browsing second." (shopkeeper); on `tick` it alternates spitting and
  coin-counting. Guaranteed, no LLM — this is its character and voice.
- **Trade (core mechanics, Elixir):** a player buys a potion. A `buy`/trade
  command validates coin, deducts currency, moves the item, and emits
  `TradeCompleted` — atomic, event-sourced, sole-writer. The brain is not
  involved.
- **Volition (remote brain):** with no customers it wanders to the storeroom to
  "restock" (a `move`); having just sold its last healing draught (learned via
  the `TradeCompleted` signal or the next `surroundings` read) it sets out for
  the market to resupply (a `move`); a menacing, broke loiterer prompts it to
  step behind the counter (a `move`).

The same stimulus can hit several layers at once — a player entering fires the
reflex greeting **and** appears in the brain's next perception so it may choose
to follow — with no conflict, because each layer acts on its own channel and
world mutation always goes through the validated core.

## Consequences

**Positive**
- Security & correctness: money, items, and HP are only ever moved by the
  validated, event-sourced core; an external brain cannot corrupt world state.
- Cost & latency: the LLM is reserved for judgment/narration, not for mechanics
  or guaranteed reactions.
- Testability: mechanics and behaviors are deterministic and unit-testable;
  brain integration is isolated behind the contract.
- Authoring clarity: content creators reach for behaviors for reflexes and voice;
  engineers add mechanics as commands/events; brain capability is a deliberate
  contract expansion.

**Negative / costs**
- Three layers can react to the same stimulus, so overlapping capabilities must
  be assigned deliberately (see "Rules for the seam") to avoid double-acting.
- Perception lag: a pull-only brain reacts a beat late; push signals are the
  remedy but add game→workflow coupling to maintain.

**Neutral — evolving the contract**
Today the layers are cleanly disjoint by capability (behaviors `say`/`emote`,
brain `move`, core does the rest), so there is no conflict. As combat and economy
land, the contract grows new verbs (`attack`, `offer_trade`, eventually `say`)
and new perception (push signals like `TradeCompleted`, `Attacked`,
`PlayerEntered`). Each addition is decided with the seam rules above: guaranteed
reflex → behavior; world rule → core Elixir; judgment → brain verb. Combat
mechanics (damage, death, XP-on-kill) are core Elixir; the brain's role in combat
is deciding *to* fight or flee, once/if the contract exposes those verbs.

## Alternatives considered

- **Fold everything into the remote brain** (the brain drives conversation,
  reflexes, and mechanics). Rejected: violates sole-writer (Principle II), is
  slow/costly for deterministic work, and makes the game depend on an external
  service for basic reactions.
- **Fold the brain back into the game** (server-side autonomous loop instead of
  Temporal). Rejected by feature 018: durable, independently scalable minds are a
  goal, and cluster-side autonomous loops are harder to isolate and scale.
- **Let the brain call core commands directly** (skip the contract). Rejected:
  the contract is the trust boundary; direct access would bypass validation and
  authentication.
