# ZERO D-RIFT — PROJECT AGENT CONSTITUTION

This repository is a graduation-thesis project and a learning portfolio. Agents
must help the owner build, verify, understand, and explain the system; they must
not optimize only for producing artifacts quickly.

## 1. Adaptive session hydration

Context is a bounded working set, not an archive. Start with the smallest
verified state needed for the request, then expand according to task and risk.

At the beginning of a new session:

1. Read `.agent/workflows/active_context.md`.
2. Check `git status --short` and `git rev-parse HEAD`; live Git overrides any
   checkpoint snapshot.
3. Read the `current_learning` file referenced by active context. Do not load the
   full learning log unless the task is a learning review or historical audit.
4. Identify the user intent, current task and risk before loading more context.
5. For planning, build, review or verification, read the active spec sections
   governing the current task, its acceptance criteria and negative boundaries.
   Read the full spec when phase-wide or L3/L4 decisions require it.
6. Read only the ADRs and project documents required by that task. Do not scan
   history, `docs/archive/` or non-canonical governance records unless requested.

Follow `.agent/references/context-governance.md` for expansion, contraction and
freshness rules. Do not claim hydration has a fixed token count, cache discount
or duration.

## 2. Document authority

When documents disagree, use this order:

1. The school-approved proposal controls the administrative title and approved
   research boundary.
2. `docs/de_cuong_tot_nghiep_ver3.md` controls implementation scope, hypotheses,
   metrics, acceptance criteria, cost ceiling, and schedule.
3. `.agent/adr/` controls approved technical decisions that remain inside ver3.
4. The active `.agent/specs/SPEC-*.md` controls the current feature contract.
5. Code, test output, raw data, and AWS inventory are operational evidence.
6. `.agent/workflows/active_context.md` is only a current-state index.

Files under `docs/governance/` and `docs/archive/` are records, not implementation
specifications. See `docs/README.md`.

## 3. Context governance

- Keep one canonical home for each fact. Active context summarizes impact and
  links to the source; it does not copy whole SPEC, ADR, evidence or history text.
- Treat Git, AWS, cluster, cost, quota and runtime state as live observations that
  must be rechecked, not durable facts carried indefinitely between sessions.
- At checkpoint, rewrite the active working set: keep what changes the next safe
  action, promote durable decisions, move evidence/history to their proper files,
  and discard expired detail. Do not append a session transcript.
- Load context progressively. A simple question should not trigger the same reads
  as an AWS apply, recovery trial or phase audit.
- Use one chat per coherent outcome, normally one parent task. Compact only when
  continuing the same outcome; checkpoint and start a new chat when the outcome
  or scope changes.

## 4. Command router

| User intent | Read and follow |
|---|---|
| `/init`, `start`, `đầu ngày` | `.agent/skills/zero-drift-init/SKILL.md` |
| `/resume`, `continue`, `tiếp tục` | `.agent/skills/zero-drift-resume/SKILL.md` |
| `/learn`, `học`, `micro-lab`, `grill-me` | `.agent/skills/zero-drift-learn/SKILL.md` |
| `/spec`, `/plan`, `kế hoạch`, `chia task` | `.agent/skills/zero-drift-plan/SKILL.md` |
| Terraform/HCL, `.tftest.hcl`, state or plan review | `.agent/skills/zero-drift-terraform/SKILL.md` |
| `/test`, `/verify`, `kiểm thử` | `.agent/skills/zero-drift-verify/SKILL.md` |
| `/save`, `checkpoint`, `cuối ngày` | `.agent/skills/zero-drift-checkpoint/SKILL.md` |

For build, review, and ship requests, follow
`.agent/workflows/main-workflow.md` and the active spec. Do not infer permission
to deploy paid AWS resources from a planning or learning request.

## 5. Learning-aware delivery

Every feature follows:

`Learn -> Micro-lab -> Design -> Spec -> Build -> Verify -> Explain -> Document -> Checkpoint`

Use one of three collaboration modes:

- **Coach:** default for an unfamiliar technology; explain and guide a small lab.
- **Pair:** implement an approved, bounded change and explain each design choice.
- **Executor:** only for mechanical work after architecture and acceptance tests
  are understood and approved.

Crossplane, kro, KEDA, Karpenter, IRSA, and recovery work begin in Coach or Pair
mode. A feature can be functionally complete while its learning gate remains open.

## 6. Safety and evidence

- Never hard-code AWS credentials, tokens, account identifiers, or private data.
- Never create paid AWS infrastructure without an explicit task and cost check.
- Never record `PASS`, a metric, or a cost result without command/run evidence.
- Never discard failed experiment trials; record exclusions with a reason.
- Never run `git add .`, auto-commit, auto-push, or push directly to `main`.
- Commit and push only when the user explicitly requests them after reviewing the
  file list and verification result.
- Use the tiered verification model in `.agent/workflows/main-workflow.md`;
  infrastructure tests are not required to finish in five seconds.
- New technologies or scope changes require an ADR and must remain compatible
  with ver3 scope gates.

## 7. Planning granularity

- Roadmap: all phases through November 2026, with outcome and exit criteria.
- Detailed spec: current phase only; outline the next phase when useful.
- Parent task: normally 2–4 focused hours.
- Subtask: normally 15–60 minutes with an observable result.
- Each spec includes learning objectives, negative boundaries, cost impact,
  verification evidence, and teach-back questions.
