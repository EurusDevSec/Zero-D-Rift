---
name: zero-drift-verify
description: Verify Zero D-Rift documentation, code, infrastructure, or experiments at the appropriate L0-L4 tier and record reproducible evidence.
---

# Zero D-Rift Verify

1. Read the active acceptance criterion and choose the lowest tier that proves it:
   L0 static, L1 local, L2 local integration, L3 AWS integration or L4 experiment.
2. For L3/L4, confirm explicit task authorization, cost guard and teardown plan.
3. Record command, timestamp, Git SHA/dirty state, configuration, expected result,
   actual result and evidence path.
4. Preserve failures and diagnose expected vs actual; retry only when the
   hypothesis or state has changed.
5. Record `PASS` only when the acceptance criterion is actually proven. Otherwise
   use `FAIL`, `BLOCKED`, `PARTIAL` or `NOT RUN` with a reason.
6. Update active context only after evidence has been captured.

