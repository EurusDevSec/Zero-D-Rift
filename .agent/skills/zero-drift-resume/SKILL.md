---
name: zero-drift-resume
description: Resume Zero D-Rift work from a fresh session by validating Git state, active context, and the active task before continuing.
---

# Zero D-Rift Resume

1. Read `.agent/workflows/active_context.md` and the referenced active spec.
2. Compare recorded and current Git HEAD/dirty state.
3. If drift exists, inspect changed files and update the checkpoint understanding;
   do not discard changes or load stale state blindly.
4. Locate the next unchecked subtask and its required mode/evidence.
5. Read only linked ADRs and relevant project documents.
6. Report what is complete, what is unverified, the next bounded action and any
   authority/cost requirement; then continue only within the user's request.

