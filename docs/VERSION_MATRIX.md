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
| EKS optimized AMI, system nodes | AL2023 standard variant; architecture và exact AMI ID `UNVERIFIED` | [AL2023 for EKS](https://docs.aws.amazon.com/eks/latest/userguide/al2023.html), [retrieve AMI ID](https://docs.aws.amazon.com/eks/latest/userguide/retrieve-ami-id.html) | 2026-09-25 | AL2023 dùng cgroup v2 và phù hợp EKS 1.35. Exact AMI release/ID phải resolve qua SSM cho selected Region trong P2. | `DOC_VERIFIED` for OS family; AMI ID `UNVERIFIED` |
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
- Architecture, exact AL2023 AMI ID, GPU instance family và NVIDIA device plugin
  vẫn `UNVERIFIED`; Region đã chọn là `us-east-1` nhưng runtime/capacity chưa verify.

## 3. Crossplane AWS provider package scope

Không cài toàn bộ AWS provider family chỉ vì package tồn tại. Package được chọn
theo resource ownership trong ADR-0003.

| Provider package | Task 3 disposition | Reason / verification gate |
| --- | --- | --- |
| `provider-family-aws` | Required dependency, candidate `v2.7.0` | Exact OCI reference/digest và health phải được capture khi cài ở L2. |
| `provider-aws-s3` | Selected candidate `v2.7.0` | Golden-path/checkpoint S3 nằm trong approved scope; exact managed resources và lifecycle policy cần design/spec. |
| `provider-aws-ec2` | Selected candidate `v2.7.0` | Security Group drift experiment cần EC2 API group; không trao quyền quản lý bootstrap VPC/EKS. |
| `provider-aws-sqs` | Conditional, `UNVERIFIED` | Shared SQS ownership chưa được chốt; chỉ chọn nếu ownership matrix giao lifecycle cho Crossplane. |
| `provider-aws-rds` | Not selected | ADR-0004 giữ shared RDS ngoài mỗi request; ADR-0008 (ACCEPTED) giao shared RDS cho Terraform module `shared-rds`. Recovery RDS owner vẫn chốt ở P8. |
| `provider-aws-iam` | Not selected | ADR-0008 (ACCEPTED): mọi role workload P4 do Terraform module `rag-identity` tạo sẵn; Crossplane không có quyền IAM. |
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

Owner teach-back for the local/EKS boundary is complete. The local choice remains
`PROPOSED` until a later L2 kind micro-lab and must not be described as EKS parity.

## 5. Evidence and open gates

### Local probe on 2026-09-25

Read-only command lookup found:

- `kubectl v1.33.5` installed.
- Docker, kind, k3d and Helm not found on `PATH`.

No tool was installed and no cluster was created. Therefore all project runtime
status remains `UNVERIFIED`.

### Required before P2/P3 installation or official trials

1. Owner review/teach-back for ADR-0005 is complete; retain the local/EKS parity gaps.
2. Install prerequisites only in the implementation task that explicitly permits it.
3. Run the L2 kind compatibility lab and retain command output/run ID.
4. Resolve chart/OCI/image digests and record them in Git or a run manifest.
5. Recheck every release/security status immediately before installation; this
   matrix is a dated decision record, not an auto-updating dependency feed.
6. Carry forward selected Region `us-east-1`; verify EKS add-ons, AMI IDs, IRSA,
   IAM actions and AWS-specific behavior in P2/P3 before any official trial.

## 6. Task 3 conclusion

- EKS 1.35 + AL2023 is the documented bootstrap baseline.
- Argo CD 3.5.3, KEDA 2.21.0, Karpenter 1.14.1 and Kyverno 1.19.1 have direct
  documentation supporting Kubernetes 1.35.
- Crossplane 2.4.0, AWS provider family 2.7.0 and kro 0.9.4 are release candidates
  whose exact combination still requires L2 evidence.
- OpenCost is deliberately not pinned as compatible with Kubernetes 1.35 yet.
- kind is the proposed local-first environment; AWS-specific claims remain blocked
  until EKS evidence exists.

## 7. P3 control-plane pins (2026-11-05)

Rechecked on 2026-11-05 for SPEC-P3 Task 1 (DRF-34). Digests, sources and CRD
findings: `docs/evidence/p3/DRF34_P3_PINS_20261105.md`. These supersede the §2
candidates for Argo CD, Crossplane and the AWS provider; other rows are unchanged.

| Component | Pin | Digest | Status |
| --- | --- | --- | --- |
| Argo CD | `v3.5.7` (upstream `manifests/install.yaml`) | image `sha256:16df57da…4647de0db`; manifest sha256 `09bfbb90…a4551f5beb77` | `SOURCE_VERIFIED` |
| Crossplane core | chart/app `2.4.3` | image `sha256:1c66261d…aa2be638` | `SOURCE_VERIFIED` |
| provider-family-aws | `v2.8.1` | `sha256:ea0d1ff9…2db25f92` | `SOURCE_VERIFIED`; built on crossplane-runtime v2.4.0 |
| provider-aws-s3 | `v2.8.1` | `sha256:4e627727…807919bd` | `SOURCE_VERIFIED`; only AWS service package in P3 |
| kro | chart/image `v0.9.4`, `rbac.mode=aggregation` | image `sha256:eaf9fbad…3376fb9` | `SOURCE_VERIFIED` |
| kind | `v0.33.0` installed at `/r/_Dev_tools/kind` | binary sha256 `4b22adaa…1515c9fc` | Installed 2026-11-05 |

S3 bucket API for P3: `s3.aws.m.upbound.io/v1beta1` `Bucket` (namespaced). It has
no `deletionPolicy`; deletion is controlled by `managementPolicies`. Runtime status
moves to `RUNTIME_VERIFIED` only after the P3 kind lab (L2) and EKS window (L3).

## 8. P4 pins (2026-11-17)

Checked on 2026-11-17 for SPEC-P4 P4-T1 part B (DRF-40). Commands, raw output and
the kind/RDS parity table: `docs/evidence/p4/P4-T1_PINS_PRICES_20261117.md`. §7
pins carry over unchanged.

| Component | Pin | Digest / checksum | Status |
| --- | --- | --- | --- |
| RDS engine | PostgreSQL `17.11` (latest in `us-east-1`; the unpinned default is 17.9, so pin explicitly) | — | `ACCOUNT_VERIFIED` 2026-11-17 |
| RDS instance | `db.t4g.micro`, gp3, orderable for 17.11 in 5 AZs | — | `ACCOUNT_VERIFIED` 2026-11-17 |
| RDS TLS | family `postgres17` default `rds.force_ssl=1`; default CA `rds-ca-rsa2048-g1` | — | `ACCOUNT_VERIFIED` 2026-11-17 |
| pgvector on RDS | `0.8.2` for 17.11 | — | `RUNTIME_VERIFIED` 2026-11-21: L3 window `P4-L3-20261121-01`, `db-init` and `probe platform` saw 0.8.2 |
| RDS CA bundle | `us-east-1-bundle.pem` from `truststore.pki.rds.amazonaws.com` | sha256 `b1711d12…2462dd77` | `SOURCE_VERIFIED` |
| App base image | `python:3.13-slim` (Python 3.13.18, Debian trixie) | index `sha256:e48f59cd…6ee9ed90` | `SOURCE_VERIFIED` |
| kind database | `pgvector/pgvector:0.8.2-pg17` (PostgreSQL 17.10, pgvector 0.8.2) | index `sha256:feb68f4f…d1a33966` | `SOURCE_VERIFIED` |
| App Python tree | `workloads/rag-sandbox/requirements.txt`: psycopg 3.3.9, psycopg-binary 3.3.9, boto3 1.44.4, botocore 1.44.6 and 5 transitive packages, generated by `lock.sh` (pip-tools 7.7.0) | `--hash` on every package; image installs with `--require-hashes` | `SOURCE_VERIFIED` 2026-11-19 (DRF-50) |
| RAGSandbox image | `ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox`, built by `.github/workflows/rag-sandbox-image.yml` from `main` `e0c8319` (run 44976281003) | index `sha256:850c77c200a798b5706ce56c7878164d4887fcf3661bbec91b2d8564df735263` (linux/amd64 manifest `sha256:233e9440…` + build attestation); manifests use the index digest. Replaces `sha256:512e982a…` (`3d38719`, 21/11, the image of window `P4-L3-20261121-01`), which predates the Codex DRF-57 fixes C3, C4, C9 (PR #55) | `SOURCE_VERIFIED` 2026-11-22: anonymous pull and `smoke.sh` PASS on this digest |
| BatchTraining image | `ghcr.io/eurusdevsec/zero-d-rift/batch-training`, built by `.github/workflows/batch-training-image.yml` from `main` `3dd43b2` (PR #92, run 45650984635) | index `sha256:d2bb517d884710dd269285773b6fd5de74b631a4faafdb2fd2a3c0020cbb470e` (linux/amd64 manifest `sha256:53bf65d9…` + build attestation); the RGD `batch-training-job` uses the index digest | `SOURCE_VERIFIED` 2026-11-25: anonymous manifest read 200; kind lab ran the same source built locally |
| aws-cli (owner micro-lab) | `public.ecr.aws/aws-cli/aws-cli`, aws-cli `2.42.1` (Python 3.14.10) | `sha256:b0102d2269f87d8531d931c1a59e248101ace586886e6c077058d94c1c37b846` | `RUNTIME_VERIFIED` 2026-11-21: `aws --version` in the L3 window |
| CI actions | checkout v7.0.1, setup-buildx-action v4.4.1, login-action v4.8.0, build-push-action v7.4.0 | pinned by commit SHA in the workflow | `SOURCE_VERIFIED` 2026-11-19 |

Parity gap: kind runs PostgreSQL 17.10 against RDS 17.11, with no TLS by default and a
real superuser where the RDS master is only `rds_superuser` (limit already stated in
SPEC-P4 P4-T2.1). TLS `verify-full` is proven only in L3, unless the kind lab adds its
own CA.

## 9. P5 pins (2026-11-22)

Checked on 2026-11-22 for SPEC-P5 P5-T1 part B (DRF-64). Commands: `docs/runbooks/P5_PINS.md`;
results and decisions: `docs/evidence/p5/P5-T1_PINS_20261122.md`. These supersede the §2 Kyverno
row (`v1.19.1`); §7 and §8 pins carry over unchanged.

| Component | Pin | Digest | Status |
| --- | --- | --- | --- |
| Kyverno | `v1.20.0`, chart `3.10.0` (`kyverno.github.io/kyverno`); supported release, Kubernetes 1.34–1.37 | chart sha256 `55961392…1642c2a301` (equals the repository index) | `SOURCE_VERIFIED`; K8s 1.35 `DOC_VERIFIED` |
| Kyverno images | `kyverno`, `kyvernopre`, `background-controller`, `reports-controller`, `kyverno-cli` (`reg.kyverno.io`), `readiness-checker` (`ghcr.io`), all `v1.20.0`; cleanup controller off (D7) | index digests in the evidence file | `SOURCE_VERIFIED` |
| Kyverno policy API | `ValidatingPolicy` `policies.kyverno.io/v1` (CEL); `kyverno.io/v1` `ClusterPolicy` is deprecated in 1.20 | — | `SOURCE_VERIFIED` (rendered CRDs) |
| VPC CNI | add-on `v1.22.4-eksbuild.10` kept (default for 1.35 is now `.14`); NetworkPolicy needs 1.21+; schema has `enableNetworkPolicy` and `env.NETWORK_POLICY_ENFORCING_MODE` (`standard`/`strict`) | — | `ACCOUNT_VERIFIED` 2026-11-22 |

Runtime status moves to `RUNTIME_VERIFIED` only after the P5 kind labs (L2) and the EKS window (L3).

## 10. P6 pins (2026-11-25)

Checked on 2026-11-25 for SPEC-P6 P6-T1 (DRF-73). Results and decisions:
`docs/evidence/p6/P6-T1_PINS_20261125.md`. §7–§9 pins carry over unchanged.

| Component | Pin | Digest | Status |
| --- | --- | --- | --- |
| KEDA | `2.21.1`, chart `2.21.1` (`kedacore.github.io/charts`); Kubernetes 1.34–1.36 | chart sha256 `76b45621…91d8fb883e` (equals the repository index) | `SOURCE_VERIFIED` |
| KEDA images | `keda`, `keda-metrics-apiserver`, `keda-admission-webhooks` (`ghcr.io/kedacore`), all `2.21.1`; pinned through `image.*.tag` = `2.21.1@sha256:…` | index digests in the evidence file | `SOURCE_VERIFIED` |
| Karpenter | `1.15.3`, chart `oci://public.ecr.aws/karpenter/karpenter` `1.15.3` | chart `sha256:7fadb557…23328fe56ed`; controller `sha256:37ae6d13…7297b4814` (pinned by the chart) | `SOURCE_VERIFIED` |
| ElasticMQ (kind only) | `softwaremill/elasticmq-native:1.7.1` | `sha256:e4580ab9…ee71c24e05c` | `SOURCE_VERIFIED` |
| Worker base | `python:3.12-slim` | `sha256:191083cd…f5296f51b4b` | `SOURCE_VERIFIED` 2026-11-25 (tag moves) |
| S3 substitute (kind only) | Adobe S3Mock `5.2.3` (MinIO no longer published) | `sha256:ab01a694…8fca92` | D12, picked 25/11 (owner delegated); path-style only |

Runtime status moves to `RUNTIME_VERIFIED` only after the P6 kind lab (L2) and the EKS window (L3).

## 11. P7 pins (2026-11-28)

Checked on 2026-11-28 for SPEC-P7 P7-T2.1 (DRF-85). Results and the kind smoke:
`docs/evidence/p7/P7-T2.1_L2_KIND_OPENCOST_20261128.md`. Supersedes the §2 OpenCost and
Prometheus rows (candidate 2.5.20, `UNVERIFIED`). §7–§10 pins carry over unchanged.

| Component | Pin | Digest | Status |
| --- | --- | --- | --- |
| Prometheus | chart `prometheus` `30.0.1` (`prometheus-community.github.io/helm-charts`), app `v3.16.0`; server, kube-state-metrics, node exporter only | chart sha256 `4f18a8da…5cc55ecb6` (equals the index). `31.0.0` rejected: downloaded tgz ≠ index digest | `RUNTIME_VERIFIED` on kind 1.35.8 (L2); EKS pending |
| Prometheus images | server `v3.16.0`, config reloader `v0.95.2`, kube-state-metrics `v2.20.0`, node exporter `v1.13.1` | full digests in the evidence §2 | `RUNTIME_VERIFIED` on kind (imageID = pin) |
| OpenCost | chart `opencost` `2.5.35` (`opencost.github.io/opencost-helm-chart`), app `1.121.5` | chart sha256 `35c5ec22…6a2836db` (equals the index) | `RUNTIME_VERIFIED` on kind 1.35.8 (L2; default prices, not AWS); EKS pending |
| OpenCost images | `ghcr.io/opencost/opencost` and `opencost-ui`, both `1.121.5`, pinned through `tag` = `1.121.5@sha256:…` | full digests in the evidence §2 | `RUNTIME_VERIFIED` on kind (imageID = pin) |
