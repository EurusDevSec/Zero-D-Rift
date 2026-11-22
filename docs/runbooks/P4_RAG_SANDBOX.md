# P4 — RAGSandbox trên EKS: window L3, kiểm, test âm, retry, dọn (DRF-56)

Trạng thái: **hồ sơ để owner duyệt, chưa chạy.** Runbook này không cho phép apply.
Chỉ chạy khi owner đã gõ duyệt đúng window request ở phần A (SPEC-P4 ranh giới âm 10).

Nguồn: SPEC-P4 §4, §5 P4-T4.1, §10; D1–D12; ADR-0004, ADR-0008; THREAT_MODEL T06.
Dùng lại nguyên:
- [P2_L3_WINDOW](P2_L3_WINDOW.md) C (chuẩn bị), D (plan/apply), E (smoke), F (gỡ admin, destroy);
- [P3_RESOURCE_GRAPH](P3_RESOURCE_GRAPH.md) B2 (Argo CD), B5 (teardown platform);
- [P4_TERRAFORM_RAG](P4_TERRAFORM_RAG.md) D (cờ `enable_rag_platform`, `rag_iam_check`).

Phần này chỉ ghi **chỗ khác** và các bước P4. Lệnh chạy từ gốc repo trong Git Bash,
trừ khi ghi `cd infra/terraform`.

Công cụ mới của window (đều trong `infra/p4-window/`):
- `window.sh` gắn role cho ServiceAccount và provider, tạo `platform-config`, chạy Job
  `db-init`/`cleanup` và các probe. Mọi giá trị có account ID, ARN hay host RDS được đọc từ
  `terraform output -json rag_platform_config` và đưa thẳng vào `kubectl`, **không in ra**.
  `window.sh status` chỉ in có/không.
- `probe.py` chạy trong một Pod ngắn hạn của image đã pin, với đúng ServiceAccount cần kiểm.
  Đây là kiểm độc lập: không đi qua code `serve`, chỉ gọi app qua Service.

## Sơ đồ window

```
T-30   Chuẩn bị chỉ đọc: MFA, inventory CLEAN, IP, run.tfvars, AZ RDS, Bills ──┐ sai → dừng
T+0    plan (cờ admin + RAG) → plan_assert → shape hash KHỚP → rag_iam_check → apply
T+25   smoke P2 · rag_iam_check --principal · RDS private · registry probe
T+40   Argo CD + root app → annotate → db-init → probe platform → platform-config
T+60   2 sandbox Ready (H1 smoke) → probe sandbox ×2 → micro-lab owner
T+80   test âm: probe cross ×2 · request không có role (PR) · tên sai (CI đỏ)
T+110  retry: bootstrap-identity off → PR attempt 0 Failed → on → PR attempt 1 Ready
T+130  xoá 1 request (PR) → cleanup → sandbox kia vẫn PASS
freeze dọn: requests (cascade) → cleanup → secret bootstrap → B5 → Argo CD → destroy → inventory
```

## A. Window request (owner điền chỗ trống rồi duyệt)

Chép vào chat hoặc Linear DRF-56. **Không ghi account ID, ARN, IP, endpoint hay tên bucket state.**

```
WINDOW REQUEST — P4 L3
RunId:             P4-L3-YYYYMMDD-01
Bắt đầu:           YYYY-MM-DD HH:MM Asia/Saigon (= HH:MM UTC)
Kết thúc cứng:     bắt đầu + 5 giờ
Freeze-new-create: kết thúc cứng − 1,5 giờ (dọn P4 ≈ 10 phút requests/cleanup + 10 phút Argo + 20 phút destroy RDS/EKS + inventory)
expires_at (tag):  giờ kết thúc cứng, UTC ...Z (cũng là EXPIRES_AT của window.sh)
Teardown owner:    HoangLV, có mặt suốt window; không rời máy khi cluster hoặc RDS còn chạy
Git revision:      <commit main lúc plan>; nhánh chạy = main, git diff rỗng trên infra/ gitops/ workloads/
Plan:              65 to add (51 của P2 window có admin + 14 của RAG: RDS, SG, rule, 5 role, 6 policy; subnet group DB thuộc 51) — đo ngày 21/11
Plan shape sha256: <điền lúc T+0 từ plan_fingerprint.sh>
Node:              1 × m6i.large (như P3)
Ước tính:          ≈ 0,35 USD/giờ (D10, đã gồm RDS 0,019 USD/giờ và Secrets Manager) → ≈ 1,75 USD cho 5 giờ
Trần P4 (D10):     5 USD gross cho mọi window P4, tính cả retry và dọn
P4 đã tiêu:        ___ USD (Bills, owner đọc); còn lại sau window: ___ USD (phải ≥ 0)
Owner duyệt:       "Duyệt window P4-L3-YYYYMMDD-01" (gõ trong chat)
```

