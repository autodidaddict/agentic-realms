<!--
SYNC IMPACT REPORT
Version change: (unratified template) → 1.0.0
Rationale: Initial ratification. The file was an unpopulated template with no
normative content; this fills it with concrete, testable principles. Treated as
the 1.0.0 baseline (MAJOR) rather than a patch because it establishes governance
from scratch.

Principles defined:
  I.   Cluster-Correct by Default (NON-NEGOTIABLE)
  II.  Event-Sourcing Invariants (NON-NEGOTIABLE)
  III. Local-First LiveView Interaction
  IV.  Test-First, Green-Before-Merge
  V.   Clean Git History — No AI Attribution (NON-NEGOTIABLE)
  VI.  Idiomatic Phoenix & Deliberate Simplicity

Sections defined:
  - Engineering Constraints (Technology & Runtime)
  - Development Workflow & Quality Gates

Templates reviewed for alignment:
  ✅ .specify/templates/plan-template.md — generic "Constitution Check" gate +
     Complexity Tracking already accommodate these principles; no edit required.
  ✅ .specify/templates/spec-template.md — "Assumptions" + requirements sections
     can carry cluster-semantics (Principle I) and event-sourcing impact
     (Principle II) clarifications; no structural change required.
  ✅ .specify/templates/tasks-template.md — phase/test task structure aligns with
     Principle IV; no edit required.
  ✅ .specify/commands/*.md — no agent-specific identifiers needing genericization.

Deferred TODOs: none.
-->

# Agentic Realms Constitution

## Core Principles

### I. Cluster-Correct by Default (NON-NEGOTIABLE)

All code MUST behave correctly on a multi-node BEAM cluster, never assuming
single-node execution for any shared concern.

- Process discovery and uniqueness for cluster-wide concerns MUST use
  cluster-aware mechanisms (e.g., `Horde.Registry` / `Horde.DynamicSupervisor`,
  `:global`, or a documented strategy). A bare local `Registry` or local
  process name MUST NOT be used for a process that must be unique across the
  cluster. Node-local state is permitted ONLY for genuinely node-local concerns
  (e.g., a LiveView's own socket assigns).
- When a feature's desired cluster behavior is not obvious — singleton vs.
  per-node, where a stateful process runs, partition/netsplit handling, cross-node
  ordering, or duplicate-delivery handling — it MUST be clarified in the spec
  **before** implementation. Specs MUST state the intended cluster semantics for
  every stateful process or coordination point they introduce.

Rationale: the system runs clustered; single-node assumptions are silent bugs
until a second node exists. Forcing cluster semantics into the spec surfaces
them at design time, not in production.

### II. Event-Sourcing Invariants (NON-NEGOTIABLE)

The write side is event-sourced (Commanded + EventStore); its guarantees hold
only if these invariants are never bent.

- Events are immutable and append-only. Persisted events are NEVER mutated or
  selectively edited in place.
- An aggregate is the SOLE writer of its own stream. Commands validate against
  current aggregate state; state changes are expressed only as emitted events
  applied through `apply/2`.
- Read models are derived state: they MUST be written only by projectors
  reacting to events — never by ad-hoc writes from command or UI code. Business
  decisions MUST NOT read un-projected/raw event data directly.
- Projectors MUST be idempotent and replay-safe (safe to re-run from position 0
  and to re-handle a redelivered event) — e.g., via `on_conflict` and
  deterministic identifiers.
- Stream identity and prefix conventions are stable contracts; changing them is
  a breaking change. Purging or restructuring event data follows the project's
  event-log policy (destroyable pre-launch; explicit, scoped migration once
  production data exists).

Rationale: auditability, replay, and rebuildable read models all depend on
these rules being absolute, not situational.

### III. Local-First LiveView Interaction

LiveView interactions MUST minimize server round-trips.

- Behavior that does NOT require authoritative server state or persistence
  SHOULD execute in the browser (JS hooks, CSS, client-side commands,
  `phx-update="ignore"`, optimistic UI) rather than via a server round-trip.
- A server round-trip is justified only when the interaction needs server
  authority: validation, persistence, cross-client broadcast, secrets, or data
  the client must not hold. When a round-trip is chosen for an interaction that
  could plausibly be local, the reason MUST be stated (in the plan or a code
  comment).

Rationale: round-trips cost latency and server work and degrade under load and
network jitter; local execution is faster and more resilient.

### IV. Test-First, Green-Before-Merge

- Every aggregate (`execute`/`apply`), projector, context function, and
  integration path MUST have tests, written alongside or before the
  implementation they cover.
- `mix precommit` (`compile --warnings-as-errors`, `format`, `test`) MUST pass
  before any change is merged. Warnings are errors. Tests MUST NOT be silently
  skipped or left pending.
- Pure logic (aggregates, parsers, generators) MUST be unit-testable without the
  database; database/Commanded-dependent paths use the established `:commanded`
  + Ecto sandbox harness.

Rationale: the event-sourced, clustered design has many invariants that only a
green test suite keeps steady over time.

### V. Clean Git History — No AI Attribution (NON-NEGOTIABLE)

Commits and pull requests MUST NEVER contain AI or tool attribution or
co-authorship.

- No `Co-Authored-By:` trailers, no "Generated with …" / "Co-authored by <tool>"
  lines, no assistant signatures — in any commit message, PR title, or PR body.
- Commit messages describe the change and its rationale in the author's voice.

This rule admits NO exception.

Rationale: project history reflects human authorship and intent; attribution
noise is unwanted and, once pushed, costly to remove.

### VI. Idiomatic Phoenix & Deliberate Simplicity

- Follow Elixir/Phoenix idioms and the existing project structure: bounded
  contexts, OTP supervision trees, Ecto for read models, and function-level
  style matching the surrounding code.
- A new runtime dependency MUST be justified by a real need not met by the
  standard library or existing dependencies. Prefer the simplest design that
  satisfies the spec; apply YAGNI.
- Significant domain events SHOULD be observable (structured logs and/or
  in-world witness entries). Supervised processes MUST be able to rebuild their
  state on restart rather than relying on never crashing.

Rationale: consistency and simplicity keep a clustered, event-sourced codebase
maintainable.

## Engineering Constraints (Technology & Runtime)

- **Stack**: Elixir/OTP + Phoenix LiveView; Commanded + EventStore (PostgreSQL)
  for the write side; Ecto + PostgreSQL for read models; Horde for cluster-wide
  registries/supervisors; Phoenix.Presence for connection state.
- **Two stores**: the event store is the source of truth; the read-model
  database is derived. Code MUST respect the separation — no business reads from
  raw event tables, and no writes to read models outside projectors.
- **Destructive event-store operations** (e.g., hard stream deletes) MUST be
  explicitly justified, scoped to the data in question, and gated behind a
  deliberate flag. They are never a default behavior.

## Development Workflow & Quality Gates

- **Spec-driven**: substantial features flow specify → (clarify) → plan → tasks
  → implement. The plan's Constitution Check MUST pass before implementation,
  and the spec MUST resolve cluster semantics (Principle I) and event-sourcing
  impact (Principle II) before coding begins.
- **Branch + gate**: work happens on feature branches; `mix precommit` is the
  merge gate (Principle IV).
- **Review**: code review MUST verify constitution compliance. Any justified
  deviation is recorded in the plan's Complexity Tracking with its rationale and
  the rejected simpler alternative; otherwise the change is revised to comply.

## Governance

This constitution supersedes ad-hoc conventions. When a principle and a
convenience conflict, the principle wins; the remedy is to amend the spec, plan,
or code — never to quietly dilute, reinterpret, or ignore a principle. Changing
a principle itself requires a constitution amendment, not a one-off exception.

- **Amendments**: proposed via a pull request that edits this file, accompanied
  by an updated Sync Impact Report and any dependent-template updates.
- **Versioning** (semantic): MAJOR = remove or incompatibly redefine a
  principle/governance rule; MINOR = add a principle/section or materially expand
  guidance; PATCH = clarifications and wording with no semantic change.
- **Compliance**: every plan runs the Constitution Check; reviewers confirm
  adherence before merge. Runtime and agent guidance lives in `CLAUDE.md` and the
  current feature plan it references.

**Version**: 1.0.0 | **Ratified**: 2026-06-09 | **Last Amended**: 2026-06-09
