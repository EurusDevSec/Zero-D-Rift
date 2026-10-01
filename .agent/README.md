# Sổ tay vận hành Zero D-Rift Agent

Đây là hướng dẫn ngắn cho người dùng. Quy tắc bắt buộc nằm ở
[AGENTS.md](../AGENTS.md); trạng thái làm việc hiện tại nằm ở
[active_context.md](workflows/active_context.md). README không duy trì một bản
sao của phase, task hay Git state.

Nếu chỉ cần bắt đầu làm việc, mở [QUICKSTART.md](QUICKSTART.md) và nhập
continue.

## Hai vòng đời phải đi cùng nhau

Vòng đời feature:

Learn → Micro-lab → Design → Spec → Build → Verify → Explain → Document → Checkpoint

Vòng đời context:

Select → Expand → Work → Verify → Classify → Contract

Mục tiêu không phải làm context ngắn nhất. Mục tiêu là giữ lượng context tối
thiểu nhưng đủ và đã được kiểm chứng cho quyết định kế tiếp. Quy tắc chi tiết
nằm ở [context-governance.md](references/context-governance.md).

## Nguồn nào chịu trách nhiệm việc gì?

| Câu hỏi | Nguồn chuẩn |
|---|---|
| Biên hành chính/tên đề tài | Hồ sơ nhà trường đã duyệt |
| Scope, metric, chi phí, timeline | docs/de_cuong_tot_nghiep_ver3.md |
| Quyết định kỹ thuật đã duyệt | .agent/adr/ |
| Contract của phase hiện tại | active SPEC được trỏ từ active context |
| Kết quả thực tế | Code, test, raw data, AWS/Kubernetes inventory |
| Đang làm gì tiếp theo | .agent/workflows/active_context.md |
| Mức hiểu hiện tại | .agent/learning/CURRENT_STATUS.md |
| Lịch sử học và milestone | LEARNING_LOG.md và history_archive.md, đọc khi cần |
| Git/AWS/Kubernetes hiện tại | Truy vấn trực tiếp |

Một fact chỉ có một nơi canonical. File khác chỉ nêu hậu quả hiện tại và liên
kết tới nguồn đó, không duy trì bản sao riêng.

## Bắt đầu hoặc tiếp tục

Khi nhập /init hoặc start, agent phải:

1. Đọc active context và current learning được trỏ trong đó.
2. Chạy Git status và Git HEAD trực tiếp.
3. Phân loại ý định, task và mức rủi ro.
4. Chỉ mở phần spec, ADR và tài liệu cần cho quyết định hiện tại.
5. Báo verified state, blocker, authority, next action và evidence cần tạo.

Khi nhập /resume hoặc continue, agent làm tương tự nhưng ưu tiên checkpoint hiện
có. Nếu checkpoint không chỉ ra được một next action an toàn, phải sửa checkpoint
trước khi làm công việc rủi ro.

Init/resume không tự cho phép tạo AWS resource, commit hoặc push.

## Nạp context theo mức rủi ro

| Loại công việc | Context cần mở |
|---|---|
| Hỏi/giải thích trạng thái | Chỉ nguồn hỗ trợ câu trả lời |
| Coach hoặc micro-lab | Learning gate, task liên quan và một nguồn kỹ thuật tập trung |
| Plan/build/review | Task hiện tại, acceptance, negative bounds và quyết định liên quan |
| Phê duyệt cả phase hoặc L3/L4 | Toàn contract cùng cost, identity, teardown và evidence |
| So sánh lịch sử | History/archive theo yêu cầu rõ ràng |

Không nạp toàn bộ learning log, lịch sử, archive hay mọi ADR theo mặc định.
Thiếu fact cụ thể nào thì mở rộng đúng nguồn đó.

## Cách checkpoint

/save không phải là chép lại cuộc trò chuyện. Nó phải:

1. Chạy verification phù hợp và truy vấn lại live state.
2. Phân loại thông tin mới.
3. Rewrite active context quanh next safe action.
4. Chạy .agent/scripts/check-context.ps1.
5. Báo danh sách file thay đổi và Git status.
6. Không commit/push nếu chưa có yêu cầu rõ.