Chỉ apply khi đủ 6 điều:
1. Plan khớp shape hash trong request.
2. `plan_assert` (`ADMIN_WINDOW=1 P4_WINDOW=1`) và `rag_iam_check.sh tfplan` PASS.
3. Danh tính đúng.
4. Còn dưới trần.
5. Window đang mở, phiên MFA còn ≥ 40 phút.
6. Owner đã gõ câu duyệt.

## B. Điều kiện dừng

Áp dụng S1–S7 của P2 và P1–P5 của P3 (P3 C4). Thêm cho P4:

| # | Tình huống | Làm gì |
|---|---|---|
| R1 | RDS chưa `available` 20 phút sau khi tạo | Dọn (destroy). Ghi lỗi. |
| R2 | Có tài nguyên ngoài tên đã duyệt (bucket không `zero-drift-rag-tenant-*`, secret ngoài `zero-drift/rag/` và `rds!`, role lạ) | Dừng tạo mới, xoá tay, ghi như lỗi bảo mật |
| R3 | Object kẹt xoá quá 15 phút | Kiểm AWS, gỡ finalizer (P3 C3), ghi lại |
| R4 | `db-init` hoặc bootstrap lỗi sau 1 lần sửa | Dọn |
| R5 | Probe cho thấy một đường **lẽ ra bị chặn** lại đi được (chéo tenant, `CREATE ROLE`, master, IMDS) | Dừng mọi test, ghi là lỗi bảo mật, dọn. Không sửa trong window |
| R6 | Còn dưới 40 phút phiên trước destroy | Làm mới MFA trước (P2 F) |
| R7 | Tới giờ freeze | Chỉ export evidence và dọn |

Một lần sửa được phép (như P3 P1/P4) phải: là thay đổi Git qua PR owner merge, hoặc một lệnh
`window.sh`; ghi giờ và lý do; không nới resource IAM.

Rủi ro đã biết, kiểm lần đầu ở window này (DRF-46, DRF-51):
- **IRSA với `automountServiceAccountToken: false`.** Job và app tắt token Kubernetes; webhook
  EKS gắn token IRSA riêng. Nếu `db-init` báo `NoCredentialsError`, đó là lỗi này. Sửa 1 lần:
  PR bật `automountServiceAccountToken` cho Job/app trong RGD, ghi lại.
- **Region cho boto3 (gặp ở window 21/11).** botocore 1.44 chỉ đọc `AWS_DEFAULT_REGION`, bỏ qua
  `AWS_REGION`, và webhook EKS không thêm biến này. Vì vậy RGD và `window.sh` đặt cả hai biến.
  `NoRegionError` là dấu hiệu.
- **Security group của node có cho đi ra 5432 không.** `db-init` báo `ConnectionTimeout` là dấu hiệu.
- **Secret master `rds!…` khi xoá RDS** có bị giữ ở trạng thái chờ xoá không: inventory đếm cả secret chờ xoá.
- **`db.t4g.micro` đặt được ở cả 2 AZ** của subnet group: kiểm ở C.

## C. Chuẩn bị (T−30, chỉ đọc)

Làm P2_L3_WINDOW C (MFA `zdr-bootstrap`, `AWS_PROFILE=zdr-tf`, PATH kubectl, `inventory.sh`
phải `CLEAN`, IP trong `run.tfvars`, `run_id`/`expires_at` trong `run.tfvars` theo request,
Bills). Thêm:

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
aws rds describe-orderable-db-instance-options --engine postgres --engine-version 17.11 \
  --db-instance-class db.t4g.micro --query 'OrderableDBInstanceOptions[0].AvailabilityZones[].Name' --output text
