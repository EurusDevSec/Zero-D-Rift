# Zero D-Rift Documentation Governance

## Canonical implementation document

`de_cuong_tot_nghiep_ver3.md` is the only canonical document for implementation
scope, architecture boundary, hypotheses, metrics, acceptance criteria, budget,
and schedule.

It preserves the approved project identity while changing unsupported numeric
claims into targets that must be measured. It must not be silently broadened by
an agent, an archived draft, or a presentation slide.

## Approved-document lineage

```text
Teacher feedback
  -> ver2: revised proposal that incorporated the feedback
  -> ver3: implementation-focused optimization of ver2
```

The owner has confirmed this lineage. Normal P1 work must not repeat a full
ver3-versus-feedback review. Reopen it only if a proposed implementation change
would exceed ver3 scope or if the teacher/school requests a formal revision.

## Administrative and historical records

| Document | Status | Normal agent use |
|---|---|---|
| `governance/gop_y_de_cuong_tu_thay_Kiet.md` | Teacher-feedback evidence | Read only when checking alignment |
| `governance/de_cuong_tot_nghiep_ver2.md` | Approved/reviewed baseline | Read only for administrative traceability |
| `governance/de_cuong_tot_nghiep.md` | Earlier proposal draft | Do not use for implementation |
| `archive/drift.md` | Historical technical draft | Do not use for implementation |
| `archive/drift2.md` | Historical technical draft | Do not use for implementation |
| `archive/slides_pitch_deck.md` | Historical presentation | Verify every claim against ver3 before reuse |

The files were restored into `docs/governance/` and `docs/archive/` without
changing their contents. Their presence in the working tree does not give them
implementation authority.

## Conflict rule

1. Approved school records govern the administrative name and accepted topic.
2. `de_cuong_tot_nghiep_ver3.md` governs technical execution.
3. ADRs may refine implementation but may not expand ver3.
4. Raw evidence overrides planned or assumed results.

Before publishing the repository as a portfolio, redact phone numbers, student
IDs, account identifiers, and other unnecessary personal information.
