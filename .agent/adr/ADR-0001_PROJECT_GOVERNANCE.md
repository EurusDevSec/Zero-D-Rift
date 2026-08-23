---
id: ADR-0001
title: Project-specific Eurus state and evidence-based workflow
status: ACCEPTED
date: 2026-08-23
---

# Context

The reusable `eurus-agent/` submodule contains sample project state, broad
auto-pilot rules, automatic Git push behavior and timing/token claims that are
not valid guarantees for an AWS/Kubernetes graduation project. Agents normally
start from the Zero D-Rift repository root, where the nested constitution is not
a reliable project entrypoint.

The owner also requires learning and explainability to progress alongside
delivery, especially for unfamiliar technologies such as Crossplane and kro.

# Decision

1. Keep `eurus-agent/` as reusable framework source.
2. Maintain a project-specific `AGENTS.md` and `.agent/` at repository root.
3. Use ver3 as the only implementation-scope SSOT; project-agent documents route
   to it but do not supersede it.
4. Use rolling-wave planning and detail only the current phase.
5. Separate functional completion from learning completion.
6. Use L0–L4 verification tiers instead of a universal five-second limit.
7. Require evidence before recording pass states or research results.
8. Require explicit owner approval for Git commit/push and paid AWS actions.

# Consequences

## Positive

- New sessions have a short, project-correct entrypoint.
- Historical drafts cannot silently broaden the implementation.
- Progress can be resumed without replaying chat transcripts.
- The workflow measures both delivery and comprehension.
- AWS cost and Git mutations remain under owner control.

## Trade-offs

- Root project-state files must be maintained when a phase changes.
- Framework updates do not automatically overwrite project adaptations.
- Teach-back and evidence collection add time, which is budgeted into the weekly
  25–30 hours.

# Revisit conditions

Revisit only if the project moves to another agent runtime, the school changes
the approved scope, or the root project-state structure creates demonstrated
maintenance overhead.