```

**Phải thấy:** có cả `us-east-1a` và `us-east-1b`. Thiếu một AZ thì dừng (D2: đổi class cần duyệt mới).

```bash
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --query 'Quota.Value'
aws rds describe-account-attributes --query "AccountQuotas[?AccountQuotaName=='DBInstances'].[Used,Max]" --output text
```

**Phải thấy:** quota vCPU On-Demand ≥ 2 (P2: 5 vCPU, node m6i.large dùng 2); RDS `Used` = 0 và
`Max` ≥ 1. Thiếu thì dừng: xin quota là thay đổi tài khoản, cần duyệt riêng.

```bash
./scripts/inventory.sh | grep -E 'p4_|rds_|secrets|RESULT'
```

**Phải thấy:** mọi dòng `p4_*`, `rds_*`, `secrets*` bằng 0; `RESULT: CLEAN`.

Trong shell của window, đặt hai biến của request (dùng cho tag và `platform-config`):

```bash
export RUN_ID=P4-L3-YYYYMMDD-01 EXPIRES_AT=YYYY-MM-DDTHH:MM:00Z
```

Chuẩn bị sẵn 5 nhánh (mỗi nhánh 1 PR, owner merge trong window). Tạo từ `main` mới nhất:

| Nhánh | Thay đổi | Dùng ở |
|---|---|---|
| `hoang/drf-56-neg-on` | `git mv gitops/requests/disabled/rag-sandbox-no-tenant-role.yaml gitops/requests/` | G2 |
| `hoang/drf-56-neg-off` | trả file đó về `disabled/` | G2 |
| `hoang/drf-56-retry-0` | thêm `gitops/requests/tenant-b-retry.yaml` (`name: retry`, `bootstrapAttempt: 0`) | H |
| `hoang/drf-56-retry-1` | đổi file đó sang `bootstrapAttempt: 1` | H |
| `hoang/drf-56-delete` | xoá `gitops/requests/tenant-b-retry.yaml` | I |

PR tên sai (`docs--qa`) **không merge**: chỉ cần CI `static-gates` đỏ (G3).

## D. Plan, cổng kiểm, apply

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
terraform init -backend-config=backend.hcl -lockfile=readonly
./scripts/check.sh
terraform plan -var-file=run.tfvars -var bootstrap_cluster_admin=true -var enable_rag_platform=true -out=tfplan
ADMIN_WINDOW=1 P4_WINDOW=1 ./scripts/plan_assert.sh tfplan
./scripts/plan_fingerprint.sh tfplan
./scripts/rag_iam_check.sh tfplan
```

**Phải thấy:**
- `Plan: 65 to add, 0 to change, 0 to destroy` (khác thì đối chiếu từng resource trước khi đi tiếp);
- `plan_assert`: `RESULT: PASS`; dòng `INFO` cho trust (OIDC chưa có) và cho `rag-db-admin-master` là bình thường;
- shape sha256 **khớp** request (khác = S1);
- `rag_iam_check`: `RESULT: PASS`; các dòng `MASTER` là `SKIP`.

Phiên MFA còn ≥ 40 phút, owner đã duyệt:

```bash
terraform apply tfplan && rm tfplan
```

EKS khoảng 12 phút, RDS chạy song song khoảng 10–15 phút. Ghi giờ RDS `available` (R1).

## E. Nền và shared service (DRF-56 phần B)

```bash
./scripts/smoke.sh | tee smoke.out          # như P2: RESULT: PASS
./scripts/rag_iam_check.sh --principal      # trust thật + cả ma trận, kể cả MASTER
DB_ID="$(terraform output -json rag_platform | jq -r .db_identifier)"
aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].{status:DBInstanceStatus,public:PubliclyAccessible,encrypted:StorageEncrypted,engine:EngineVersion,class:DBInstanceClass,backup:BackupRetentionPeriod,deletionProtection:DeletionProtection}'
```

**Phải thấy:** `available`, `public: false`, `encrypted: true`, `17.11`, `db.t4g.micro`, `backup: 0`,
`deletionProtection: false`. "Không tới được từ ngoài" ở P4 nghĩa là: không public, nằm ở subnet DB
không có route Internet, và SG chỉ có 1 rule vào (đã khoá bằng `plan_assert`). Không thử kết nối từ
máy cá nhân (ranh giới âm 6).

Thăm dò registry (có thêm ghcr.io và ECR Public của aws-cli):

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
kubectl run zdr-registry-probe --image=public.ecr.aws/docker/library/amazonlinux:2023 \
  --restart=Never --rm -i --quiet -- bash -s < infra/terraform/scripts/registry_probe.sh
