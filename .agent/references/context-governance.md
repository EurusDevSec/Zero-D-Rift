# Zero D-Rift Context Governance

This reference defines how project context stays useful across chats and phases.
It is read by session-start and checkpoint workflows, not by every ordinary task.

## Governing invariant

Provide the minimum sufficient, verified context for the next decision. Expand
when task or risk requires more evidence; contract again at checkpoint.

Shortness is not the goal by itself. A context packet is healthy when a fresh
session can identify the current outcome, verified state, open decisions, next
safe action, required evidence and authority boundary without reading history.

## Information lifecycle

| Class | Canonical home | Lifecycle |
|---|---|---|
| Stable rules | `AGENTS.md`, accepted ADRs, canonical scope | Load through routing when applicable |
| Active working set | `workflows/active_context.md`, active SPEC/task | Rewrite as the next decision changes |
| Current learning state | `learning/CURRENT_STATUS.md` | Keep concise; update only from demonstrated evidence |
| Durable learning/history | `learning/LEARNING_LOG.md`, `workflows/history_archive.md` | Append meaningful entries; read on demand |
| Operational evidence | code, tests, run manifests, logs, inventory | Store at the evidence path; never replace with prose claims |
| Ephemeral detail | chat, exploration notes, redundant output | Promote what matters, then discard or compact |
| Live external state | Git, AWS, Kubernetes, billing, quotas | Re-query before relying on it |

One fact has one canonical home. Other files may state its current consequence and
link to it, but must not maintain a second independently editable copy.

## Adaptive loading

Start every new session with active context, live Git and current learning status.
Then load according to intent:

- Explanation or status: only the sources needed to support the answer.
- Coach or micro-lab: current learning objective, relevant task and one focused
  technical source; do not preload unrelated controllers or later phases.
- Plan/build/review: active task, applicable acceptance/negative cases and linked
  decisions. Expand to the full spec only when the decision is phase-wide.
- L3/L4 or destructive work: full governing contract plus cost, identity,
  teardown, evidence and authority sources. Recheck live external state.
- Historical comparison: history/archive only when explicitly required.

When unsure, load the smaller set first and expand after identifying a concrete
missing fact. Do not repeatedly reread unchanged large files in one turn.

## Active-context content test

Keep an item in active context only when removing it could cause the next session
to choose the wrong task, violate a boundary, repeat an unresolved decision or
misstate current evidence.

Active context should contain:

1. Active phase, spec, parent task, collaboration mode and authority boundary.
2. A small set of verified facts that affect current work.
3. Open decisions or blockers.
4. One next safe action and the evidence it must create.
5. Pointers that tell the next session what to read if deeper context is needed.
6. Parked work only when it could otherwise contaminate the active scope.

It should not contain transcripts, completed-task narration, raw command output,
full ADR/spec text, detailed learning history or an authoritative embedded Git
hash. A Git hash may appear in immutable evidence, not as live state in this index.

## Checkpoint contraction

Checkpointing is classification and rewrite, not append-only summarization:

1. Re-query Git and any relevant external state.
2. Verify claims against code, commands and evidence paths.
3. Classify new information:
   - affects the next decision -> active context;
   - durable decision -> ADR or canonical document;
   - observed result -> evidence;
   - demonstrated learning -> learning log and current status;
   - completed milestone -> history;
   - expired or redundant detail -> discard.
4. Rewrite active context so it describes the next safe working state.
5. Run `.agent/scripts/check-context.ps1` and show live Git status separately.

Do not force every category to change at every checkpoint. Update only what the
session actually changed and proved.

## Chat and compaction policy

- Use one chat for one coherent outcome, normally one parent task.
- Continue the chat while new turns materially depend on the same reasoning trail.
- Before compaction, checkpoint any state that would be costly or risky to lose.
- Compact when the same outcome continues; start a fresh chat when the outcome,
  phase gate or write scope changes, or when accumulated history causes drift.
- A fork preserves old transcript and is for a genuine branch, not a clean handoff.
- Chat history and Codex memory are recall aids, never the sole project record.

No fixed context percentage or line count determines correctness. File-size and
context-usage thresholds are warnings that trigger review, not automatic proof of
bad context.

## Feedback loop

When the agent repeatedly reads irrelevant files, trusts stale state, reopens a
settled decision or misses a source, treat it as a harness defect. Fix the closest
router, skill or deterministic check rather than adding broad instructions to
every prompt. Add a permanent rule only for a repeated or high-risk failure.
