# Bản đồ repo Zero D-Rift — đọc file này trước

Mở repo mà thấy rối thì quay lại đây. Đây là nơi duy nhất cần nhớ.
Bản trực quan: tab **Repo** trong [learning/zero-drift-explorer.html](learning/zero-drift-explorer.html).

## 1. Bốn thư mục code (DevOps thật cần thành thạo)

| Thư mục | Là gì | Mở khi nào | Phase |
|---|---|---|---|
| `infra/terraform/` | Dựng nền AWS một lần: VPC, EKS, IAM, RDS (`modules/` = khối dùng lại, `tests/` = test không tốn tiền, `scripts/` = mở/đóng window) | Sửa hạ tầng AWS | P2, P4 |
| `gitops/` | Những gì Argo CD đồng bộ vào cluster: `bootstrap/` → `platform/` (apps, providers, RGD, RBAC, tenants) → `requests/` (đơn của tenant) | Thêm/sửa thứ chạy trong cluster | P3, P4 |
| `workloads/rag-sandbox/` | Code app Python + test + Dockerfile | Sửa app | P4 |
| `labs/` | Lab local trên kind, mỗi thư mục một bài (`p3-kind`, `p4-kro-spike`, `p4-kind-db`, `p4-kind`) | Tập/kiểm chứng trước khi lên AWS | P3, P4 |

Thêm: `.github/workflows/` = CI (static gates), `infra/iam/` = policy IAM mẫu.
Bỏ qua: `infra/terraform/.terraform/` (module tải về, Git bỏ qua, hơn 130 file `.md` không phải của mình).

## 2. Ba loại tài liệu kỹ thuật (công ty thật cũng có)

| Loại | Ở đâu | Trả lời câu hỏi |
|---|---|---|
| ADR | `.agent/adr/ADR-000N_*.md` | Vì sao chọn cách này? |
| Runbook | `docs/runbooks/P<n>_*.md` | Làm lại từng bước thế nào, kiểm tra, hoàn tác? |
| Evidence | `docs/evidence/p<n>/*.md` | Đã chạy thật chưa, output là gì? |

## 3. Đọc gì theo phase (chỉ cần chừng này)

| Phase | Spec | Runbook | Evidence |
|---|---|---|---|
| P2 nền AWS | `.agent/specs/SPEC-P2_*` | `P2_EKS`, `P2_NETWORK`, `P2_L3_WINDOW` | `evidence/p2/` |
| P3 controller | `.agent/specs/SPEC-P3_*` | `P3_RESOURCE_GRAPH`, `P3_L2_KIND_LAB` | `evidence/p3/` |
| P4 RAG sandbox | `.agent/specs/SPEC-P4_*` | `P4_L2_KIND_LAB`, `P4_TERRAFORM_RAG`, `P4_RAG_IMAGE` | `evidence/p4/` |
| P5 tenant guardrails | `.agent/specs/SPEC-P5_*` (owner duyệt 22/11) | `P5_PINS` | `evidence/p5/` |

**Bản nháp SPEC P6–P9 đã có sẵn, đừng viết mới từ đầu.** Claude Fable 5.2 phác thảo ngày 16/11 theo yêu cầu
của owner, nằm trên nhánh `claude/specs-p5-p9-draft-ecc762` (chưa merge):
`SPEC-P6_BATCH_TRAINING_JOB`, `SPEC-P7_COST_OBSERVABILITY_AND_BASELINE`, `SPEC-P8_REMEDIATION_RECOVERY_AND_FREEZE`,
`SPEC-P9_OFFICIAL_CAMPAIGN` (status `DRAFT_FABLE_20261116`). Khi vào phase: lấy bản nháp bằng
`MSYS_NO_PATHCONV=1 git show origin/claude/specs-p5-p9-draft-ecc762:.agent/specs/<file>`, kiểm lại giả định với
`main` và evidence phase trước (như SPEC-P5 ngày 22/11), rồi mới review. Bản P6 viết trước ADR-0009 (17/11,
P6 chạy CPU) nên phần GPU phải sửa theo ADR.

Phạm vi gốc của cả đồ án: `de_cuong_tot_nghiep_ver3.md`. Kiến trúc: `architecture/SYSTEM_DESIGN.md`.

## 4. Giấy tờ quản lý (không cần đọc hết)

