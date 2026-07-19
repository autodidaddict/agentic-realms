# Architecture Decision Records

Cross-cutting architecture decisions that span (or outlive) a single feature
spec. Feature-scoped design lives under `specs/<NNN-feature>/`; ADRs capture the
durable "why" behind decisions that multiple features depend on.

Each ADR is immutable once **Accepted** — supersede it with a new ADR rather than
rewriting history. Statuses: `Proposed` → `Accepted` → (`Superseded by NNNN` |
`Deprecated`).

| # | Title | Status |
|---|---|---|
| [0001](0001-npc-autonomy-separation-of-responsibilities.md) | NPC Autonomy & Separation of Responsibilities | Accepted |
| [0002](0002-roll-our-own-combat-resolution.md) | Roll Our Own Combat Resolution (No Third-Party Rules Dependency) | Accepted |
| [0003](0003-srd-5-2-default-ruleset.md) | SRD 5.2 as the Default Ruleset (5.1 Divergences as Explicit Opt-Ins) | Accepted |
