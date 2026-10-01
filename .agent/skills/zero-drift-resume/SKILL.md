---
name: zero-drift-resume
description: Resume Zero D-Rift work from a fresh session by validating Git state, active context, and the active task before continuing.
---

# Zero D-Rift Resume

1. Read [context governance](../../references/context-governance.md), active
   context and its referenced current learning status.
2. Query live Git HEAD/status and run `../../scripts/check-context.ps1` when
   PowerShell is available. Treat mismatch as drift to investigate, not a reason
   to discard owner changes.
3. Identify the active outcome and risk. Load the current task plus applicable
   acceptance/negative cases; read the full spec only for phase-wide or L3/L4 work.
4. Expand to linked ADRs/project documents only when a concrete decision needs them.
5. If the packet is stale, duplicated or cannot identify the next safe action,
   report the defect and repair the checkpoint before risky implementation.
6. Report verified, unverified, blocker, next action, evidence and authority/cost
   boundary; continue only within the user's request.

