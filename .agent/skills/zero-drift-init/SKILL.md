---
name: zero-drift-init
description: Initialize or audit Zero D-Rift project-agent state when the user says /init, start, or asks to onboard a fresh session; does not deploy infrastructure.
---

# Zero D-Rift Init

1. Read [context governance](../../references/context-governance.md), root
   `AGENTS.md`, active context and its referenced current learning status.
2. Inspect live Git HEAD/status and repository structure before trusting any
   checkpoint. Run `../../scripts/check-context.ps1` when PowerShell is available.
3. Classify the request and repository as planning, implementation, experiment
   or release work, then load only the required canonical/spec/ADR sections.
4. Validate that active-context pointers exist and that the packet identifies one
   next safe action, evidence target and authority boundary.
5. If onboarding files are missing and the user asked to initialize, create only
   the minimum state documents required by the root constitution.
6. Report verified state, drift, active task, next action, blockers and evidence.

Do not create AWS resources, install controllers, commit or push as part of
initialization.
