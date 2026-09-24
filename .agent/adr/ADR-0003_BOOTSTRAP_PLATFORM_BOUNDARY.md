---
id: ADR-0003
title: Bootstrap plane and platform control plane boundary
status: PROPOSED
date: 2026-09-17
---

# Context

## Bootstrap dependency

Zero D-Rift cần một Kubernetes cluster hoạt động trước khi cài đặt các platform controllerrs, Argo CD, kro và Crossplane đều chạy dưới dạng workload trong Kubernetes, nên chúng phụ thuộc vào Kubernetes API, networking, system node và bootstrap identity đã sẵn sàng.

## Overlapping ownership

Terraform và Crossplane đều có khả năng quản lý một số AWS resources như IAM, SG, S3, RDS. Nếu không xác định ownership rõ ràng, cùng một resource hoặc cùng một lifecycle concern có thể dược mô tả trong cả Terraform state và Crossplane managed resource.

## P2 risks

- Thứ nhất là chồng chéo ownership
  Nếu Terraform, Crossplane cùng quản lý một AWS resource, hai desired state có thể mâu thuẫn:

Terraform apply thay đổi resource -> Crossplane phát hiện khác desired state -> Crossplane sẽ đổi ngược lại

Như vậy sẽ tách biệt được vai trò và trách nhiệm giữa các công cụ và tránh nguy cơ tạo reconciliation loop hoặc configuration drift

- Thứ hai Bootstrap dependency vòng tròn
  Vì Crossplane chạy dưới dạng Pod trong EKS. Nếu yêu cầu Crosplane tạo chính EKS đầu tiên chứa nó:
  thì Crossplane cần EKS để chạy còn EKS lại cần Crossplane để được tạo -> circular dependency

-> Điều này làm P2 không thể bootstrap từ trạng thái ban đầu một cách tái lập

- Teardown không xác định
  Nếu không biết công cụ nào sở hữu resource nào:

* Terraform destroy có thể bỏ sót resoủce do Crossplane tạo
* Xoá managed resource có thể xoá nhầm resource cần retain
* VPC, ENI, Load Balancer, EBS, hoặc IAM có thể chặn việc xoá EKS.
* Resource còn sót tiếp tục gây chi phí.

Điều này trực tiếp làm hỏng exit criterion của P2: tạo và xoá EKS bằng quy tình được tài liệu hoá.

- State và evidence không rõ ràng
  Terraform có state riêng: Crossplane lưu desired state và status trong Kubernetes API.

Neesu boundary không rõ, khi resource sai trạng thái sẽ không biết phải kiểm tra:

- Terraform state
- Kubernetes managed resource
- Crossplane conditions
- AWS actual state.

P2 sẽ khó chứng minh resource được tạo bởi công cụ nào và bằng evidence nào

- IAM có thể rộng quá mức

Terraform cần quền bootstrap EKS và IAM nền. Crossplane chỉ nên có quyền cho selected AWS resources.
Nếu không tách boundary, Crossplane provider có thể được cấp quyền bootstrap/admin rộng

# Decision

- Terraform sở hữu các bootstrap resource như:

* VPC và networking nền
* EKS control plane
* EKS OIDC provider
* system node group
* Bootstrap IAM
* Logging cơ bản và budget controls
* Terraform state của những bootstrap resource trên

> Tuyệt đối không đưa mọi S3, SQS hay Security Group của Golden path vào ownership này

- Điều kiện trước khi cài platform controllers

* EKS Kubernetes API truy cập được
* System nodes đã `Ready`
* Quyền quản trị bootstrap/kubeconfig hoạt động
* OIDC và IAM nên đã được cấu hình.
* Cluster có đủ capacity để chạy controller.
* Version và cấu hình cần thiết đã được phê duyệt trong P1/P2
  KHÔNG CẦN ghi chi tiết command trong ADR

- Trách nhiệm platform controllers(Argo CD, kro, Crossplane)

* Argo CD: đồng bộ desired state từ Git vào cluster.
* kro: cung cấp golden-path API, tạo dependency graph và tổng hợp readiness.
* Crossplane: reconcile selected AWS external resource thông qua provider.

> Mỗi resource chỉ có một primary lifecycle owner, Terraform và Crossplane không đồng thời quản lý một resource nếu chưa có quy trình handoff rõ ràng.

- Những gì giữ `UNVERIFIED`
  Không chốt trong ADR-0003:

* Exact Kubernetes/EKS/controller versions.
* AWS Region.
* Network egress design.
* Crossplane provider packages.
* Exact IAM actions và resource ARN.
* Management/deletions policies.
* Secret integration method
* Terraform state backend cụ thể nếu chưa có evidence

