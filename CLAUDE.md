# Claude entrypoint — Zero D-Rift

Read `AGENTS.md` first. It is the shared project constitution for Claude and Codex.
Then follow `.agent/workflows/main-workflow.md`, especially "Codex and Claude
coordination", and `.agent/docs/LINEAR_DELIVERY.md` for the live tracker.

At session start read `.agent/workflows/active_context.md`, query live Git status
and HEAD, read the referenced current learning file and the assigned issue plus
its governing SPEC/AC. Expand context only for the current task and risk.

The owner uses both agents for delivery and learning. Agree who implements and
who reviews before writing; one writer per overlapping file/resource. Recheck
dirty paths and preserve the other agent's and owner's work. Record a bounded
work claim and release it explicitly at handoff. Never reset someone else's work.

Use the same canonical scope: `docs/de_cuong_tot_nghiep_ver3.md`. Linear owns live
issue status, assignment and dates; the repository owns scope, contracts, code
and evidence. Linear milestone names use the same P2-P11 phase IDs as the repository;
there is no separate milestone numbering.
The separate NCKH Evidence Graph topic is not this delivery backlog.

If Linear is unavailable, ask for a dated issue snapshot and mark live status
unverified. Handoff issue/AC, revision and dirty paths, allowlist, changes,
verification/evidence, learning gaps, unresolved risks, authority and next action.
Do not claim a second-agent review unless that agent actually reviewed the
candidate. Owner explanations and labs cannot be fabricated by either agent.

Tracking/workflow approval does not authorize CLI installation, local Terraform
lab execution, IAM/backend/quota/account mutation, AWS apply, commit or push.
Retain previously granted authority only within its actual scope. Scheduling
targets do not authorize paid AWS resources to run between approved windows.
