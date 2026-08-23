# Zero D-Rift Durable Memory

Store only facts and lessons likely to remain useful across phases. Current task
state belongs in `workflows/active_context.md`; raw evidence belongs in
`experiments/`.

## Durable project facts

- Owner: Lê Văn Hoàng; graduation project timeline ends with a release candidate
  by 01/11/2026 and defense preparation during November.
- Existing background: AWS CLF-C02, Kubernetes labs/small projects, and basic
  applied Terraform on AWS and DigitalOcean.
- Initial learning gaps explicitly reported: Crossplane and kro have not been used.
- Canonical implementation scope: `docs/de_cuong_tot_nghiep_ver3.md`.
- One EKS cluster, one AWS account/Region sandbox, two simulated tenants and two
  golden paths form the maximum PoC boundary.
- The project values reproducibility, honest failure reporting, cost control and
  the owner's ability to explain the system over technology count.

## Durable agent-operation decisions

- The root `.agent/` directory is the self-contained project-state and workflow
  layer. The reusable framework source was removed after P0 initialization.
- Planning is rolling-wave: current phase detailed, later phases outcome-level.
- New technologies start in Coach/Pair mode.
- A claim becomes a result only after linked evidence exists.
- No automatic Git staging, commit, push, or paid AWS provisioning.

## Reusable failure record template

```markdown
### YYYY-MM-DD — Short failure name
- Context/phase:
- Expected:
- Actual:
- Evidence:
- Root cause status: suspected | confirmed
- Workaround/fix:
- Durable lesson:
```
