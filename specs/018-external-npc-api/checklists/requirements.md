# Specification Quality Checklist: External NPC Brains — Game-Side Contract API

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-07-01
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- All items pass on first validation.
- The contract is described at capability level (identity read, surroundings read, move command, shared-secret auth, mind lifecycle) without pinning wire formats or module/route names; the exact wire shapes are owned by the shared contract schema referenced in `agentic-realms-npc` feature `001`.
- Terms like "orchestration server", "durable workflow", and "task queue" are used as domain vocabulary for the externally-managed NPC mind (per the feature's premise), kept framework-agnostic rather than naming a specific product.
- Scope correction applied after initial draft: the NPC mind **lifecycle** (start a mind on NPC spawn; terminate the NPC's mind on removal/destruction) is explicitly IN scope (User Stories 4 & 5; FR-024–FR-029; SC-010–SC-012).
- Ownership clarification applied: mind-start idempotency (exactly one mind per NPC) and mind-terminate safety (no-op on an absent mind) are **guarantees of the orchestration server, not the game**. The game submits deterministic-identity start/terminate requests fire-and-forget, keeps no registry of which NPCs have minds, and performs no existence/duplicate checks (US4/US5, FR-025, FR-026, FR-028, SC-010, SC-011, Key Entities, Assumptions).
- Integration-target clarification applied: the mind lifecycle call is made to the **Temporal server over its HTTP API** (start/terminate a Temporal workflow), and explicitly **not** to the `agentic-realms-npc` worker service. The game and the worker never call each other directly; the two one-way integrations are game→Temporal (lifecycle) and worker→game (contract). Reflected in the Overview, FR-024/FR-027/FR-034/FR-037, Key Entities (Temporal Server vs. Mind Worker Service), Dependencies, and Assumptions.
- Note on "No implementation details / technology-agnostic": the concrete external system **Temporal** is named deliberately per explicit user direction, because the integration target's identity (and the game→Temporal vs. game→worker distinction) is a hard requirement of this integration feature. The Success Criteria (SC-001–012) remain phrased in outcome terms and do not depend on that naming.
