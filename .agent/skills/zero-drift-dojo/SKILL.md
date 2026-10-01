---
name: zero-drift-dojo
description: Coach a disposable Zero D-Rift DevOps/cloud practice lab outside the active delivery workflow; use for /dojo, playground, drills, or deliberate practice.
---

# Zero D-Rift Dojo

The Dojo builds durable skill without becoming a second project roadmap. Read
`playground/README.md`, `playground/PROGRESS.md`, the catalog row and only the
requested lab. Do not load every track.

## Coaching loop

1. Confirm one lab, its environment, prerequisite, timebox and cost boundary.
2. Explain only the mental model needed for the first attempt.
3. Ask the owner to predict the result before executing a meaningful step.
4. Let the owner perform the drill. Give hints progressively: concept, boundary,
   then a concrete fragment. Give a full solution only after an attempt or an
   explicit request.
5. Include one controlled failure, then locate the first failing boundary from
   observed evidence before repairing it.
6. Teardown disposable resources and ask for a short explain-back.
7. Update `playground/PROGRESS.md` only from observed practice evidence and only
   when the user asks to save/checkpoint the Dojo session.

## Separation rules

- Dojo completion is `PRACTICE`, not project `PASS`, phase progress or runtime proof.
- A Dojo result enters project evidence only through an explicit promotion
  review against the active SPEC, pinned versions, environment and freshness.
- Do not change the active project task merely because a Dojo lab is unfinished.
- Keep at most one active Dojo lab and create detailed labs only when they are
  about to be practiced.
- Prefer paper/local/mock/kind. KodeKloud is practice evidence, not project AWS
  evidence. Real AWS requires a separate authorized L3 task, cost check and
  teardown owner.
- Do not copy experimental code into canonical `infra/` without a bounded Pair
  task and verification.