| Loại thông tin | Nơi lưu |
|---|---|
| Ảnh hưởng quyết định kế tiếp | active_context.md |
| Quyết định bền vững | ADR hoặc tài liệu canonical |
| Kết quả quan sát | evidence path |
| Bằng chứng học mới | LEARNING_LOG.md; cập nhật CURRENT_STATUS nếu level đổi |
| Milestone đã hoàn thành | history_archive.md |
| Chi tiết hết hạn/lặp lại | Loại bỏ |

## Cách cộng tác

- Coach: mặc định với công nghệ chưa quen; giải thích flow, dự đoán và micro-lab.
- Pair: triển khai thay đổi đã duyệt và giải thích quyết định.
- Executor: chỉ cho việc cơ học sau khi design và acceptance đã rõ.

Crossplane, kro, KEDA, Karpenter, IRSA và recovery bắt đầu ở Coach hoặc Pair.
Feature chạy được nhưng chủ dự án chưa giải thích được chỉ là functional done,
chưa phải learning done.

## Dojo tách khỏi tiến độ chính

`/dojo` mở một bài luyện DevOps/cloud trong `playground/`. Dojo dùng để luyện
lặp lại, cố ý gây lỗi và chẩn đoán; nó không thay micro-lab của active SPEC và
không tự tạo project evidence hay phase progress. Chỉ một lab Dojo được active
tại một thời điểm, mặc định ưu tiên paper/local/mock/kind trước AWS thật.

## Kiểm tra continuity

`/hydration-test candidate` kiểm tra một account/session mới có thể tự đọc
repository, đối chiếu live Git và xác định đúng outcome, current state, next safe
action cùng authority boundary hay không. Candidate chỉ trả report read-only;
`/hydration-test evaluator` dùng rubric semantic để account hiện tại chấm lại.
Không dùng trí nhớ cloud hoặc độ giống văn phong làm đáp án.

## Done và evidence

Một task chỉ done khi kết quả chạy được, có evidence phù hợp và người dùng giải
thích được phần cần bảo vệ. Trạng thái kiểm thử hợp lệ gồm PASS, FAIL, PARTIAL,
BLOCKED và NOT RUN.

Các mức verification:

| Tier | Phạm vi |
|---|---|
| L0 | Format, schema, static policy |
| L1 | Unit/render/local component |
| L2 | kind/k3d integration |
| L3 | AWS/EKS integration |
| L4 | Trial chính thức và dataset |

Không biến tài liệu hoặc teach-back thành runtime proof. Không xóa failed trial;
mọi exclusion phải có lý do đã quy định.

## Chat và compaction

- Một chat theo một outcome mạch lạc, thường là một parent task.
- Cùng outcome nhưng transcript dài: checkpoint rồi dùng /compact.
- Đổi outcome, phase gate hoặc phạm vi ghi file: checkpoint rồi mở chat mới.
- Context percentage và line count chỉ là cảnh báo để review, không phải luật cứng.
- Chat history và Codex memory hỗ trợ recall, không thay project record.

## An toàn

- Không hard-code credential, token, account ID hoặc dữ liệu riêng tư.
- Không tạo AWS resource trả phí nếu chưa có task, cost check và authority rõ.
- Không ghi PASS/metric/cost khi chưa có command hoặc run evidence.
- Không chạy git add ., tự commit, tự push hoặc đẩy thẳng main.
- Không bỏ thay đổi sẵn có của người dùng để làm checkpoint trông sạch.
- Teardown khẩn cấp và xóa secret không bị chặn bởi learning gate.

## Lệnh thường dùng

| Lệnh | Kết quả mong đợi |
|---|---|
| /init, start | Kiểm tra packet và onboard session |
| /resume, continue | Tiếp tục một next action đã kiểm chứng |
| /hydration-test candidate hoặc evaluator | Chạy/chấm bài continuity read-only |
| /learn chủ-đề | Coach một concept và micro-lab |
| /dojo status hoặc /dojo terraform | Xem/chọn một deliberate-practice lab riêng |
| /plan feature | Refine spec/task/evidence |
| build Task N theo Pair mode | Triển khai bounded change đã duyệt |
| /verify, /test | Chạy tier phù hợp |
| /save, cuối ngày | Classify, contract và handoff |
| mock defense chủ-đề | Luyện giải thích từ evidence |

Chi tiết Definition of Done nằm ở
[definition-of-done.md](references/definition-of-done.md); workflow build/review
nằm ở [main-workflow.md](workflows/main-workflow.md).
