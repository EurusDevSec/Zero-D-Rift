# Sổ tay sử dụng Eurus Agent cho Zero D-Rift

Đây là hướng dẫn vận hành hằng ngày cho Zero D-Rift: sử dụng agent để làm dự án,
học công nghệ đúng thời điểm, theo dõi tiến độ và chuyển sang chat/session mới mà
không phải giải thích lại từ đầu.

Nếu không muốn đọc toàn bộ tài liệu này, chỉ cần dùng
[`QUICKSTART.md`](QUICKSTART.md). Đây là thẻ workflow một trang để mở mỗi ngày.

`eurus-agent/` là framework nguồn có thể dùng lại. Thư mục `.agent/` ở project
root mới là instance chứa trạng thái thật của Zero D-Rift. Không dùng memory mẫu
bên trong `eurus-agent/.agent/` để quyết định công việc của đồ án.

---

## 1. Nguyên tắc cốt lõi

Eurus không thay bạn làm toàn bộ dự án. Nó giúp bảo đảm mỗi giai đoạn đều có:

1. Mục tiêu và giới hạn rõ ràng.
2. Kiến thức cần học đúng lúc.
3. Task/subtask đủ nhỏ để thực hiện.
4. Kiểm thử và bằng chứng thật.
5. Khả năng giải thích lại bằng hiểu biết của bạn.
6. Checkpoint để session tiếp theo tiếp tục chính xác.

Workflow chuẩn:

```text
Learn → Micro-lab → Design → Spec → Build
      → Verify → Explain → Document → Checkpoint
```

Không bỏ qua `Learn`, `Verify` và `Explain` chỉ để tạo ra nhiều file hoặc nhiều
công nghệ. Một feature chạy được nhưng bạn chưa giải thích được thì mới chỉ
`functional done`, chưa đạt `learning done`.

---

## 2. Bắt đầu nhanh

### Chat/session mới hoàn toàn

Trong project root, nhập:

```text
/init
```

hoặc:

```text
start
```

Agent phải:

1. Đọc `AGENTS.md` ở project root.
2. Đọc `workflows/active_context.md`.
3. Kiểm tra Git HEAD và dirty status.
4. Đọc active spec được trỏ từ context.
5. Đọc hồ sơ nền tảng của bạn trong `memory/cold_memory.md` và phần đánh giá
   hiện tại trong `learning/LEARNING_LOG.md`.
6. Báo phase hiện tại, task tiếp theo, blocker và evidence cần tạo.

`/init` chỉ nạp và kiểm tra trạng thái. Nó không được tự triển khai AWS, cài
controller, commit hoặc push.

### Tiếp tục công việc đang dở

Nhập:

```text
/resume
```

hoặc:

```text
continue
```

Agent phải đối chiếu checkpoint với Git hiện tại, tìm checkbox tiếp theo trong
active spec và chỉ đọc tài liệu liên quan tới task đó.

### Bắt đầu hoặc kết thúc một ngày làm việc

```text
đầu ngày
```

Tương đương `/init` hoặc `/resume`, tùy project đã có checkpoint hay chưa.

```text
cuối ngày
```

Tương đương `/save`/checkpoint: chạy kiểm tra phù hợp, ghi kết quả thật, cập nhật
context và liệt kê file thay đổi. Không tự động commit/push.

---

## 3. Bản đồ nguồn sự thật

Không có một file chứa mọi thứ. Mỗi loại thông tin chỉ có một nơi chịu trách nhiệm.

| Thứ tự | Nguồn | Quyết định điều gì |
|---:|---|---|
| 1 | Hồ sơ nhà trường đã duyệt | Tên đề tài và biên hành chính |
| 2 | `docs/de_cuong_tot_nghiep_ver3.md` | Scope triển khai, metric, ngân sách, timeline, nghiệm thu |
| 3 | `.agent/adr/ADR-*.md` | Quyết định kỹ thuật đã được chấp thuận trong phạm vi ver3 |
| 4 | Active `.agent/specs/SPEC-*.md` | Contract và task của feature/phase hiện tại |
| 5 | Code, test, raw data, AWS inventory | Bằng chứng vận hành thực tế |
| 6 | `workflows/active_context.md` | Con trỏ trạng thái hiện tại, không thay thế các nguồn trên |

