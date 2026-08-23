---
name: zero-drift-checkpoint
description: Save a verified Zero D-Rift session checkpoint and handoff state without automatically staging, committing, pushing, or provisioning resources.
---

# Zero D-Rift Checkpoint

1. Summarize changed files, completed subtasks, verification results, failures,
   learning evidence and cost/resource state.
2. Update `.agent/workflows/active_context.md` with current Git HEAD/dirty state,
   active task, blockers, evidence paths and the next small action.
3. Add only durable lessons to cold memory and meaningful milestones to history.
4. Show `git status --short` and identify untracked/modified files.
5. Do not run `git add .`, commit or push. If the user explicitly requests a
   commit/push, stage only the reviewed file list and report the verification state.
6. Do not mark a feature/phase complete unless its functional and learning DoD
   are satisfied.