| Ở đâu | Là gì | Ai dùng |
|---|---|---|
| `AGENTS.md`, `CLAUDE.md` | Luật làm việc cho agent | Agent |
| `.agent/workflows/active_context.md` | Đang làm task gì, tới đâu | Agent + bạn khi mở phiên mới |
| `.agent/docs/` | Roadmap, tính năng, kiến trúc agent, cách dùng Linear | Tra khi cần |
| `.agent/skills/`, `.agent/tests/` | Skill và test của agent | Agent |
| `.agent/references/` | Tài liệu tham chiếu: quy tắc context, definition of done, `AI_INFRA_COST.md` (nguồn về chi phí hạ tầng AI cho phần bối cảnh báo cáo) | Agent + bạn khi viết báo cáo |
| `.agent/learning/`, `playground/`, `SO_TAY.md` | Nhật ký học, bài tập, khung tư duy | Bạn khi ôn |
| `docs/learning/` | Explorer trực quan (`zero-drift-explorer.html` + `.data.json`, icon) | Bạn khi ôn, cập nhật mỗi phase |
| `docs/governance/`, `docs/archive/` | Đề cương cũ, góp ý của thầy | Chỉ khi đối chiếu |
| `docs/finops/`, `docs/security/`, `docs/experiments/`, `docs/research/` | Chi phí, threat model, thí nghiệm, NCKH | Theo task |

Ở công ty, nhóm này thường nằm trong Jira/Confluence; ở đây nằm trong repo vì là đồ án và có agent làm cùng.

## 5. Luật giữ repo gọn (áp dụng cho mọi agent)

Giới hạn **loại** file, không dồn mọi thứ vào một file.

1. **Chỉ có các loại file trong mục 2 và 4.** Không tạo loại `.md` mới (ghi chú lẻ, summary, notes…).
2. **Một file, một chủ đề, dưới ~300 dòng.** Vượt thì tách theo chủ đề (không theo ngày), giữ cùng thư mục và cùng tiền tố tên.
3. **Mỗi file mở đầu bằng TL;DR ≤ 5 dòng:** để làm gì · trạng thái · kết luận chính · liên quan (link) · mục lục.
   Agent đọc TL;DR trước, rồi chỉ mở đúng mục cần (tìm theo tiêu đề), không nạp cả file.
4. **Nhật ký chỉ ghi thêm cắt theo phase:** `active_context.md`, `LEARNING_LOG.md` chỉ giữ phase hiện tại; đóng phase thì chuyển phần cũ vào `history_archive.md`.
5. **Bản đồ này là cửa vào duy nhất.** File mới phải được thêm vào bản đồ trong cùng task.
6. **Bàn giao** liệt kê "file mới / file sửa", mỗi file một dòng giải thích.
7. **Dọn dẹp** (tách file dài, thêm TL;DR, lưu trữ) chỉ làm ở ranh giới phase, như một task riêng.

## 6. Cách đặt tên file

Thư mục đã nói **loại** file, nên tên chỉ cần nói **phase + chủ đề**. Tên ngắn, cùng chủ đề thì cùng từ khoá.

| Loại | Mẫu tên | Ví dụ |
|---|---|---|
| Spec | `.agent/specs/SPEC-P<n>_<CHU_DE>.md` | `SPEC-P4_RAG_SANDBOX.md` |
| ADR | `.agent/adr/ADR-<NNNN>_<CHU_DE>.md` | `ADR-0009_P6_CPU_BATCH.md` |
| Runbook | `docs/runbooks/P<n>_<CHU_DE>[_<PHAN>].md` | `P4_LAB_SETUP.md`, `P4_LAB_FAILURES.md` |
| Evidence | `docs/evidence/p<n>/P<n>-T<task>_<CHU_DE>_<YYYYMMDD>.md` | `P4-T3.2_LAB_GRAPH_20261119.md` |

Quy tắc:

- `<CHU_DE>`: CHỮ_HOA_GẠCH_DƯỚI, **tối đa 3 từ**, tiếng Anh không dấu. Không lặp lại tên loại (`RUNBOOK`, `DOC`, `NOTES`).
- **Cùng chủ đề → cùng từ khoá** ở mọi loại, để tìm một lần ra hết. Ví dụ chủ đề `LAB` của P4: runbook `P4_LAB_*`, evidence `P4-T*_LAB_*`.
- **Mã task `T<task>`** (khớp Linear/spec) là sợi dây nối: evidence `P4-T3.2_…` ↔ mục `T3.2` trong spec ↔ mục tương ứng trong runbook.
- Chỉ evidence có ngày (vì là bằng chứng tại một thời điểm); spec, ADR, runbook luôn là bản hiện hành, lịch sử nằm trong Git.
- Tách file thì giữ tiền tố và thêm phần đuôi: `P4_LAB.md` → `P4_LAB_SETUP.md` + `P4_LAB_FAILURES.md` + `P4_LAB_CLEANUP.md`.
- File hiện có giữ nguyên tên; chỉ đổi tên ở lần dọn dẹp cuối phase, cập nhật mọi link trong cùng commit.

---

# Documentation governance

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

## NCKH derivative research track

The proposed student-research topic derived from Zero D-Rift is documented at
`research/nckh/NCKH_RESEARCH_CONTEXT.md`. It is a handoff/context record, not an
approved extension of the graduation-project scope. Its title, Category B target,
advisor acceptance, non-duplication boundary, funding and experiment design remain
subject to the explicit status labels in that file.