Khi có mâu thuẫn, dùng nguồn ở thứ tự cao hơn và sửa tài liệu thấp hơn. Tài liệu
cũ trong Git history không được dùng để mở rộng scope hoặc biến mục tiêu thành
kết quả đã đạt.

---

## 4. Mỗi file có nhiệm vụ gì?

### Entrypoint và điều phối

| File | Nhiệm vụ | Khi agent đọc | Ai cập nhật |
|---|---|---|---|
| `../AGENTS.md` | Constitution, quyền ưu tiên, router command, an toàn | Mọi session mới | Chỉ sửa khi workflow toàn dự án thay đổi |
| `README.md` | Sổ tay sử dụng Eurus cho con người | Khi cần hiểu cách vận hành | Cập nhật khi quy trình sử dụng thay đổi |
| `workflows/active_context.md` | Phase/task hiện tại, blocker, Git state, next action | Đầu và cuối mỗi session | Agent cập nhật bằng evidence, người dùng review |
| `workflows/main-workflow.md` | Quy trình Learn-to-Checkpoint và test tiers | Khi build/review/ship | Chỉ sửa khi lifecycle thay đổi |
| `workflows/history_archive.md` | Các milestone có ý nghĩa | Khi audit lịch sử | Append ở phase/feature transition, không ghi transcript |

### Kế hoạch và kiến trúc

| File | Nhiệm vụ | Quy tắc |
|---|---|---|
| `docs/ROADMAP.md` | Toàn bộ phase đến tháng 11, deadline và exit criteria | Chỉ giữ mức phase/outcome cho tương lai |
| `docs/FEATURES.md` | Mục lục feature và spec tương ứng | Không lặp lại toàn bộ roadmap |
| `docs/ARCHITECTURE.md` | Bản đồ kiến trúc và dependency hiện tại | Không được tự nhận là scope SSOT |
| `specs/SPEC-*.md` | Goal, acceptance, negative bounds, task/subtask, evidence | Chi tiết phase hiện tại; không tạo sẵn mọi phase |
| `adr/ADR-*.md` | Quyết định, lý do, trade-off, hậu quả | Chỉ tạo cho quyết định có ảnh hưởng đáng kể |

### Học tập, memory và tiêu chuẩn hoàn thành

| File | Nhiệm vụ | Không được dùng để |
|---|---|---|
| `learning/LEARNING_ROADMAP.md` | Học công nghệ nào ở phase nào | Học trước toàn bộ stack cùng lúc |
| `learning/LEARNING_LOG.md` | Bằng chứng đã học/lab/giải thích được | Tự đánh dấu hiểu chỉ vì agent tạo code |
| `memory/cold_memory.md` | Nền tảng của bạn, quyết định bền vững, lỗi có thể tái diễn | Lưu trạng thái task hằng ngày |
| `references/definition-of-done.md` | Điều kiện done cho subtask, feature, learning, phase, research result | Đánh dấu done khi chưa có evidence |

### Skills

| Skill | Dùng khi |
|---|---|
| `zero-drift-init` | Onboard hoặc kiểm tra một session mới |
| `zero-drift-resume` | Tiếp tục từ checkpoint có sẵn |
| `zero-drift-plan` | Tạo/refine spec, phase, task, subtask |
| `zero-drift-learn` | Học một công nghệ bằng micro-lab và teach-back |
| `zero-drift-verify` | Chọn test tier và ghi evidence |
| `zero-drift-checkpoint` | Kết thúc phiên, cập nhật trạng thái an toàn |

