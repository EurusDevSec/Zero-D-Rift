---
id: ADR-0004
title: Shared RDS and separate recovery database
status: ACCEPTED
date: 2026-09-24
---

# Context

`RAGSandbox` cần PostgreSQL/pgvector nhưng mục tiêu provisioning đo từ lúc Argo CD phát hiện request đến khi application vượt readiness check. Tạo một RDS instance mới trong mỗi request sẽ đưa thời gian cấp phát database và chi phí instance vào critical path. Ảnh hưởng chính xác vẫn phải được đo; không ghi đây là kết quả đã quan sát.

PoC chỉ có tối đa hai tenant và sử dụng soft isolation. Vì vậy cần cân bằng giữa chi phí, thời gian provisioning và mức cô lập dữ liệu.

Data-recovery trial bao gồm snapshot, restore, thay đổi endpoint/secret và kiểm tra kết nối lại. Chạy destructive trial trên database phục vụ `RAGSandbox` có thể làm gián đoạn application và làm sai lệch evidence của hai thí nghiệm.

# Decision

1. Dùng một RDS PostgreSQL/pgvector được chuẩn bị trước làm shared platform service.
2. Không tạo RDS instance mới trong mỗi `RAGSandbox` request.
3. Mỗi sandbox dùng database hoặc schema riêng, DB role và credential riêng.
4. Application chỉ nhận credential giới hạn; không nhận administrative credential.
5. Bootstrap Job dùng database credential có privilege giới hạn để chuẩn bị database/schema/role. AWS IAM, nếu được dùng để đọc secret, không thay thế PostgreSQL authorization.
6. Recovery trial dùng RDS PoC hoặc clone riêng, không phá shared RDS chính.
7. Chỉ ghi recovery thành công khi data-integrity check và application reconnect đều pass.
8. ADR này không chốt engine version, instance class, Region, secret-integration method, provisioning owner hoặc chi phí thực tế; các mục đó vẫn `UNVERIFIED` cho đến task tương ứng.

# Alternatives considered

## Một RDS instance cho mỗi sandbox

Lợi ích:

- Failure domain và lifecycle tách biệt hơn.
- Cô lập database mạnh hơn logical database/schema.
- Teardown từng sandbox rõ hơn.

Hạn chế:

- Đưa RDS provisioning vào request critical path.
- Tăng fixed cost và số tài nguyên phải inventory.
- Tăng quota, teardown và operational overhead.
- Không phù hợp với PoC chỉ có tối đa hai tenant.

## Shared RDS cho application và recovery

Lợi ích:

- Ít instance hơn.
- Có thể tái sử dụng cùng môi trường database.

Rủi ro:

- Recovery trial có thể làm gián đoạn cả hai sandbox.
- Làm lẫn evidence provisioning và recovery.
- Có thể làm hỏng dữ liệu dùng cho demo chính.
- Tăng blast radius của thao tác destructive.

## Shared RDS cho application, DB/clone riêng cho recovery

Lợi ích:

- Giữ RDS creation ngoài provisioning path của sandbox.
- Cô lập destructive recovery experiment.
- Dễ phân biệt evidence của application provisioning và recovery.

Trade-offs:

- Vẫn tồn tại soft isolation và shared failure domain giữa các sandbox.
- Recovery DB/clone tạo thêm chi phí tạm thời.
- Cần quản lý snapshot, endpoint, secret và teardown riêng.
- Có thêm hai lifecycle database phải quản lý.

# Consequences

## Positive

- Provisioning path không phải chờ tạo RDS instance.
- Giảm số RDS instance thường trực trong phạm vi PoC.
- Recovery experiment không tác động shared RDS chính.
- Evidence provisioning và recovery tách biệt hơn.

## Trade-offs

- Hai sandbox vẫn chia sẻ instance-level capacity và failure domain.
- Database/schema không phải hard multi-tenancy.
- Có nguy cơ noisy neighbor.
- Cleanup logical database, role và credential cần được thực hiện đúng.
- Recovery environment làm tăng operational complexity.

## Security consequences

- Mỗi sandbox có DB role và credential riêng.
- Application không nhận administrative credential.
- Bootstrap Job chỉ có quyền cần thiết và trong thời gian cần thiết.
- Secret không được commit vào Git, log hoặc evidence.
- Negative test phải xác minh tenant A không truy cập data của tenant B.
- Recovery DB không được dùng để tuyên bố production-grade isolation.

## Cost consequences

- Shared RDS là fixed cost khi còn chạy.
- Storage, backup và manual snapshot vẫn có thể phát sinh chi phí.
- Recovery DB/clone chỉ nên tồn tại trong trial window đã phê duyệt.
- Teardown phải kiểm tra instance, storage, snapshot, log và retained backup.
- Không ghi số USD trước khi Task 5 xác minh giá và account credit.

# Evidence

- `docs/de_cuong_tot_nghiep_ver3.md`
  - MVP boundary: shared RDS cho RAGSandbox.
  - Recovery dùng RDS PoC hoặc clone riêng.
  - Recovery success cần data-integrity check và application reconnect.
- `docs/architecture/SYSTEM_DESIGN.md`
  - Shared RDS design.
  - Controlled data recovery boundary.
- `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`

Đây là design evidence, chưa phải runtime evidence. ADR này không khẳng định provisioning time, recovery time hoặc cost đã được đo.

# Revisit conditions

- Negative isolation test cho thấy tenant có thể truy cập dữ liệu tenant khác.
- Shared instance không đáp ứng workload profile hoặc xuất hiện noisy-neighbor đáng kể.
- Cost plan cho thấy phương án khác phù hợp hơn ngân sách.
- Recovery trial không thể cô lập an toàn bằng DB PoC/clone.
- Yêu cầu scope thay đổi sang hard multi-tenancy hoặc production-grade isolation.
- RDS provisioning/restore evidence làm thay đổi giả định hiện tại.

# Guardrails

- Không gọi namespace/database/schema là hard isolation.
- Không nói shared RDS “đã giảm chi phí/thời gian” trước khi đo.
- Không trộn Security Group drift remediation với RDS data recovery.
- Không quyết định provider/version/instance class trong ADR này.
- Không tuyên bố recovery thành công chỉ vì RDS restore hoàn tất; application phải reconnect và data-integrity check phải pass.
