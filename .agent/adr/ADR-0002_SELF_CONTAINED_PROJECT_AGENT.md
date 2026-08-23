---
id: ADR-0002
title: Remove the reusable framework source after project initialization
status: ACCEPTED
date: 2026-08-23
supersedes: ADR-0001 decision item 1
---

# Context

P0 copied and adapted the required constitution, skills, roadmap, workflow,
memory, learning and Definition of Done into the root `AGENTS.md` and `.agent/`.
The reusable framework source was no longer referenced by the active command
router or needed for fresh-session hydration. Keeping it also retained sample
state that could be mistaken for project truth.

# Decision

Remove the reusable framework source from the Zero D-Rift repository and keep
the root project-agent instance self-contained.

The project retains:

- root `AGENTS.md` as the session entrypoint;
- `.agent/skills/` for project commands;
- `.agent/workflows/` for live state and handoff;
- `.agent/docs/`, `.agent/specs/`, `.agent/adr/` and `.agent/learning/` for
  planning, decisions and learning evidence.

# Consequences

- Fresh sessions have one unambiguous source of project-agent state.
- The repository no longer carries unrelated framework benchmarks or sample memory.
- Future framework improvements must be ported deliberately rather than pulled
  automatically.
- Removing the framework does not change the thesis scope or implementation.

# Evidence

- P0 project-agent commit: `52c02ce`.
- Framework removal commit: `2a5e6a4`.
- Root command router and all current pointers pass the P1 handoff audit.