Agent chỉ đọc skill tương ứng với ý định hiện tại, không cần nạp tất cả skill vào
mỗi session.

---

## 5. Cách theo dõi tiến độ

Tiến độ được theo dõi ở bốn cấp, không chỉ bằng cảm giác hoặc số lượng file.

### Cấp 1 — Roadmap/Phase

Mở `docs/ROADMAP.md` để biết:

- Đang ở phase nào.
- Deadline và outcome của phase.
- Exit criteria.
- Scope gate nếu bị trễ hoặc công nghệ không hoạt động.

Status hợp lệ:

```text
PLANNED → ACTIVE → BLOCKED hoặc COMPLETE
```

Chỉ đánh dấu `COMPLETE` khi exit criteria và Definition of Done đều đạt.

### Cấp 2 — Feature/Spec

Mở active spec được ghi trong `workflows/active_context.md`.

Spec cho biết:

- Phải xây gì và tại sao.
- Những gì không được làm.
- Kiến thức phải hiểu.
- Task/subtask cụ thể.
- Test/evidence và teach-back cần hoàn thành.

Parent task thường kéo dài 2–4 giờ. Subtask thường kéo dài 15–60 phút và phải có
kết quả quan sát được.

### Cấp 3 — Session/Ngày làm việc

`workflows/active_context.md` phải trả lời được:

1. Project đang ở đâu?
2. Task nào đang active?
3. Việc gì đã được xác minh?
4. Việc gì chỉ mới dự kiến?
5. Blocker là gì?
6. Lệnh hoặc hành động nhỏ tiếp theo là gì?
7. Git/AWS state hiện tại ra sao?

Không lưu cả hội thoại vào context. Chỉ lưu kết luận, evidence pointer và next action.

### Cấp 4 — Năng lực học tập

Mỗi mục trong `learning/LEARNING_LOG.md` dùng bốn mức:

| Mức | Ý nghĩa |
|---|---|
| `STARTED` | Đã đọc/xem, chưa thực hành |
| `PRACTICED` | Đã làm micro-lab có evidence |
| `EXPLAINED` | Giải thích được flow, trách nhiệm và một failure mode |
| `REPRODUCIBLE` | Tự lặp lại được kết quả dự án theo runbook |

Mục tiêu không phải đưa mọi công nghệ lên `REPRODUCIBLE`. Chỉ các cơ chế thật sự
dùng trong MVP mới cần đạt mức phù hợp để bảo vệ đồ án và đi phỏng vấn.

---

## 6. Cách sử dụng agent hợp lý

### Coach mode

Dùng khi công nghệ còn mới, đặc biệt với Crossplane, kro, KEDA, Karpenter, IRSA
và recovery.

Bạn có thể yêu cầu:

```text
/learn Kubernetes reconciliation cho task P1 hiện tại
```

Agent phải giải thích bản chất, cho bạn dự đoán, thiết kế một micro-lab nhỏ và hỏi
lại 3–5 câu. Không được nhảy thẳng sang tạo toàn bộ feature.

### Pair mode

Dùng khi đã hiểu khái niệm nhưng cần hỗ trợ thiết kế/triển khai:

```text
Làm Task 2 theo Pair mode. Giải thích mỗi quyết định trước khi sửa file.
```

Agent có thể viết phần code/tài liệu đã được chấp thuận, nhưng phải cho biết vì
sao, thay đổi gì và kiểm chứng thế nào.

### Executor mode

Chỉ dùng cho công việc cơ học hoặc lặp lại sau khi design đã chốt:

```text
Thực hiện các subtask cơ học đã duyệt trong Task 2 ở Executor mode.
```

Không dùng Executor mode để giao toàn bộ công nghệ mới cho agent rồi chỉ xem demo.

### Phân chia trách nhiệm

