# Version and Compatibility Matrix

## 1. Purpose and scope

Tài liệu này chốt baseline phiên bản có bằng chứng cho Zero D-Rift trước khi bắt
đầu bootstrap EKS. Nó không chứng minh rằng controller đã được cài hoặc hệ thống
đã chạy end-to-end.

Ngày kiểm tra nguồn: **2026-09-25**.

Phạm vi của Task 3 chỉ gồm đọc nguồn chính thức và kiểm tra công cụ cục bộ. Không
có AWS resource hoặc platform controller nào được tạo/cài đặt.

### Verification status

| Status | Ý nghĩa |
| --- | --- |
| `DOC_VERIFIED` | Phiên bản tồn tại và quan hệ compatibility được nguồn chính thức xác nhận. Chưa có runtime evidence của dự án. |
| `SOURCE_VERIFIED` | Phiên bản/release tồn tại trong nguồn chính thức, nhưng nguồn chưa xác nhận đầy đủ tổ hợp mà dự án cần. |
| `UNVERIFIED` | Chưa đủ bằng chứng để pin hoặc tuyên bố compatibility. Phải giữ mở đến verification gate được nêu. |
| `RUNTIME_VERIFIED` | Đã có run evidence của chính dự án. Task 3 chưa có hàng nào đạt trạng thái này. |

`Latest` không phải là một version pin. Mọi chart, OCI package và container image
phải được resolve thành version/digest bất biến trong manifest cài đặt hoặc run
manifest trước official trial.

## 2. Selected baseline

