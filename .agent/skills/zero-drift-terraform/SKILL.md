---
name: zero-drift-terraform
description: Design, review, or test Terraform HCL for an approved Zero D-Rift task; does not authorize provider installation, AWS apply, or account mutation.
---

# Zero D-Rift Terraform

Use Terraform only inside the active SPEC, ADR ownership boundary and current
verification tier. The active task controls resources, versions, cost and
evidence; this skill supplies Terraform-specific guidance without expanding
them.

## Route only the needed detail

- For HCL layout, naming, variables, outputs, version constraints or review,
  read [references/style-and-layout.md](references/style-and-layout.md).
- For `.tftest.hcl`, assertions, mocks or test execution, read
  [references/testing.md](references/testing.md).
- For backend, state, apply or destroy work, use the active SPEC and runbook as
  the source of truth. Do not invent a backend or duplicate its contract here.

## Operating rules

1. Read the active task's acceptance and negative boundaries before editing.
2. Use the owner-approved Terraform CLI/provider/module pins. Source-check
   version-sensitive syntax against current official HashiCorp documentation;
   never replace a reviewed pin with `latest` automatically.
3. Default to the lowest proving tier: static checks or a local/mocked test
   before any real-provider test. A plan is not runtime proof.
4. Do not install or update a CLI, provider, module or helper tool without the
   task authorizing that dependency and version.
5. Do not run `apply`, apply-mode tests against a real provider, create a
   backend, query sensitive account state or mutate AWS unless the current task
   explicitly authorizes it. L3 additionally requires a current cost check,
   bounded window and teardown owner.
6. Treat state, saved plans, plan JSON, variable files and outputs as
   sensitive-capable. Do not print, commit or place them in evidence unless the
   approved evidence procedure explicitly redacts them.
7. Make one bounded change, run the verification that proves its acceptance
   criterion, and report the observed status. Preserve failed output and
   leftover-resource evidence.