```

**Phải thấy:** mọi dòng `final=200` hoặc `206`. `403` từ host `s3.…amazonaws.com` = endpoint S3 chặn
(P3 C5): sửa 1 lần bằng PR thêm bucket layer chỉ đọc, plan, `plan_assert`, apply.

Argo CD và root app: làm P3 B2. **Phải thấy:** 8 app con (thêm `zdr-tenants`) và root `Synced/Healthy`;
2 provider `HEALTHY`; `kubectl get rgd` có `rag-sandbox` `Active`. Hai request trong `main` đã được
sync nhưng đứng ở `IN_PROGRESS … waiting for external reference "platformConfig"`: đúng, đó là cổng.

Ghi lại giờ Argo thấy revision của request (mốc 1 của H1):

```bash
kubectl -n argocd get app zdr-requests -o jsonpath='{.status.sync.revision} {.status.reconciledAt}{"\n"}'
kubectl get ragsandbox -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,CREATED:.metadata.creationTimestamp,STATE:.status.state
```

Gắn role, chạy `db-init`, kiểm nền, rồi mới mở cổng:

```bash
bash infra/p4-window/window.sh annotate
bash infra/p4-window/window.sh db-init
bash infra/p4-window/window.sh probe platform
bash infra/p4-window/window.sh platform-config
```

**Phải thấy:**
- `annotate`: 3 dòng `OK`, `status` báo `provider pod has AWS_ROLE_ARN yes`;
- `db-init`: log `"bootstrap_secret_created": true`, `"vector_version": "0.8.2"` (cũng chứng minh pull image ghcr.io qua endpoint);
- `probe platform`: `TLS on the connection ssl=True`, `pgvector 0.8.2`, `rag_bootstrap … super=False createrole=True`,
  `rag_bootstrap database grants … create_grant_option=False` (từ DRF-57),
  `bootstrap identity cannot read the master secret … AccessDenied…`, `RESULT: PASS`;
- `platform-config`: `OK … applied HH:MM:SSZ` (mốc 2 của H1).

`platform-config` từ chối chạy nếu `db-init` chưa `Complete`: nó mở đường cho request, nên phải sau database.

## F. End to end hai sandbox (DRF-56 phần C)

```bash
kubectl -n tenant-a wait ragsandbox/docs-qa --for=jsonpath='{.status.state}'=ACTIVE --timeout=600s
kubectl -n tenant-b wait ragsandbox/docs-qa --for=jsonpath='{.status.state}'=ACTIVE --timeout=600s
for t in tenant-a tenant-b; do
  kubectl -n $t get ragsandbox docs-qa -o jsonpath='{.status}' | jq -c 'del(.conditions)'
  kubectl -n $t get bucket.s3.aws.m.upbound.io,sa,deploy,svc -o custom-columns=KIND:.kind,NAME:.metadata.name,CREATED:.metadata.creationTimestamp
  kubectl -n $t get ragsandbox docs-qa -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}{"\n"}'
done
kubectl -n zdr-platform get job -l rag.zero-drift.io/sandbox=docs-qa -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp,DONE:.status.completionTime
bash infra/p4-window/window.sh probe sandbox tenant-a docs-qa
bash infra/p4-window/window.sh probe sandbox tenant-b docs-qa
```

**Phải thấy:** status có `endpoint`, `schema`, `bucket`, `secretName`, `bootstrapState Succeeded`,
`availableReplicas 1`, không giá trị secret. Thứ tự: Job → bucket → SA, Deployment, Service.
Mỗi probe `RESULT: PASS`: đọc được secret của mình, `≥ 6 seeded rows`, `nearest id 1`, `HeadBucket 200`,
`/readyz` và `/query` qua Service.

Mốc H1 (nhãn **smoke**, không phải trial chính thức): mốc 1 Argo thấy revision; mốc 2
`platform-config`; mốc 3 là mốc **muộn hơn** giữa `Ready` của instance và giờ probe sandbox PASS.
Kiểm tag bucket:

```bash
aws s3api get-bucket-tagging --bucket zero-drift-rag-tenant-a-docs-qa --query 'TagSet[].[Key,Value]' --output text
```

**Phải thấy:** `Project Owner Environment ManagedBy RunId ExpiresAt` đúng giá trị request.

**Micro-lab owner tự gõ** (đoán trước: role nào hiện ra? bucket nào đọc được?).
Pod chạy xong mới đọc log, và **mọi** dòng đi qua `sed`. Câu lỗi `AccessDenied` cũng chứa account
ID, còn `run -i` làm mất các dòng đầu (window 21/11, F5):

```bash
kubectl -n tenant-a run zdr-awscli --restart=Never --override-type=strategic \
  --image=public.ecr.aws/aws-cli/aws-cli@sha256:b0102d2269f87d8531d931c1a59e248101ace586886e6c077058d94c1c37b846 \
  --overrides='{"spec":{"serviceAccountName":"rag-docs-qa","securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"zdr-awscli","image":"public.ecr.aws/aws-cli/aws-cli@sha256:b0102d2269f87d8531d931c1a59e248101ace586886e6c077058d94c1c37b846","command":["sh","-c","aws --version; aws sts get-caller-identity --query Arn --output text; aws s3 ls s3://zero-drift-rag-tenant-a-docs-qa && echo OWN_OK; aws s3 ls s3://zero-drift-rag-tenant-b-docs-qa || echo OTHER_DENIED"],"env":[{"name":"HOME","value":"/tmp"}],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
