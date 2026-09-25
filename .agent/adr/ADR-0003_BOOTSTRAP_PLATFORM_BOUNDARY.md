---
id: ADR-0003
title: Bootstrap plane and platform control plane boundary
status: ACCEPTED
date: 2026-09-17
---

# Context

## Bootstrap dependency

Zero D-Rift cần một Kubernetes cluster hoạt động trước khi cài đặt các platform controllers. Argo CD, kro và Crossplane đều chạy dưới dạng workload trong Kubernetes, nên chúng phụ thuộc vào Kubernetes API, networking, system nodes và bootstrap identity đã sẵn sàng.

## Overlapping ownership

Terraform và Crossplane đều có khả năng quản lý một số AWS resources như IAM, Security Group, S3 và RDS. Nếu không xác định ownership rõ ràng, cùng một resource hoặc cùng một lifecycle concern có thể được mô tả trong cả Terraform state và Crossplane managed resource.

## P2 risks

- Chồng chéo ownership: nếu Terraform và Crossplane cùng quản lý một AWS resource, hai desired state có thể mâu thuẫn:

Terraform thay đổi resource → Crossplane phát hiện khác desired state → Crossplane đổi ngược lại.

Vì vậy, resource ownership phải được tách rõ để tránh reconciliation loop và configuration drift do hai công cụ tự tạo ra.

- Bootstrap dependency vòng tròn: Crossplane chạy dưới dạng Pod trong EKS. Nếu yêu cầu Crossplane tạo chính EKS đầu tiên chứa nó, Crossplane cần EKS để chạy còn EKS lại cần Crossplane để được tạo.

Điều này làm P2 không thể bootstrap từ trạng thái ban đầu một cách tái lập.

- Teardown không xác định: nếu không biết công cụ nào sở hữu resource nào:

  - Terraform destroy có thể bỏ sót resource do Crossplane tạo.
  - Xóa managed resource có thể xóa nhầm resource cần retain.
  - VPC, ENI, Load Balancer, EBS hoặc IAM có thể chặn việc xóa EKS.
  - Resource còn sót tiếp tục gây chi phí.

Điều này trực tiếp làm hỏng exit criterion của P2: tạo và xóa EKS bằng quy trình được tài liệu hóa.

- State và evidence không rõ ràng: Terraform có state riêng; Crossplane lưu desired state và status trong Kubernetes API.

Nếu boundary không rõ, khi resource sai trạng thái sẽ không biết phải kiểm tra:

- Terraform state
- Kubernetes managed resource
- Crossplane conditions
- AWS actual state.

P2 sẽ khó chứng minh resource được tạo bởi công cụ nào và bằng evidence nào.

- IAM có thể rộng quá mức:

Terraform cần quyền bootstrap EKS và IAM nền. Crossplane chỉ nên có quyền cho selected AWS resources.
Nếu không tách boundary, Crossplane provider có thể được cấp quyền bootstrap/admin rộng.

# Decision

- Terraform sở hữu các bootstrap resource như:

  - VPC và networking nền.
  - EKS control plane.
  - EKS OIDC provider.
  - System node group.
  - Bootstrap IAM.
  - Logging cơ bản và budget controls.
  - Terraform state của những bootstrap resource trên.

> Golden-path S3, SQS và Security Group không mặc định thuộc Terraform; primary lifecycle owner của từng resource class phải được ghi rõ trước khi triển khai.

- Điều kiện trước khi cài platform controllers

  - EKS Kubernetes API truy cập được.
  - System nodes đã `Ready`.
  - Quyền quản trị bootstrap/kubeconfig hoạt động.
  - OIDC provider và bootstrap IAM đã được cấu hình.
  - Cluster có đủ capacity để chạy platform controllers.
  - Version và cấu hình cần thiết đã được phê duyệt trước bước cài đặt tương ứng.

- Trách nhiệm platform controllers (Argo CD, kro, Crossplane):

  - Argo CD: đồng bộ desired state từ Git vào cluster.
  - kro: cung cấp golden-path API, tạo dependency graph và tổng hợp readiness.
  - Crossplane: reconcile selected AWS external resources thông qua provider.

> Mỗi resource chỉ có một primary lifecycle owner, Terraform và Crossplane không đồng thời quản lý một resource nếu chưa có quy trình handoff rõ ràng.

- Những gì giữ `UNVERIFIED`:

  Không chốt trong ADR-0003:

  - Exact Kubernetes/EKS/controller versions.
  - AWS Region.
  - Network egress design.
  - Crossplane provider packages.
  - Exact IAM actions và resource ARN.
  - Management/deletion policies.
  - Secret integration method.
  - Terraform state backend cụ thể nếu chưa có evidence.