| Bạn chịu trách nhiệm | Agent hỗ trợ |
|---|---|
| Chọn mục tiêu, duyệt scope và chi phí | Phân tích trade-off và phát hiện rủi ro |
| Hiểu và giải thích kiến trúc | Dạy, thiết kế micro-lab và phản biện |
| Quyết định tạo/xóa AWS resource | Viết kế hoạch, lệnh và kiểm tra inventory |
| Review thay đổi và quyết định commit | Chỉnh file, chạy verification, báo diff |
| Bảo vệ kết quả trước hội đồng | Tạo câu hỏi teach-back và mock defense |

---

## 7. Quy trình làm việc trong một ngày

### Bước 1 — Hydrate (10–15 phút)

```text
/resume
```

Kiểm tra phase, active task, Git state, blocker và evidence cần tạo.

### Bước 2 — Learn/Design (45–90 phút)

- Học đúng một concept đang chặn task.
- Dùng tài liệu chính thức/phù hợp version.
- Dự đoán hành vi trước khi chạy lab.
- Nếu là quyết định quan trọng, ghi ADR.

### Bước 3 — Micro-lab/Build (2–3 giờ)

- Làm một parent task hoặc một nhóm subtask liên quan.
- Không mở thêm công nghệ ngoài task.
- Với AWS, kiểm tra cost gate và teardown trước khi tạo resource.

### Bước 4 — Verify/Explain (45–60 phút)

- Chọn L0–L4 phù hợp.
- Lưu command, timestamp, expected/actual và evidence.
- Giải thích lại flow và failure mode.

### Bước 5 — Checkpoint (15–30 phút)

```text
/save
```

Agent cập nhật context, learning log/history khi phù hợp và báo Git status. Chỉ
commit/push khi bạn yêu cầu rõ sau khi review file list.

Không bắt buộc mỗi ngày đều đủ năm bước. Nhưng mọi task hoàn chỉnh phải đi qua
cả workflow trước khi đánh dấu done.

---

## 8. Nhịp làm việc 25–30 giờ/tuần

| Hoạt động | Thời lượng mục tiêu |
|---|---:|
| Học tài liệu chính thức, focused learning | 5–6 giờ |
| Micro-lab và thiết kế | 3–4 giờ |
| Triển khai | 12–14 giờ |
| Test, troubleshooting và evidence | 4–5 giờ |
| Tài liệu, teach-back và checkpoint | 2 giờ |

Đây là tổng thời gian của dự án, không phải 25–30 giờ code cộng thêm thời gian học.

Cuối mỗi tuần:

1. Đối chiếu exit criteria của phase.
2. Tổng hợp functional done và learning done.
3. Kiểm tra chi phí/resource inventory.
4. Ghi blocker và quyết định cắt `COULD`, sau đó `SHOULD` nếu bị trễ.
5. Chỉ tạo spec chi tiết cho phase kế tiếp khi dependency hiện tại đủ ổn định.

---

## 9. Verification và evidence

| Tier | Dùng cho | Evidence tối thiểu |
|---|---|---|
| L0 | Format, schema, static policy | Command và output |
| L1 | Unit/render/local component | Test/log artifact |
| L2 | kind/k3d integration | Run ID và logs |
| L3 | AWS/EKS integration | Run manifest, AWS inventory, logs, cost/teardown check |
| L4 | Trial chính thức | Raw dataset bất biến và analysis script |

Không ghi `PASS` khi chỉ mới tạo file. Trạng thái hợp lệ gồm:

```text
PASS | FAIL | PARTIAL | BLOCKED | NOT RUN
```

Mỗi kết quả cần có Git SHA/dirty state, timestamp, cấu hình, expected/actual và
đường dẫn evidence. Trial thất bại không được xóa để làm số liệu đẹp hơn.

---

## 10. Git, AWS và an toàn

### Git

