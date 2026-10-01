---
name: zero-drift-checkpoint
description: Save a verified Zero D-Rift session checkpoint and handoff state without automatically staging, committing, pushing, or provisioning resources.
---

# Zero D-Rift Checkpoint

1. Read [context governance](../../references/context-governance.md), then capture
   changed files, live Git state, verification, failures, learning and cost/resources.
2. Classify new information into active state, ADR/canonical decision, evidence,
   learning, milestone history or disposable detail.
3. Rewrite `.agent/workflows/active_context.md` around the next safe action. Do
   not append chronology, duplicate canonical text or store Git HEAD as live truth.
4. Update `learning/CURRENT_STATUS.md` only from demonstrated evidence; append the
   full learning log, cold memory and history only when their specific criteria apply.
5. Run `../../scripts/check-context.ps1`; show warnings, exact modified/untracked
   files and `git status --short` separately.
6. Do not run `git add .`, commit or push. If explicitly requested, stage only the
   reviewed file list and report verification state.
7. Do not mark a feature/phase complete unless functional and learning DoD pass.