# Alternatives considered

### Terraform quản lý tất cả resource

Lợi ích cần phân tích

- Một workflow và một state model
- Bootstrap/teardown dễ lần theo
- Công nghệ đã quen thuộc hơn

Hạn chế:

- Không phù hợp API-service chạy theo Kubernêts custom resource.
- Không cung cấp continuous in-cluster reconciliation theo thiết kế.
- Khó phản ánh external-resource status vào golden path
- Không đáp ứng đúng thí nghiệm Crossplane Security Group remediation.

### Crossplane bootstrap cluster đầu tiên

Lợi ích:

- Có thể thống nhất resource dưới Kubernetes API nếu đã tồn tại một management cluster khác.
- Có continuous reconciliation ngay từ đầu.

Hạn chế:

- Crossplane cần Kubernetes để chạy nhưng EKS đầu tiên chưa tồn tại
- Tạo circular dependency.
- Muốn giải quyết phải có management cluster riêng, làm tăng scope, cost và vận hành
- Mâu thuẫn với PoC một EKS cluster và không cần thiết cho đề tài

## Terraform bootstrap, Crossplane continuous reconciliation

Lợi ích:

- Terraform giải quyết bootstrap dependency.
- Crossplane thực hiện continuous reconciliation cho selected resource.
- Phù hợp dependency order của dự án
- Hỗ trợ thí nghiệm drift remediation
- Giữ Terraform và Crossplane trong phạm vi trách nhiệm riêng.

Hạn chế:

- Có hai state/reconciliation model.
- Cần ownership matrix rõ ràng.
- Troubleshooting và teardown phức tạp hơn.
- Cần quy định thứ tự cài đặt và xoá tài nguyên.

## Consequences

### Positive

- P2 có dependency order rõ và bootstrap tái lập được
- Mỗi resource có primảy owner.
- Platform controller không phụ thuộc vòng tròn vào cluster chưa tồn tại.
- Crossplane vẫn được sử dụng cho continuous reconciliation và drift experiment.
- Teardown có thể lần theo ownership thay vì xoá mù.

### Trade-offs

Các chi phí quyết định:

- Phải vận hành cả Terraform và Crossplane.
- Có Terraform state và Kubernetes managed-resource status.
- Người vận hành phải biết lỗi thuộc boundary nào.
- Resource handoff/import giữa hai công cụ cần quy trình riêng.
- Tearndown cần đúng thứ tự.

| Risk                                                      | Mitigation                                                                        |
| --------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Cùng một resource bị Terraform và Crossplane quản lý      | Duy trì ownership matrix; không dual-manage nếu chưa có ADR handoff               |
| Controller được cài khi cluster/system node chưa sẵn sàng | Dùng readiness gate trước bước cài platform                                       |
| Resource Crossplane còn sót sau Terraform destroy         | Inventory và xóa selected external resources trước bootstrap teardown             |
| Crossplane provider có quyền quá rộng                     | Dùng least-privilege IAM và negative-access tests                                 |
| Xóa managed resource làm mất dữ liệu                      | Giữ deletion/management policy là `UNVERIFIED` đến khi version được pin và review |
| Terraform state bị mất hoặc không khớp                    | Chốt state backend, locking và recovery procedure trong P2 trước AWS apply        |
| Boundary không đủ rõ khi troubleshoot                     | Ghi owner, desired-state source và evidence location cho từng resource class      |

## Evidence

Có thể bổ sung SPEC đang điều khiển quyết định:

```md
- `docs/de_cuong_tot_nghiep_ver3.md`
- `docs/architecture/SYSTEM_DESIGN.md`
- `.agent/specs/SPEC-P1_FOUNDATION_AND_COMPATIBILITY.md`
```

Ghi rõ đây là design evidence, chưa phải runtime evidence. Không ghi `PASS` hoặc tuyên bố AWS đã được kiểm chứng.

## 6. Revisit conditions

Quyết định cần xem lại khi:

- Dự án chuyển sang management cluster riêng.
- Scope chuyển thành multi-cluster hoặc multi-account.
- P2 chứng minh boundary hiện tại làm bootstrap/teardown không tái lập được.
- Một resource cần chuyển ownership giữa Terraform và Crossplane.
- Version/provider evidence cho thấy lifecycle dự kiến không được hỗ trợ.
- Nhà trường hoặc canonical ver3 thay đổi phạm vi kiến trúc.

Không dùng ngày cố định; dùng điều kiện kỹ thuật có thể quan sát.
