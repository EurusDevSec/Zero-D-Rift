---
name: zero-drift-init
description: Initialize or audit Zero D-Rift project-agent state when the user says /init, start, or asks to onboard a fresh session; does not deploy infrastructure.
---

# Zero D-Rift Init

1. Read root `AGENTS.md`, `docs/README.md`, the canonical ver3, roadmap and active context.
2. Inspect Git HEAD/status and repository structure before trusting recorded state.
3. Classify the repository as planning, implementation, experiment or release state.
4. Validate that active-context pointers exist and contain project-specific data.
5. If onboarding files are missing and the user asked to initialize, create only
   the minimum project-state documents required by the root constitution.
6. Report current phase, active spec, next action, blockers and evidence state.

Do not load nested Eurus sample memory, create AWS resources, install controllers,
commit or push as part of initialization.