kubectl -n tenant-a wait pod/zdr-awscli --for=jsonpath='{.status.phase}'=Succeeded --timeout=120s
kubectl -n tenant-a logs pod/zdr-awscli 2>&1 | sed -E 's/\b[0-9]{12}\b/<ACCOUNT>/g'
kubectl -n tenant-a delete pod zdr-awscli
```

**Phải thấy:** `assumed-role/zero-drift-rag-tenant-a/…`, `OWN_OK`, rồi `AccessDenied` và `OTHER_DENIED`.

## G. Test âm (DRF-56 phần D), mỗi ca tối đa 10 phút

**G1. Chéo tenant, quyền sandbox, IMDS** (probe chạy với identity của tenant đó):

```bash
bash infra/p4-window/window.sh probe cross tenant-a docs-qa tenant-b
bash infra/p4-window/window.sh probe cross tenant-b docs-qa tenant-a
```

**Phải thấy** mỗi chiều 7 dòng `PASS`, chặn đúng tầng:

| Ca | Tầng chặn | Thấy |
|---|---|---|
| đọc secret tenant kia | IAM (policy role tenant) | `AccessDeniedException` |
| đọc secret bootstrap | IAM | `AccessDeniedException` |
| `HeadBucket` bucket tenant kia | IAM (`ListBucket` chỉ prefix của mình) | `403` |
| đọc schema tenant kia | PostgreSQL (không có `USAGE`) | `SQLSTATE 42501` |
| `CREATE ROLE` | PostgreSQL (role sandbox không có `CREATEROLE`) | `42501` |
| `CREATE SCHEMA` | PostgreSQL | `42501` |
| token IMDS từ Pod | mạng node (hop limit 1) | timeout |

Ca "bootstrap không đọc được master" đã chạy ở E (`probe platform`).

**G2. Request ở namespace không có role tenant.** Ca này có hai lớp chặn. Lớp 1 là CI: job
`gitops` của `static-gates` đỏ trên PR `neg-on`, vì rule namespace có từ DRF-51. Ghi lại lớp này
trước. Lớp 2 là runtime. Muốn kiểm nó, owner phải cố ý merge dù CI đỏ. `main` không bảo vệ nhánh
nên merge được: lớp CI chỉ là cảnh báo (window 21/11, F3). Owner merge PR `neg-on`, rồi:

```bash
kubectl -n argocd annotate app zdr-requests argocd.argoproj.io/refresh=hard --overwrite
kubectl -n zdr-platform wait job/zdr-requests-docs-qa-boot-0 --for=condition=Failed --timeout=300s
kubectl -n zdr-platform logs job/zdr-requests-docs-qa-boot-0
kubectl -n zdr-requests get ragsandbox docs-qa -o wide
kubectl -n argocd get app zdr-requests -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'
aws s3api head-bucket --bucket zero-drift-rag-zdr-requests-docs-qa 2>&1 | tail -1
```

**Phải thấy:** log `invalid input: tenant 'zdr-requests' is not one of tenant-a, tenant-b`; instance
`IN_PROGRESS`; Argo `Synced`; `head-bucket` báo `Not Found` (bucket chờ Job nên không được tạo, không tốn
gì). Owner merge PR `neg-off`; instance bị prune.

**G3. Tên sai bị chặn trước merge.** Mở PR chuyển `disabled/rag-sandbox-bad-name.yaml` lên
`gitops/requests/`. **Phải thấy:** job `gitops` của `static-gates` đỏ với `breaks the sandbox name
contract`. Đóng PR, không merge. (`main` chưa bảo vệ nhánh: CI đỏ không tự chặn nút merge, nên
không merge là việc của owner.)

## H. Retry chỉ bằng Git (DRF-56 phần E)

Nguyên nhân giả lập ở phía nền tảng, như lab kind (ở đó là secret bootstrap sai): Job bootstrap
mất identity AWS.

```bash
bash infra/p4-window/window.sh bootstrap-identity off
```

Owner merge PR `retry-0`, rồi:

```bash
kubectl -n argocd annotate app zdr-requests argocd.argoproj.io/refresh=hard --overwrite
kubectl -n zdr-platform wait job/tenant-b-retry-boot-0 --for=condition=Failed --timeout=360s
kubectl -n zdr-platform logs job/tenant-b-retry-boot-0
kubectl -n tenant-b get ragsandbox retry -o jsonpath='{.status.state} {.status.bootstrapState}{"\n"}'
kubectl -n tenant-b get bucket.s3.aws.m.upbound.io,sa,deploy,svc | grep retry || echo "nothing for retry"
```

**Phải thấy:** log có `NoCredentialsError` (không role, và IMDS bị chặn nên cũng không lấy được role
node); `IN_PROGRESS Failed`; không có gì cho `retry`.

Sửa nguyên nhân. Lệnh dưới đây là thao tác phía nền tảng bằng `kubectl` (gắn lại annotation IRSA cho
ServiceAccount `rag-bootstrap`), **không** đi qua Git. Phần chỉ đi qua Git là đổi request:

```bash
bash infra/p4-window/window.sh bootstrap-identity on
```

Owner merge PR `retry-1`, rồi:

```bash
kubectl -n argocd annotate app zdr-requests argocd.argoproj.io/refresh=hard --overwrite
kubectl -n tenant-b wait ragsandbox/retry --for=jsonpath='{.status.state}'=ACTIVE --timeout=600s
kubectl -n zdr-platform logs job/tenant-b-retry-boot-1
kubectl -n zdr-platform get jobs,pods -l rag.zero-drift.io/sandbox=retry -o wide
bash infra/p4-window/window.sh probe sandbox tenant-b retry
```

**Phải thấy:** `boot-1` log `secret_created true` (lần 0 không có credential nên chưa ghi được secret);
instance `ACTIVE`; Job `boot-0` đã bị kro xoá, Pod của nó còn lại không owner; probe PASS. Không sửa
hay xoá tay object nào của request. Thay đổi tay duy nhất là `bootstrap-identity` ở phía nền tảng.

## I. Xoá một request và cleanup

Owner merge PR `delete`, rồi:

```bash
kubectl -n argocd annotate app zdr-requests argocd.argoproj.io/refresh=hard --overwrite
kubectl -n tenant-b get ragsandbox,bucket.s3.aws.m.upbound.io,sa,deploy,svc | grep retry || echo "k8s objects gone"
aws s3api head-bucket --bucket zero-drift-rag-tenant-b-retry 2>&1 | tail -1
bash infra/p4-window/window.sh cleanup tenant-b retry
aws secretsmanager describe-secret --secret-id zero-drift/rag/tenant-b/retry 2>&1 | grep -o ResourceNotFoundException
kubectl -n zdr-platform get jobs,pods -l rag.zero-drift.io/sandbox=retry
bash infra/p4-window/window.sh probe sandbox tenant-b docs-qa
```

**Phải thấy:** object Kubernetes hết; `head-bucket` `Not Found` (Crossplane xoá bucket, `forceDestroy`);
cleanup in `role_dropped, schema_dropped, secret_deleted true`; `ResourceNotFoundException`; không còn
Job hay Pod của `retry`; sandbox `tenant-b/docs-qa` vẫn `RESULT: PASS`.

## J. Teardown (từ giờ freeze, hoặc sớm hơn nếu xong)

Thứ tự: sandbox → cleanup → secret bootstrap → controller → Argo CD → destroy → inventory.

1. Xoá hai sandbox còn lại bằng app `zdr-requests` (cascade, như P3 B5), **trước** khi gỡ Crossplane
   để provider còn xoá được bucket:

   ```bash
   kubectl -n argocd patch app zdr-root --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
   kubectl -n argocd patch app zdr-requests --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
   kubectl -n argocd patch app zdr-requests --type merge -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}'
   kubectl -n argocd delete app zdr-requests --timeout=300s
   kubectl get ragsandbox -A; kubectl get managed -A          # phải: No resources found
   for t in tenant-a tenant-b; do aws s3api head-bucket --bucket zero-drift-rag-$t-docs-qa 2>&1 | tail -1; done
   bash infra/p4-window/window.sh cleanup tenant-a docs-qa
   bash infra/p4-window/window.sh cleanup tenant-b docs-qa
   ```

2. Secret bootstrap do `db-init` tạo, không role P4 nào được xoá nó; xoá bằng role Terraform:

   ```bash
   aws secretsmanager delete-secret --secret-id zero-drift/rag/platform/bootstrap --force-delete-without-recovery --query Name --output text
   ```

3. P3 B5 cho các app còn lại, ngược wave. Danh sách P4:
   `zdr-rgd zdr-kro-rbac zdr-kro zdr-tenants zdr-providerconfig zdr-providers zdr-crossplane`
   (không còn `zdr-requests`). Rồi xoá `zdr-root` và Argo CD.
4. P2 F: (tuỳ chọn) gỡ admin, rồi destroy. Plan gỡ admin và plan destroy **vẫn giữ**
   `-var enable_rag_platform=true`, nếu không plan gỡ admin sẽ xoá luôn RDS và role:

   ```bash
   cd infra/terraform
   terraform plan -destroy -var-file=run.tfvars -var enable_rag_platform=true -out=d.tfplan
   terraform apply d.tfplan && rm d.tfplan
   terraform state list | wc -l                                  # 0
   ./scripts/inventory.sh                                        # RESULT: CLEAN
   ```

**Phải thấy:** `rds_instances=0`, `rds_snapshots_*=0`, `rds_automated_backups=0`,
`p4_secrets_incl_pending=0`, `rds_managed_secrets_incl_pending=0`, `p4_buckets=0`, `p4_iam_roles=0`.
Secret master còn ở trạng thái chờ xoá là R2: ghi lại, xoá bằng `--force-delete-without-recovery`.

Ngày hôm sau: chạy lại `inventory.sh`, owner đọc Bills, ghi vào evidence (DRF-57 phần A).

## K. Evidence

`docs/evidence/p4/P4-T4.1_L3_WINDOW_<ngày>.md`, theo mẫu DRF-37: request đã duyệt, cổng trước apply,
dòng thời gian, mốc H1 smoke, output probe (đã sạch ARN/host), test âm, retry, cleanup, inventory,
chi phí, phát hiện, giới hạn. `smoke.out` và log thô **không** vào Git.

## L. Window xác nhận ngắn (DRF-57, sau review Codex)

**Vì sao cần.** Sau window `P4-L3-20261121-01`, PR #55 sửa code app, RGD và IAM theo review Codex.
Bản nghiệm thu vì thế khác bản đã chạy trên EKS. Window này kiểm đúng các thay đổi đó, và giữ lại
dòng `sts` còn thiếu của DRF-56 C. Nó **không** chạy lại G, H, I, và không cần PR nào trong lúc chạy.

| # | Kiểm gì | Bước | Phải thấy |
|---|---|---|---|
| V1 | C9 grant của bootstrap | E, `probe platform` | `rag_bootstrap database grants … connect_grant_option=True create=True create_grant_option=False` PASS |
| V2 | C6 quyền Crossplane không wildcard | F, rồi chờ thêm 5 phút | 2 bucket `SYNCED True READY True`; không event `AccessDenied` (lệnh dưới bảng) |
| V3 | C4 kiểm danh tính, image `850c77c2…` | F, `probe sandbox` ×2 | `/readyz` `ready: True`, probe 6/6 PASS. Log app không có `connected as` |
| V4 | DRF-56 C: dòng `sts` owner tự gõ | F, micro-lab | output đủ từ `aws --version`, có `assumed-role/zero-drift-rag-tenant-a/…`; owner dán nguyên văn vào chat |
| V5 | C6 xoá được, C1 kiểm lại sau Job | J bước 1 | `head-bucket` `Not Found` cho cả hai; `cleanup` không báo `reappeared` |
| V6 | Teardown | J | `65 destroyed`, state 0, `inventory.sh` `RESULT: CLEAN` |

Lệnh cho V2, chạy sau khi hai sandbox `ACTIVE` khoảng 5 phút (provider đã observe lại ít nhất một lần):

```bash
kubectl get bucket.s3.aws.m.upbound.io -A
# A failed read must stop here, not look like "no AccessDenied" (PR #56 review).
denied() { # what, kubectl args...
  local what=$1 out; shift
  if out="$(kubectl "$@" 2>&1)"; then
    grep -iE 'denied|forbidden' <<<"$out" || echo "OK    no AccessDenied in $what"
  else
    echo "STOP  cannot read $what: $(head -1 <<<"$out")"
  fi
}
denied "Bucket events" get events -A --field-selector involvedObject.kind=Bucket
denied "Bucket conditions" get bucket.s3.aws.m.upbound.io -A \
  -o jsonpath='{range .items[*]}{.metadata.name}{range .status.conditions[*]}{" "}{.message}{end}{"\n"}{end}'
