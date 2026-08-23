# Zero D-Rift Documentation Governance

## Canonical implementation document

`de_cuong_tot_nghiep_ver3.md` is the only canonical document for implementation
scope, architecture boundary, hypotheses, metrics, acceptance criteria, budget,
and schedule.

It preserves the approved project identity while changing unsupported numeric
claims into targets that must be measured. It must not be silently broadened by
an agent, an archived draft, or a presentation slide.

## Administrative and historical records

| Document | Status | Normal agent use |
|---|---|---|
| `gop_y_de_cuong_tu_thay_Kiet.md` | Governance evidence in Git history | Read only when checking teacher-feedback alignment |
| `de_cuong_tot_nghiep_ver2.md` | Approved/reviewed baseline in Git history | Read only for administrative traceability |
| `de_cuong_tot_nghiep.md` | Earlier proposal draft in Git history | Do not use for implementation |
| `drift.md` | Historical technical draft in Git history | Do not use for implementation |
| `drift2.md` | Historical technical draft in Git history | Do not use for implementation |
| `slides_pitch_deck.md` | Historical presentation in Git history | Verify every claim against ver3 before reuse |

The current working tree contains only the canonical ver3 and this governance
README. The historical files were removed in commit `21a1d11` and remain
recoverable from earlier commit `69be067`, for example:

```text
git show 69be067:docs/gop_y_de_cuong_tu_thay_Kiet.md
```

Their presence in Git history does not give them implementation authority.

## Conflict rule

1. Approved school records govern the administrative name and accepted topic.
2. `de_cuong_tot_nghiep_ver3.md` governs technical execution.
3. ADRs may refine implementation but may not expand ver3.
4. Raw evidence overrides planned or assumed results.

Before publishing the repository as a portfolio, redact phone numbers, student
IDs, account identifiers, and other unnecessary personal information.