# Alternatives considered

## Terraform quản lý tất cả resource

Lợi ích:

- Một workflow và một state model.
- Bootstrap/teardown dễ lần theo.
- Công nghệ đã quen thuộc hơn.

Hạn chế:

- Không phù hợp với API self-service dựa trên Kubernetes custom resource.
- Không cung cấp continuous in-cluster reconciliation theo thiết kế.
- Khó phản ánh external-resource status vào golden path.
- Không đáp ứng đúng thí nghiệm Crossplane Security Group remediation.

## Crossplane bootstrap cluster đầu tiên

Lợi ích:

- Có thể thống nhất resource dưới Kubernetes API nếu đã tồn tại một management cluster khác.
- Có continuous reconciliation ngay từ đầu.

Hạn chế:

- Crossplane cần Kubernetes để chạy nhưng EKS đầu tiên chưa tồn tại.
- Tạo circular dependency.
- Muốn giải quyết phải có management cluster riêng, làm tăng scope, cost và vận hành.
- Mâu thuẫn với PoC một EKS cluster và không cần thiết cho đề tài.

## Terraform bootstrap, Crossplane continuous reconciliation

Lợi ích:

- Terraform giải quyết bootstrap dependency.
- Crossplane thực hiện continuous reconciliation cho selected resource.
- Phù hợp dependency order của dự án.
- Hỗ trợ thí nghiệm drift remediation.
- Giữ Terraform và Crossplane trong phạm vi trách nhiệm riêng.

Hạn chế:

- Có hai state/reconciliation model.
- Cần ownership matrix rõ ràng.
- Troubleshooting và teardown phức tạp hơn.
- Cần quy định thứ tự cài đặt và xoá tài nguyên.

# Consequences

## Positive

- P2 có dependency order rõ và một boundary để xây dựng quy trình bootstrap tái lập.
- Mỗi resource có primary owner.
- Platform controller không phụ thuộc vòng tròn vào cluster chưa tồn tại.
- Crossplane vẫn được sử dụng cho continuous reconciliation và drift experiment.
- Teardown có thể lần theo ownership thay vì xóa mù.

## Trade-offs

Các chi phí quyết định:

- Phải vận hành cả Terraform và Crossplane.
- Có Terraform state và Kubernetes managed-resource status.
- Người vận hành phải biết lỗi thuộc boundary nào.
- Resource handoff/import giữa hai công cụ cần quy trình riêng.
- Teardown cần đúng thứ tự.

| Risk                                                      | Mitigation                                                                        |
| --------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Cùng một resource bị Terraform và Crossplane quản lý      | Duy trì ownership matrix; không dual-manage nếu chưa có ADR handoff               |
| Controller được cài khi cluster/system node chưa sẵn sàng | Dùng readiness gate trước bước cài platform                                       |
| Resource Crossplane còn sót sau Terraform destroy         | Inventory và xóa selected external resources trước bootstrap teardown             |
| Crossplane provider có quyền quá rộng                     | Dùng least-privilege IAM và negative-access tests                                 |
| Xóa managed resource làm mất dữ liệu                      | Giữ deletion/management policy là `UNVERIFIED` đến khi version được pin và review |
| Terraform state bị mất hoặc không khớp                    | Chốt state backend, locking và recovery procedure trong P2 trước AWS apply        |
| Boundary không đủ rõ khi troubleshoot                     | Ghi owner, desired-state source và evidence location cho từng resource class      |

# Evidence

- `docs/de_cuong_tot_nghiep_ver3.md`
- `docs/architecture/SYSTEM_DESIGN.md`
- `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`

Đây là design evidence, chưa phải runtime evidence. ADR này không ghi `PASS` hoặc tuyên bố AWS đã được kiểm chứng.

# Revisit conditions

Quyết định cần xem lại khi:

- Dự án chuyển sang management cluster riêng.
- Scope chuyển thành multi-cluster hoặc multi-account.
- P2 chứng minh boundary hiện tại làm bootstrap/teardown không tái lập được.
- Một resource cần chuyển ownership giữa Terraform và Crossplane.
- Version/provider evidence cho thấy lifecycle dự kiến không được hỗ trợ.
- Nhà trường hoặc canonical ver3 thay đổi phạm vi kiến trúc.

Không dùng ngày cố định; dùng điều kiện kỹ thuật có thể quan sát.