- Không chạy `git add .`.
- Không tự commit hoặc push.
- Không push thẳng `main` nếu chưa được bạn yêu cầu.
- Trước checkpoint phải báo chính xác file modified/untracked.
- Commit chỉ chứa nhóm thay đổi đã review và có verification tương ứng.

### AWS

- `/init`, `/resume`, `/learn`, `/plan` không cấp quyền tạo tài nguyên trả phí.
- L3/L4 cần task được chấp thuận, cost estimate, quota và teardown plan.
- Không lưu Access Key, secret, account ID hay dữ liệu cá nhân trong Git/log.
- Sau mỗi đợt AWS test phải chạy inventory và xác nhận tài nguyên retain/delete.
- Billing có thể trễ; pod/node về zero không có nghĩa toàn hệ thống hết chi phí.

---

## 11. Khi nào nên đổi sang chat/session mới?

Nên checkpoint và mở session mới khi:

- Hoàn thành một parent task hoặc milestone.
- Context chat dài và bắt đầu lặp lại thông tin.
- Chuyển từ design sang build hoặc từ build sang experiment lớn.
- Agent nhầm file, nhầm trạng thái hoặc sử dụng snapshot cũ.
- Cần tách một cuộc review/phản biện khỏi phiên triển khai.

Trước khi đổi session:

1. Chạy `/save`.
2. Kiểm tra `active_context.md` có task, blocker, Git state, evidence và next action.
3. Review file thay đổi; commit nếu bạn chủ động chọn làm vậy.
4. Mở chat mới và nhập `continue`.

Session mới đạt yêu cầu khi tự báo đúng:

- SSOT là ver3.
- Phase và active spec hiện tại.
- Subtask tiếp theo.
- Nền tảng AWS/Kubernetes/Terraform của bạn và các learning gap.
- Không được tự tạo AWS resource hoặc commit/push.

Nếu thiếu một trong các mục này, dừng triển khai và sửa checkpoint trước.

---

## 12. Command cheat sheet

| Bạn nhập | Mục đích |
|---|---|
| `/init` hoặc `start` | Onboard/kiểm tra session mới |
| `/resume` hoặc `continue` | Tiếp tục task đang dở |
| `/learn <topic>` | Học và làm micro-lab một concept |
| `/plan <feature>` | Lập/refine spec, task và subtask |
| `build Task N theo Pair mode` | Triển khai task đã duyệt, vừa làm vừa giải thích |
| `/verify` hoặc `/test` | Chạy verification tier phù hợp |
| `review` | Soi scope, security, evidence và maintainability |
| `/save` hoặc `cuối ngày` | Ghi checkpoint, không tự commit/push |
| `mock defense <topic>` | Luyện giải thích/phản biện sau khi có evidence |

---

## 13. Trạng thái hiện tại

- P0: bộ Eurus project-specific đã được tạo ở root.
- P1: `Foundation and compatibility decisions` đang active.
- Active spec: `specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`.
- Chưa triển khai hạ tầng AWS hoặc code workload.
- Crossplane và kro bắt đầu ở Coach mode.
- Việc tiếp theo: review/commit có chủ đích bộ trạng thái, sau đó thực hiện Task 1
  trong active spec.

Trạng thái sống luôn phải lấy từ `workflows/active_context.md`; mục này chỉ giúp
người mới định hướng và có thể chậm hơn checkpoint mới nhất.

---

## 14. Quy tắc chống sa đà

- Không tiếp tục phát triển framework Eurus trong thời gian làm MVP, trừ lỗi làm
  gián đoạn workflow hiện tại.
- Không học cả stack trước khi làm; học theo dependency của phase.
- Không tạo tất cả spec cho mười tuần ngay từ đầu.
- Không thêm công nghệ vì “hay” hoặc vì agent đề xuất nếu không giải quyết exit criteria.
- Không xem số lượng file, số dòng code hay số controller là thước đo tiến độ.
- Tiến độ thật = exit criteria + evidence + khả năng giải thích + teardown an toàn.