```

**Phải thấy:** hai dòng `OK`. Có dòng `STOP` thì V2 chưa được tính: đọc lại cho tới khi được.

Điều kiện dừng riêng (thêm vào B):

| # | Tình huống | Làm gì |
|---|---|---|
| R8 | Bucket báo `AccessDenied` cho một action `s3:Get…` | Ghi tên action. **Không** thêm quyền trong window. Teardown, rồi sửa bằng PR có test |
| R9 | App không Ready, log có `connected as … expected …` | Đây là C4 chặn đúng hoặc sai cấu hình. Ghi log, không sửa trong window, teardown |

Window request (chép vào chat; owner điền chỗ trống):

```
WINDOW REQUEST — P4 L3 xác nhận
RunId:             P4-L3-20261122-01
Bắt đầu:           2026-11-22 HH:MM Asia/Saigon (= HH:MM UTC)
Kết thúc cứng:     bắt đầu + 2,5 giờ
Freeze-new-create: kết thúc cứng − 1 giờ
expires_at (tag):  giờ kết thúc cứng, UTC ...Z
Teardown owner:    HoangLV, có mặt suốt window
Git revision:      <commit main lúc plan>; git diff rỗng trên infra/ gitops/ workloads/
Plan:              65 to add; shape sha256 phải bằng 56963920ba954bd71979f158d02ff903e85d04e33250ec4dc10f5615bb7d17f9
                   (shape chỉ gồm địa chỉ resource; PR #55 chỉ đổi nội dung policy)
Phạm vi:           C, D, E, F, J của runbook này + V1–V6; bỏ G, H, I
Ước tính:          ≈ 0,35 USD/giờ → tối đa ≈ 0,9 USD cho 2,5 giờ; dự kiến ≈ 0,4 USD (≈ 70 phút)
Trần P4 (D10):     5 USD gross
P4 đã tiêu:        ≤ 0,55 USD (Credits 22/11, thận trọng: tính cả tài khoản vào P4); Bills gross đọc sau window này
                   còn lại sau window: ≥ 5 − 0,55 − 0,9 = 3,55 USD
Owner duyệt:       "Duyệt window P4-L3-20261122-01" (gõ trong chat)
```

Sáu điều kiện apply ở A vẫn áp dụng. Evidence: `docs/evidence/p4/P4-T4.2_L3_CONFIRM_20261122.md`.

## Tự thử (không cần AWS)

Probe chạy được trên lab kind của DRF-51 (file store, không TLS, không bucket):

```bash
# sau khi dựng lab P4_L2_KIND_LAB G0–G5 với cả hai request ACTIVE
LAB=1 bash infra/p4-window/window.sh probe platform
LAB=1 bash infra/p4-window/window.sh probe sandbox tenant-a docs-qa
LAB=1 bash infra/p4-window/window.sh probe cross tenant-a docs-qa tenant-b
```

Đoán trước: ca nào `SKIP` trên kind, ca nào PASS vì lý do khác với EKS? (Gợi ý: secret của tenant
kia "không thấy" vì PV không gắn thư mục đó, không phải vì IAM; IMDS không có trên kind.)

## Undo

- Chưa apply: không có gì để hoàn tác; xoá các nhánh PR chuẩn bị.
- Đã apply: phần J chính là undo. `window.sh` chỉ tạo object window (annotation, ConfigMap, Job,
  Pod probe); chúng đi cùng cluster.
- Bỏ công cụ: `git rm -r infra/p4-window`.

## Giới hạn

- `window.sh` và `probe.py` mới chỉ chạy trên kind (`LAB=1`): phần AWS (IRSA, Secrets Manager, S3,
  TLS, IMDS) chỉ được kiểm lần đầu trong window.
- Digest image aws-cli đọc từ registry 21/11; phiên bản CLI xem ở dòng `aws --version` của micro-lab.
- `main` chưa bảo vệ nhánh: CI đỏ không tự chặn merge (G3).
