# Terraform Style and Layout

Read this reference when writing or reviewing Zero D-Rift Terraform HCL.

## Project precedence

- Use the Terraform, provider and module versions approved in the active SPEC.
  Examples from external guides are not project pins.
- Keep resources inside the ownership boundary in ADR-0003. Do not manage the
  same resource with Terraform and a platform controller.
- Do not add a resource merely because it is a generic best practice. Logging,
  KMS keys, endpoints, security services and other hardening must remain inside
  the approved scope, cost plan and acceptance criteria.

## Layout and readability

- Keep `terraform.tf` for required Terraform/provider constraints,
  `providers.tf` for provider configuration, `variables.tf` and `outputs.tf`
  for their declarations, and `locals.tf` for shared locals when useful.
- Split larger resource sets by a clear domain such as network or EKS rather
  than forcing every resource into `main.tf`.
- Use `snake_case` descriptive nouns without repeating the resource type.
- Let references express dependencies. Add `depends_on` only for a dependency
  Terraform cannot infer.
- Run `terraform fmt -check -recursive` and `terraform validate` at the
  appropriate L0/L1 checkpoint.

## Variables and repetition

- Give every variable a type and description; validate values only where the
  project has a real restriction.
- Expose a variable when a value is expected to vary between approved runs.
  Avoid turning every literal into a variable.
- Use `count` for nearly identical indexed instances or conditional creation.
  Use `for_each` when instances need stable keys or distinct values. Choose
  from resource identity and lifecycle behavior, not a universal preference.
- Use locals to remove meaningful repetition, not to hide simple expressions.

## Versions, state and secrets

- Pin versions according to the approved compatibility decision and commit the
  reviewed `.terraform.lock.hcl`. Do not auto-upgrade to a latest major/minor.
- Never commit `.terraform/`, state and backups, saved plans, sensitive
  `.tfvars`, plan JSON or lock-info files.
- Mark sensitive variables and outputs, but remember `sensitive = true` only
  redacts CLI display; it does not keep a value out of state.
- Prefer a provider-native secret manager or a reviewed ephemeral/write-only
  mechanism when the pinned Terraform/provider version supports it.
- Never hard-code credentials, account identifiers or private data.

## Review questions

1. Is every planned resource owned by Terraform and allowed by the active task?
2. Are version constraints and the lock file intentional and source-checked?
3. Could any input, output, plan or state expose sensitive data?
4. Does a lifecycle/meta-argument create replacement, retention or teardown risk?
5. Does the change introduce fixed cost or a resource absent from the cost plan?