| Component | Selected version / digest | Official source | Checked date | Compatibility with project baseline | Status |
| --- | --- | --- | --- | --- | --- |
| Amazon EKS / Kubernetes | EKS minor `1.35`; EKS platform patch do AWS quản lý | [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html), [platform versions](https://docs.aws.amazon.com/eks/latest/userguide/platform-versions.html) | 2026-09-25 | EKS 1.35 đang trong standard support. Không pin platform patch như một user-managed dependency. | `DOC_VERIFIED` |
| EKS optimized AMI, system nodes | AL2023 standard variant; architecture và exact AMI ID `UNVERIFIED` | [AL2023 for EKS](https://docs.aws.amazon.com/eks/latest/userguide/al2023.html), [retrieve AMI ID](https://docs.aws.amazon.com/eks/latest/userguide/retrieve-ami-id.html) | 2026-09-25 | AL2023 dùng cgroup v2 và phù hợp EKS 1.35. Exact AMI release/ID phụ thuộc Region và phải resolve qua SSM khi Region được duyệt. | `DOC_VERIFIED` for OS family; AMI ID `UNVERIFIED` |
| EKS optimized AMI, GPU nodes | AL2023 NVIDIA variant; exact architecture, AMI ID and driver build `UNVERIFIED` | [EKS optimized accelerated AMI](https://docs.aws.amazon.com/eks/latest/userguide/ml-eks-optimized-ami.html) | 2026-09-25 | AL2023 NVIDIA AMI hỗ trợ Kubernetes 1.33 trở lên. Instance family, architecture, device plugin và Karpenter NodeClass cần EKS test. | `SOURCE_VERIFIED` |
| Argo CD | `v3.5.3`; image/chart digests `UNVERIFIED` | [v3.5.3 release](https://github.com/argoproj/argo-cd/releases/tag/v3.5.3), [tested Kubernetes versions](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/) | 2026-09-25 | Argo CD 3.5 được dự án kiểm thử với Kubernetes 1.33-1.36, gồm 1.35. | `DOC_VERIFIED` |
| Crossplane core | `v2.4.0`; chart/image digests `UNVERIFIED` | [v2.4.0 release](https://github.com/crossplane/crossplane/releases/tag/v2.4.0), [install prerequisites](https://docs.crossplane.io/latest/get-started/install/) | 2026-09-25 | Release hiện hành và yêu cầu Kubernetes còn được upstream hỗ trợ. Exact pairing với AWS provider v2.7.0 chưa có matrix chính thức được tìm thấy. | `SOURCE_VERIFIED`; pairing `UNVERIFIED` |
| Crossplane AWS provider family | Candidate `v2.7.0`; exact OCI package refs/digests `UNVERIFIED` | [provider release v2.7.0](https://github.com/crossplane-contrib/provider-upjet-aws/releases/tag/v2.7.0), [provider repository](https://github.com/crossplane-contrib/provider-upjet-aws) | 2026-09-25 | Release dùng `crossplane-runtime v2.3.3`; điều này không tự chứng minh Crossplane core v2.4.0 + provider v2.7.0. Phải kiểm tra Provider/ProviderRevision health và CRDs trên kind trước AWS. | `SOURCE_VERIFIED`; combination `UNVERIFIED` |
| kro | `0.9.4`; chart/image digest `UNVERIFIED` | [kro 0.9.4 installation](https://kro.run/docs/getting-started/Installation/) | 2026-09-25 | Nguồn chính thức có pinned Helm version 0.9.4 nhưng không công bố matrix Kubernetes 1.35. CRD lifecycle và RGD reconcile cần kind test. | `SOURCE_VERIFIED`; K8s 1.35 `UNVERIFIED` |
| KEDA | `v2.21.0`; chart/image digests `UNVERIFIED` | [v2.21.0 release](https://github.com/kedacore/keda/releases/tag/v2.21.0), [KEDA 2.21 deployment](https://keda.sh/docs/2.21/deploy/) | 2026-09-25 | KEDA 2.21 được upstream kiểm thử với Kubernetes 1.34-1.36. Token-audience change phải được review khi thiết kế TriggerAuthentication/IRSA. | `DOC_VERIFIED` |
| Karpenter AWS provider | `v1.14.1` LTS; chart/image digests `UNVERIFIED` | [v1.14.1 release](https://github.com/aws/karpenter-provider-aws/releases/tag/v1.14.1), [compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/) | 2026-09-25 | Kubernetes 1.35 yêu cầu Karpenter 1.9 trở lên; 1.14.1 thỏa điều kiện. AL2023 NodeClass, IAM, EC2, Spot/GPU behavior vẫn cần EKS evidence. | `DOC_VERIFIED` |
| Kyverno | `v1.19.1`; chart/image digests `UNVERIFIED` | [v1.19.1 release](https://github.com/kyverno/kyverno/releases/tag/v1.19.1), [supported releases](https://main.kyverno.io/docs/installation/releases/) | 2026-09-25 | Kyverno 1.19 hỗ trợ Kubernetes 1.33-1.35. Policy behavior của PoC vẫn cần L2 test. | `DOC_VERIFIED` |
| OpenCost | Candidate Helm chart `2.5.20` / app `1.120.2`; digests `UNVERIFIED` | [chart 2.5.20 release](https://github.com/opencost/opencost-helm-chart/releases/tag/opencost-2.5.20), [installation requirements](https://opencost.io/docs/installation/install/) | 2026-09-25 | Docs yêu cầu Kubernetes 1.21+ nhưng chỉ nêu tested support cũ đến 1.28; không đủ để chứng nhận 1.35. Cần security recheck, kind smoke test và EKS/AWS billing validation trước khi pin. | `UNVERIFIED` |
| Prometheus dependency | Version/chart/digest `UNVERIFIED` | [OpenCost installation requirements](https://opencost.io/docs/installation/install/) | 2026-09-25 | OpenCost cần Prometheus. Task 3 chưa chọn distribution/version vì P7 sẽ chốt metrics stack. | `UNVERIFIED` |

### EKS and AL2023 constraints carried forward

- EKS 1.35 loại bỏ đường chạy cgroup v1 mặc định; AL2023 dùng cgroup v2.
- AL2 không phải lựa chọn cho EKS 1.35: Kubernetes 1.32 là release cuối có
  EKS-optimized AL2 AMI.
- Exact EKS platform version có thể được AWS nâng tự động trong cùng minor; evidence
  của trial phải ghi observed platform version thay vì coi một patch hiện tại là pin.
- Containerd 1.x là generation cuối được EKS 1.35 hỗ trợ; P2 phải kiểm tra runtime
  thực tế và không xây automation phụ thuộc vào containerd 1.x cho lần nâng 1.36.
- Region, architecture, exact AL2023 AMI ID, GPU instance family và NVIDIA device
  plugin vẫn `UNVERIFIED`.

## 3. Crossplane AWS provider package scope

Không cài toàn bộ AWS provider family chỉ vì package tồn tại. Package được chọn
theo resource ownership trong ADR-0003.

| Provider package | Task 3 disposition | Reason / verification gate |
| --- | --- | --- |
| `provider-family-aws` | Required dependency, candidate `v2.7.0` | Exact OCI reference/digest và health phải được capture khi cài ở L2. |
| `provider-aws-s3` | Selected candidate `v2.7.0` | Golden-path/checkpoint S3 nằm trong approved scope; exact managed resources và lifecycle policy cần design/spec. |
| `provider-aws-ec2` | Selected candidate `v2.7.0` | Security Group drift experiment cần EC2 API group; không trao quyền quản lý bootstrap VPC/EKS. |
| `provider-aws-sqs` | Conditional, `UNVERIFIED` | Shared SQS ownership chưa được chốt; chỉ chọn nếu ownership matrix giao lifecycle cho Crossplane. |
| `provider-aws-rds` | Not selected for request path | ADR-0004 giữ shared RDS ngoài mỗi request; provisioning owner của shared/recovery RDS chưa được chốt. |
| `provider-aws-iam` | Not selected | Bootstrap/workload IAM boundary chưa có least-privilege design; không cấp IAM management mặc định cho Crossplane. |
| `provider-aws-eks` | Excluded | Terraform sở hữu EKS theo ADR-0003; cài package này sẽ làm mờ ownership boundary. |

Provider v2.7.0 là candidate chung, không phải tuyên bố runtime compatibility.
Trước khi AWS access được cấp, L2 phải chứng minh tối thiểu:

1. Crossplane core trở thành healthy.
2. Các Provider/ProviderRevision đã chọn trở thành healthy và active như mong đợi.
3. CRDs cần cho S3 bucket và EC2 SecurityGroup tồn tại.
4. `crossplane render`/schema checks không báo API mismatch.
5. Không có package ngoài ownership allowlist được cài.

## 4. Local-first decision and parity gaps

### Proposed choice: kind

ADR-0005 đề xuất `kind v0.33.0` với image Kubernetes 1.35.8 được pin bằng
digest:

```text
kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0
```

Nguồn: [kind v0.33.0 release](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0).

`k3d v5.9.0` là alternative đã review nhưng không chọn. Nó chạy K3s, trong khi
kind cung cấp upstream Kubernetes node image đúng minor 1.35 và immutable digest,
phù hợp hơn cho CRD, admission và reconciliation compatibility spike.

| Capability | kind evidence can cover | Must be re-verified on EKS |
| --- | --- | --- |
| Kubernetes 1.35 APIs, CRDs, webhooks | Yes | EKS platform-specific admission/configuration |
| Argo CD, Crossplane, kro, KEDA, Kyverno install health | Yes, after approved L2 micro-lab | Production sizing, IRSA and AWS integration |
| Crossplane render/schema and provider package health | Yes without AWS credentials | Real AWS API permissions, lifecycle and external resource status |
| IRSA / EKS OIDC / STS | No | Yes |
| VPC CNI, ENI and EKS NetworkPolicy behavior | No | Yes |
| Karpenter EC2, Spot, GPU and node reclamation | No | Yes |
| AL2023 standard/NVIDIA node behavior | No | Yes |
| S3, SQS, RDS and Security Group semantics | No | Yes |
| AWS LoadBalancer/NLB, quotas and service limits | No | Yes |
| OpenCost allocation logic | Partial | AWS pricing configuration and billing reconciliation |

The local choice remains `PROPOSED` until owner review and a later L2 kind
micro-lab. It must not be described as EKS parity.

## 5. Evidence and open gates

### Local probe on 2026-09-25

Read-only command lookup found:

- `kubectl v1.33.5` installed.
- Docker, kind, k3d and Helm not found on `PATH`.

No tool was installed and no cluster was created. Therefore all project runtime
status remains `UNVERIFIED`.

### Required before P2/P3 installation or official trials

1. Owner reviews ADR-0005 and explains why kind is useful but not EKS-equivalent.
2. Install prerequisites only in the implementation task that explicitly permits it.
3. Run the L2 kind compatibility lab and retain command output/run ID.
4. Resolve chart/OCI/image digests and record them in Git or a run manifest.
5. Recheck every release/security status immediately before installation; this
   matrix is a dated decision record, not an auto-updating dependency feed.
6. Verify Region, EKS add-ons, AMI IDs, IRSA, IAM actions and AWS-specific behavior
   in P2/P3 before any official trial.

## 6. Task 3 conclusion

- EKS 1.35 + AL2023 is the documented bootstrap baseline.
- Argo CD 3.5.3, KEDA 2.21.0, Karpenter 1.14.1 and Kyverno 1.19.1 have direct
  documentation supporting Kubernetes 1.35.
- Crossplane 2.4.0, AWS provider family 2.7.0 and kro 0.9.4 are release candidates
  whose exact combination still requires L2 evidence.
- OpenCost is deliberately not pinned as compatible with Kubernetes 1.35 yet.
- kind is the proposed local-first environment; AWS-specific claims remain blocked
  until EKS evidence exists.
