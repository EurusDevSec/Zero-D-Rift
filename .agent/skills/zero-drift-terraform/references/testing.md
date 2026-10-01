# Terraform Testing

Read this reference when creating or running `.tftest.hcl` tests. Confirm syntax
against the pinned Terraform version because the test framework evolves.

## Choose the test boundary first

| Test form | What it can prove | Boundary |
|---|---|---|
| Static format/validate | HCL format and internal consistency | Does not prove provider API validity or runtime behavior |
| Plan with mock provider | Expressions, validation, counts, tags and planned shape | Uses generated values; no AWS behavior or timing proof |
| Plan with real provider | Planned changes with provider schema/data access | May query AWS and expose sensitive plan data; no creation proof |
| Apply with mock provider | Terraform apply-path logic over simulated provider values | Does not create or prove AWS resources |
| Apply with real provider | Actual provider/resource behavior | L3: may create paid resources and leave orphans |

Default to plan plus mocks for L1 tests. Do not infer EKS or AWS success from a
mocked result.

## Useful P2 assertions

- Reject invalid Region, CIDR, instance type/count or public API CIDR input.
- Assert the default plan contains no NAT Gateway, RDS, GPU or platform controller.
- Assert approved resource counts, tags, encryption flags and node limits.
- Assert sensitive outputs are marked sensitive where applicable.
- Use `expect_failures` for input-validation negative cases.

Avoid assertions on arbitrary mock-generated IDs or formats unless explicit mock
values are supplied. Mock schemas and defaults may need revision after a provider
upgrade.

## Correct command shape

Run from the configuration root:

```powershell
terraform test
terraform test -filter='tests\network_unit_test.tftest.hcl'
terraform test -verbose
```

`-filter` selects test files, not `run` block names. Do not assume an external
skill's example flag exists; check `terraform test -help` for the pinned CLI.

## Real-provider safety

- Never run apply-mode tests against AWS automatically on merge or as a routine
  local check.
- Before an L3 test, record approval, identity, Region, exact plan, estimate,
  stop time, teardown owner and pre-inventory.
- Watch cleanup output. If Terraform cannot destroy a test resource, preserve
  its address/error, stop unrelated work and execute the approved orphan runbook.
- Do not use a no-cleanup/debug option with paid resources unless retention is
  explicitly approved and recorded.
- A successful test apply is incomplete until teardown and post-inventory are
  verified.

## Evidence

Record the command, pinned versions, timestamp, Git SHA/dirty state, expected
result, actual result, exit status and redacted evidence path. Use `PASS` only
for the criterion actually proven; otherwise use `FAIL`, `PARTIAL`, `BLOCKED` or
`NOT RUN`.
