---
id: ADR-0005
title: kind as the local-first compatibility environment
status: PROPOSED
date: 2026-09-25
---

# Context

Zero D-Rift cần một local-first environment để kiểm tra Kubernetes API, CRD,
webhook và controller reconciliation trước khi tạo paid EKS resources. Canonical
scope cho phép chọn `kind` hoặc `k3d`, nhưng yêu cầu mọi hành vi phụ thuộc AWS
phải được xác nhận lại trên EKS thật.

Baseline của dự án là EKS/Kubernetes 1.35. Lựa chọn local cần ưu tiên:

- chạy đúng upstream Kubernetes minor 1.35;
- pin node image bằng immutable digest;
- phù hợp compatibility spike cho controller và CRD;
- không tạo ảo tưởng rằng local cluster tương đương EKS.

# Proposed decision

Chọn `kind v0.33.0` làm local-first environment với node image:

```text
kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0
```

Decision chỉ được chuyển sang `ACCEPTED` sau khi owner review và L2 micro-lab
chứng minh cluster 1.35 khởi động được cùng những controller được task triển khai
cho phép. Task 3 không cài controller và không tạo cluster.

# Why kind

- kind release cung cấp upstream Kubernetes 1.35.8 image và công bố digest cần
  dùng để tái lập đúng artifact.
- Project cần kiểm tra CRD, admission webhook và reconciliation behavior gần với
  upstream Kubernetes API hơn là các tối ưu/bundled components của K3s.
- Cùng minor 1.35 giúp giảm một biến số khi chuyển từ local compatibility test
  sang EKS, dù không loại bỏ EKS-specific gaps.

# Alternative considered: k3d

`k3d v5.9.0` chạy K3s trong container và hỗ trợ workflow local nhanh. Nó không
được chọn vì K3s không phải distribution/control-plane packaging của EKS hoặc
upstream kind node. Các bundled/default components và behavior riêng của K3s làm
tăng một biến số không cần thiết cho compatibility spike này.

K3d có thể được xem lại nếu kind không chạy ổn định trên workstation và lỗi được
chứng minh là do local runtime thay vì manifest/controller.

# Consequences

## Positive

- Local test pin đúng Kubernetes 1.35 minor và immutable node-image digest.
- Có nơi chạy L2 checks trước khi sử dụng AWS credits.
- Controller/CRD incompatibility có thể được phát hiện sớm mà không phát sinh
  EKS hourly cost.

## Trade-offs

- Cần Docker-compatible container runtime, kind, Helm và đủ RAM/CPU cục bộ.
- kind networking, storage và load balancer không mô phỏng chính xác EKS.
- Local success không phải evidence cho AWS IAM, cost, quota hoặc external API.

# Explicit parity gaps

Các nội dung sau không được xác nhận bằng kind và phải chạy lại trên EKS:

- EKS control plane/platform version và managed add-ons.
- AL2023 nodes, cgroup/runtime configuration và NVIDIA/GPU behavior.
- IRSA, EKS OIDC, STS và least-privilege IAM.
- VPC CNI, ENI, NetworkPolicy behavior và AWS load balancer integration.
- Karpenter EC2/Spot/GPU capacity, disruption và reclamation.
- Real S3, SQS, RDS, Security Group reconciliation và AWS service quotas.
- OpenCost AWS pricing configuration và đối soát với billing data.

# Evidence

- `docs/VERSION_MATRIX.md`
- [kind v0.33.0 release](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)
- [k3d v5.9.0 release](https://github.com/k3d-io/k3d/releases/tag/v5.9.0)
- `docs/de_cuong_tot_nghiep_ver3.md`

Đây là documentation evidence. Local runtime evidence chưa tồn tại vì Docker,
kind và Helm chưa có trên `PATH` tại thời điểm Task 3 probe.

# Acceptance checks

Trước khi đổi status sang `ACCEPTED`:

1. Owner giải thích được hai điều kind kiểm tra được và hai điều bắt buộc kiểm tra
   lại trên EKS.
2. kind tạo cluster bằng image/digest đã pin.
3. Observed Kubernetes version là 1.35.x.
4. L2 task lưu run ID/log và cleanup cluster theo documented procedure.
5. Nếu node image/digest thay đổi, `docs/VERSION_MATRIX.md` và ADR được review lại.

# Revisit conditions

- Workstation không thể chạy kind ổn định với controller stack tối thiểu.
- EKS minor baseline thay đổi khỏi 1.35.
- Controller compatibility yêu cầu Kubernetes patch/minor khác.
- Local testing cần capability mà kind không cung cấp và k3d hoặc môi trường khác
  có evidence tốt hơn.
