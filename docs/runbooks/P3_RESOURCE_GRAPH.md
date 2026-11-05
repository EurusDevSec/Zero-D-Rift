# P3 — Resource graph trên EKS: IRSA, GitOps, window, dọn

Runbook của P3 (SPEC-P3). Mỗi task thêm phần của mình:

| Phần | Task | Trạng thái |
|---|---|---|
| A. IRSA role cho provider (Terraform) | DRF-36 (T4) | Viết 05/11, phần không cần AWS đã chạy |
| B. GitOps: Argo CD sync `gitops/platform` và `gitops/requests` | DRF-35 (T3) | Viết 05/11; đã tập trên kind (không AWS), trừ root app |
| C. Window L3: tạo, kiểm, test âm, test xóa, dọn | DRF-37 (T5) | Viết 05/11; chưa chạy, cần owner duyệt window |

Runbook nền:
- [P2_L3_WINDOW](P2_L3_WINDOW.md): MFA, IP, plan, apply, admin, destroy, inventory;
- [P3_L2_KIND_LAB](P3_L2_KIND_LAB.md): làm quen với Argo CD, Crossplane và kro trên kind, không AWS.

---

## A. IRSA role cho Crossplane provider (DRF-36)

### Ý tưởng trong 4 dòng

```
Pod provider-aws-s3 ── token OIDC do EKS ký (sub = system:serviceaccount:crossplane-system:provider-aws-s3)
        │
        ▼  sts:AssumeRoleWithWebIdentity (role chỉ tin đúng sub + aud này)
IAM role zero-drift-p3-crossplane-s3 ── chỉ s3:CreateBucket/DeleteBucket/PutBucketTagging/Get*/List*
                                       trên arn:aws:s3:::zero-drift-p3-*  (không object, không IAM)
```

Terraform sở hữu role này (ADR-0003). Bucket thuộc Crossplane. Role chỉ được tạo khi bật `enable_p3_provider_role = true`. Giá trị mặc định là `false`, nên plan của P2 không đổi.

Code:
- `infra/terraform/modules/p3-provider-irsa/`;
- lời gọi module ở cuối `infra/terraform/main.tf`;
- test: `infra/terraform/tests/p3_irsa.tftest.hcl`;
- kiểm plan: `scripts/plan_assert.sh` (check 13);
- mô phỏng IAM: `scripts/p3_iam_check.sh`.

### A0. Kiểm tĩnh, không cần AWS (làm bất cứ lúc nào)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
terraform init -backend=false -lockfile=readonly    # lần đầu, hoặc khi thêm module
./scripts/check.sh
```

**Phải thấy:** `RESULT: PASS`. Dòng `terraform test` pass, gồm 4 test P3:
- mặc định không có role;
- khi bật, trust đúng 1 subject;
- role sai tiền tố bị từ chối;
- prefix bucket `*` bị từ chối.

Muốn xem từng test:

```bash
terraform test
```

**Phải thấy:** `20 passed, 0 failed`.

**Tự thử:**
1. Mở `modules/p3-provider-irsa/main.tf`, đổi dòng `Resource = ["arn:aws:s3:::${var.bucket_prefix}*"]` thành `Resource = ["*"]`, rồi chạy `terraform test`.
2. **Phải thấy:** `Permissions must apply only to arn:aws:s3:::zero-drift-p3-*` và `1 failed`.
3. Trả lại như cũ: `git checkout modules/p3-provider-irsa/main.tf`.

### A1. Plan cho window P3 (cần phiên MFA; chỉ đọc AWS)

Làm theo P2_L3_WINDOW các bước: MFA, IP, `run.tfvars`, `init` với backend. Sau đó **thêm** cờ P3:

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
export AWS_PROFILE=zdr-tf AWS_REGION=us-east-1
terraform plan -var-file=run.tfvars -var bootstrap_cluster_admin=true -var enable_p3_provider_role=true -out=tfplan
ADMIN_WINDOW=1 P3_WINDOW=1 ./scripts/plan_assert.sh tfplan
./scripts/plan_fingerprint.sh tfplan
./scripts/p3_iam_check.sh tfplan
```

**Phải thấy:**
- `plan_assert`: `RESULT: PASS`, có 3 dòng `P3 role …` PASS. Số resource là 53: 50 của P2, cộng 1 admin association, 1 role P3 và 1 inline policy.
- `plan_fingerprint`: ghi lại shape hash cho window request.
- `p3_iam_check`: Access Analyzer không có ERROR hay SECURITY_WARNING. Các hành động trên bucket `zero-drift-p3-*` ra `allowed`; mọi thứ khác ra `implicitDeny` (bucket ngoài prefix, object, PutBucketPolicy, ListAllMyBuckets, IAM, AssumeRole).

**Nếu sai:**
- Quên `P3_WINDOW=1`: check 13 báo `inline role polic(ies) planned without P3_WINDOW=1`. Đó là cố ý, để không ai vô tình tạo role P3.
- Quên `-var enable_p3_provider_role=true`: `p3_iam_check` báo `no aws_iam_role_policy in the plan`.

### A2. Sau khi apply trong window

```bash
./scripts/p3_iam_check.sh --principal
aws iam get-role --role-name zero-drift-p3-crossplane-s3 --query 'Role.RoleName' --output text
# ARN chỉ để đưa vào cluster, KHÔNG echo, KHÔNG ghi vào evidence/Git (chứa account ID):
ROLE_ARN="$(aws iam get-role --role-name zero-drift-p3-crossplane-s3 --query 'Role.Arn' --output text)"
```

`ROLE_ARN` được dùng ở phần B: gắn vào ServiceAccount `provider-aws-s3` qua DeploymentRuntimeConfig.

**Phải thấy:** `p3_iam_check --principal` trả `RESULT: PASS`, và `get-role` in đúng tên role.

### A3. Gỡ admin nhưng GIỮ role P3

Trong P2, bước gỡ admin là plan lại **không** truyền `-var bootstrap_cluster_admin=true`. Sang P3 thì **phải vẫn giữ** `-var enable_p3_provider_role=true` cho tới khi bucket P3 đã hết:

```bash
terraform plan -var-file=run.tfvars -var enable_p3_provider_role=true -out=tfplan
terraform show -no-color tfplan | grep -E '^Plan:|will be destroyed'
```

**Phải thấy:** `Plan: 0 to add, 0 to change, 1 to destroy`, và resource bị destroy là association admin.

Nếu quên cờ này, plan sẽ xóa luôn role. Khi đó provider mất quyền, không xóa được bucket thật, và MR bị kẹt ở bước xóa.

### A4. Undo

- **Chỉ gỡ role** (cluster vẫn còn, và bucket P3 đã hết): plan và apply **không** có `-var enable_p3_provider_role=true`. Plan phải chỉ có 2 delete: `aws_iam_role_policy` và `aws_iam_role` của module `p3_provider_irsa`.
- **Gỡ hết:** dùng `terraform destroy` như P2. Role đi cùng destroy.
- **Kiểm sau cùng:**

  ```bash
  aws iam get-role --role-name zero-drift-p3-crossplane-s3 2>&1 | grep -c NoSuchEntity
  ```

  Kết quả phải là `1`.

### Giới hạn của phần A

- Role P3 nằm ngoài phạm vi policy R1 (`infra/iam/zero-drift-terraform-policy.json` chỉ cho phép role `zero-drift-cluster-*` và `zero-drift-system-node-*`, và không có `iam:PutRolePolicy`). Hiện tại Terraform dùng AdministratorAccess (R1 hoãn tới DRF-27/29), nên window không bị chặn. Khi làm lại R1 thì phải thêm role `zero-drift-p3-*` và `PutRolePolicy`/`GetRolePolicy`.
- `s3:Get*` và `s3:List*` là wildcard ở **action**, không phải ở resource: provider đọc rất nhiều thuộc tính con của bucket mỗi lần refresh. Resource chỉ gồm ARN bucket có prefix, nên các action trên object không bao giờ khớp.

---

## B. GitOps: Argo CD dựng control plane từ Git (DRF-35)

### Bố cục

```
gitops/bootstrap/root-app.yaml     ← áp tay 1 lần (app of apps)
gitops/platform/apps/              ← các Application, chạy theo sync-wave
  00-crossplane   (Helm 2.4.3, image @sha256)        wave 0
  10-providers    (family + s3 @sha256, DRC)         wave 1
  20-providerconfig (ClusterProviderConfig IRSA)     wave 2
  30-kro          (Helm OCI 0.9.4, aggregation)      wave 3
  35-kro-rbac     (ClusterRole aggregate)            wave 3
  40-rgd          (StorageAppSpike)                  wave 4
  90-requests     (gitops/requests, PRUNE)           wave 9
gitops/requests/storage-app-spike-valid.yaml        ← bucket zero-drift-p3-spike-…
gitops/requests/disabled/…-negative.yaml            ← KHÔNG sync (app không recurse)
```

Chính sách sync:
- App platform: `selfHeal: true`, `prune: false`. Đổi Git **không bao giờ** gỡ controller.
- App requests: `prune` + `selfHeal` + `allowEmpty`. Xóa file trong Git thì instance, rồi bucket, bị xóa theo.

### B0. Kiểm tĩnh (không cần cluster)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
./gitops/check.sh
```

**Phải thấy:** `RESULT: PASS`, gồm:
- 28 dòng PASS;
- không có Secret, không có account ID;
- mọi image và package đều có `@sha256`;
- provider đúng allowlist;
- chart pin đúng version;
- chính sách sync đúng;
- bucket nằm trong prefix;
- RGD có `readyWhen`.

### B1. Tập trên kind trước (không AWS, khoảng 15 phút)

Làm bước 0–2 của [P3_L2_KIND_LAB](P3_L2_KIND_LAB.md): tạo cluster và cài Argo CD. **Không** cài Crossplane hay kro bằng tay; Argo sẽ cài. Sau đó:

```bash
REV=main      # hoặc tên nhánh đang sửa
for f in gitops/platform/apps/*.yaml; do sed "s|targetRevision: main|targetRevision: $REV|" "$f" | kubectl apply -f -; done
kubectl -n argocd get app -w            # đợi 7 app Synced  Healthy (khoảng 2–4 phút)
kubectl get rgd                         # storage-app-spike  Active
kubectl -n zdr-requests get storageappspike,deploy,bucket.s3.aws.m.upbound.io
```

**Phải thấy:**
- 7 app `Synced Healthy`;
- instance `spike` ở `IN_PROGRESS`;
- Bucket `SYNCED=False … IAM Roles for Service Accounts …`: kind không có IRSA;
- **chưa có Deployment**, vì Deployment phụ thuộc vào bucket nên kro chờ bucket trước.

Đây là Synced ≠ Ready: Argo báo xanh hết, nhưng request chưa xong.

> Ở đây áp từng app con, **không** dùng root app, vì `sed` chỉ đổi được revision của file trên máy. Root app đọc file app con từ Git, mà trong Git chúng trỏ `main`.

**Tự thử:**
1. Trong `gitops/platform/rgd/storage-app-spike.yaml`, đổi readyWhen của `app` thành `== schema.spec.replicas`, push lên nhánh, rồi refresh:

   ```bash
   kubectl -n argocd annotate app zdr-rgd argocd.argoproj.io/refresh=hard --overwrite
   ```

   **Phải thấy:** `kubectl get rgd` báo `Inactive … references unknown identifiers: [schema]`, trong khi Argo vẫn báo `zdr-rgd` Synced/Healthy.
2. Chạy `kubectl explain storageappspike.spec`: đây là API mới mà kro vừa sinh ra.

Dọn: `kind delete cluster --name zdr-p3-lab`.

### B2. Trong window: cài Argo CD và bật root app (cần kubeconfig EKS và admin trong window)

Cài Argo CD giống bước 2 của P3_L2_KIND_LAB (kiểm sha256, apply `--server-side`). Sau đó:

```bash
kubectl apply -f gitops/bootstrap/root-app.yaml
kubectl -n argocd get app -w          # 8 app (root + 7) → Synced Healthy
kubectl get providers.pkg.crossplane.io
kubectl -n crossplane-system get sa provider-aws-s3
```

### B3. Gắn IRSA cho provider (ROLE_ARN lấy ở A2, không echo)

```bash
kubectl patch deploymentruntimeconfig provider-aws-s3 --type merge \
  -p "{\"spec\":{\"serviceAccountTemplate\":{\"metadata\":{\"annotations\":{\"eks.amazonaws.com/role-arn\":\"$ROLE_ARN\"}}}}}"
unset ROLE_ARN
# Pod phải tạo lại thì webhook EKS mới gắn token IRSA:
kubectl -n crossplane-system delete $(kubectl -n crossplane-system get pods -o name | grep provider-aws-s3)
kubectl -n crossplane-system get pods -o json | jq '[.items[] | select(.metadata.name | startswith("provider-aws-s3")) | .spec.containers[0].env[]?.name] | index("AWS_ROLE_ARN") != null'
kubectl -n argocd get app zdr-providers     # vẫn Synced: Argo bỏ qua annotation này
```

**Phải thấy:** jq in `true`, và `zdr-providers` vẫn `Synced`.

Trên kind đã kiểm (với ARN giả có account `000000000000`):
- SA nhận annotation sau khoảng 5 giây;
- ép sync lại thì annotation vẫn còn;
- app vẫn Synced.

### B4. Test âm và test xóa: đổi qua Git (PR, rồi owner merge)

| Test | Thay đổi trong Git | Phải thấy |
|---|---|---|
| Âm | `git mv gitops/requests/disabled/storage-app-spike-negative.yaml gitops/requests/` | Trong tối đa 10 phút: Bucket báo `AccessDenied`, instance không Ready, Argo vẫn Synced. Sau đó `git mv` trả file về `disabled/` |
| Xóa | `git rm gitops/requests/storage-app-spike-valid.yaml` | Argo prune instance, kro xóa Deployment và Bucket MR, Crossplane xóa bucket AWS (policy mặc định `*`). Kiểm: `aws s3api head-bucket --bucket zero-drift-p3-spike-d4163e` phải báo `404`/`Not Found` |

Đã tập prune trên kind bằng một nhánh tạm không có file valid:
- instance mất sau khoảng 5 giây;
- Bucket MR mất, không bị kẹt finalizer;
- app vẫn `Synced/Healthy` dù thư mục rỗng (`allowEmpty`).

Bucket trong lần tập đó **chưa từng được tạo trên AWS**, nên đường xóa bucket thật chỉ được chứng minh ở L3.

### B5. Teardown platform (theo thứ tự)

Điều kiện trước: không còn instance, không còn MR, và `head-bucket` báo không còn bucket P3 nào.

```bash
kubectl get managed -A                          # phải: No resources found
# 1. Dừng ROOT trước: nếu không, selfHeal của root sẽ trả "automated" lại cho app con
kubectl -n argocd patch app zdr-root --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
# 2. App con, ngược thứ tự wave: dừng sync, gắn finalizer cascade, xóa
for a in zdr-requests zdr-rgd zdr-kro-rbac zdr-kro zdr-providerconfig zdr-providers zdr-crossplane; do
  kubectl -n argocd patch app $a --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
  kubectl -n argocd patch app $a --type merge -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}'
  kubectl -n argocd delete app $a --timeout=180s
done
kubectl -n argocd delete app zdr-root
kubectl get providers.pkg.crossplane.io; kubectl get pods -A | grep -E 'crossplane|provider|kro'   # không còn gì
```

Sau đó xóa Argo CD (`kubectl delete -n argocd -f <manifest đã pin>`), gỡ admin, rồi `terraform destroy` (P2_L3_WINDOW).

Đã tập trên kind (bỏ bước root):
- 7 app bị xóa trong khoảng 30 giây; provider mất khoảng 20 giây;
- không còn pod controller;
- **còn 24 CRD** (21 core Crossplane, 3 kro), vì Helm không xóa CRD. Trên EKS, các CRD này đi cùng `terraform destroy`.

### B6. Undo

- Bỏ một request: xóa file trong `gitops/requests/` qua PR. App requests sẽ prune.
- Bỏ cả platform: làm B5.
- Bỏ phần IRSA: gỡ annotation khỏi DRC bằng `kubectl patch … --type json -p '[{"op":"remove","path":"/spec/serviceAccountTemplate/metadata/annotations"}]'`, rồi xóa pod provider.

---

## C. Window L3 trên EKS (DRF-37)

Chỉ chạy khi đủ 4 điều:
- PR #22 và #23 **đã merge** (root app đọc `main`);
- DRF-39 PASS;
- owner đã gõ duyệt đúng window request bên dưới;
- phiên MFA mới.

Các bước P2 dùng lại nguyên từ [P2_L3_WINDOW](P2_L3_WINDOW.md): C (chuẩn bị), D (plan/apply), E (smoke/inventory), F (gỡ admin/destroy). Phần này chỉ ghi **chỗ khác** và các bước P3.

### C0. Window request (owner điền chỗ trống rồi duyệt)

```
WINDOW REQUEST — P3 L3
RunId:            P3-L3-20261105-01
Bắt đầu:          23:15 05/11 Asia/Saigon (= 16:15Z)  (đề xuất; dời thì sửa cả expires_at)
Kết thúc cứng:    03:15 06/11 Asia/Saigon (= 20:15Z), bắt đầu + 4 giờ
Freeze-new-create: 01:45 06/11 (= 18:45Z), kết thúc cứng − 1,5 giờ (dọn P3 ≈ 10 phút Argo + 15 phút destroy + inventory)
expires_at (tag): 2026-11-05T20:15:00Z (cũng là tag ExpiresAt của bucket trong gitops/requests)
Teardown owner:   HoangLV, có mặt suốt window; không rời máy khi cluster còn chạy (S7)
Git revision:     <commit main sau khi merge #23>
Plan:             53 to add (50 P2 + admin + role P3 + inline policy)
Plan shape sha256: ________ (Claude điền sau bước A1, trước khi xin duyệt)
Node:             1 × m6i.large (D7, đo ở DRF-39)
Ước tính:         ≈ 0.21 USD/giờ (EKS 0.10 + m6i.large 0.096 + EBS/IPv4/log) → ≈ 0.85 USD cho 4 giờ
Trần P3 (D8):     3 USD gross, tính cả retry, dọn, S3, log
P3 đã tiêu:       0 USD; P2 thực tế ≈ 0.07 USD
Owner duyệt:      "Duyệt window P3-L3-20261105-01" (gõ trong chat)
```

### C1. Trình tự (giờ là phút tính từ lúc bắt đầu)

| Phút | Bước | Lệnh / nơi | Phải thấy |
|---|---|---|---|
| −30 | Chuẩn bị chỉ đọc | P2_L3_WINDOW C: `inventory.sh` (có thêm `p3_iam_roles`), kiểm IP, sửa `run_id`/`expires_at` trong `run.tfvars` | `RESULT: CLEAN`; IP khớp |
| 0 | Plan + cổng kiểm | Runbook A1 (`-var bootstrap_cluster_admin=true -var enable_p3_provider_role=true`) | 53 to add; `plan_assert` PASS; shape hash **khớp** request; `p3_iam_check` PASS |
| 0 | Apply | `terraform apply tfplan` (phiên MFA còn ≥ 40 phút) | Apply complete, khoảng 15–20 phút |
| +20 | Smoke P2 | `./scripts/smoke.sh` | `RESULT: PASS` |
| +25 | Role P3 sống | Runbook A2 (`p3_iam_check --principal`, lấy `ROLE_ARN`) | PASS |
| +30 | Argo CD + root app | Runbook B2 | 8 app Synced/Healthy; 2 provider HEALTHY |
| +40 | IRSA | Runbook B3 | Pod provider có `AWS_ROLE_ARN` |
| +45 | Instance hợp lệ | Xem dưới (C2) | Instance `ACTIVE/Ready`; bucket có thật, đủ tag; Deployment 1/1 |
| +60 | Test âm (≤ 10 phút) | Owner merge PR "neg-on" | Bucket `AccessDenied`, instance không Ready, Argo `Synced` |
| +75 | Tắt âm + test xóa | Owner merge PR "neg-off + delete" | Instance và MR mất; `head-bucket` → 404 |
| freeze | Teardown platform | Runbook B5 (root trước) | Không còn controller |
| freeze | Gỡ admin, destroy | P2_L3_WINDOW F (plan gỡ admin vẫn giữ `-var enable_p3_provider_role=true`, xem A3) | `state list` = 0; `inventory.sh` CLEAN, `p3_iam_roles=0`, `s3_buckets=1` |

### C2. Lệnh kiểm instance hợp lệ (+45)

```bash
kubectl -n zdr-requests get storageappspike,deploy,bucket.s3.aws.m.upbound.io
kubectl -n zdr-requests get storageappspike spike -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
aws s3api head-bucket --bucket zero-drift-p3-spike-d4163e && echo "bucket exists"
aws s3api get-bucket-tagging --bucket zero-drift-p3-spike-d4163e --query 'TagSet[].Key' --output text
```

**Phải thấy:**
- `READY=True`;
- `bucket exists`;
- có đủ các tag `Project Owner Environment ManagedBy RunId ExpiresAt` (cộng tag `crossplane-*`).

Ghi giờ tạo bucket và giờ instance Ready.

### C3. Test âm và test xóa: 2 PR đã chuẩn bị sẵn

| PR | Nhánh | Thay đổi |
|---|---|---|
| neg-on | `hoang/drf-37-neg-on` | Chuyển `disabled/storage-app-spike-negative.yaml` lên `gitops/requests/` |
| neg-off + xóa | `hoang/drf-37-neg-off-delete` | Xóa cả 2 file instance khỏi `gitops/requests/` (bản âm trả về `disabled/`) |

Sau khi owner merge, ép Argo đọc lại Git ngay thay vì đợi 3 phút:

```bash
kubectl -n argocd annotate app zdr-requests argocd.argoproj.io/refresh=hard --overwrite
```

**Test âm:**

```bash
kubectl -n zdr-requests get bucket.s3.aws.m.upbound.io zdr-outside-p3-d4163e -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
```

**Phải thấy:** message có `AccessDenied`, và `aws s3api head-bucket --bucket zdr-outside-p3-d4163e` báo lỗi (403 hoặc 404, **không** được thành công).

Nếu sau khi xóa mà MR âm kẹt ở finalizer quá 5 phút:
1. Kiểm bằng `head-bucket` rằng bucket không tồn tại.
2. Gỡ finalizer bằng tay:

   ```bash
   kubectl -n zdr-requests patch bucket.s3.aws.m.upbound.io zdr-outside-p3-d4163e --type merge -p '{"metadata":{"finalizers":[]}}'
   ```

3. Ghi lại làm evidence (SPEC Task 5).

### C4. Điều kiện dừng thêm cho P3 (cộng với S1–S7 của P2)

| # | Tình huống | Làm gì |
|---|---|---|
| P1 | Controller hoặc ProviderRevision không healthy sau 1 lần sửa | Dọn (B5 rồi destroy) |
| P2 | Có bucket được tạo ngoài prefix `zero-drift-p3-` | Dừng ngay; xóa bucket bằng tay; ghi lại như lỗi bảo mật |
| P3 | MR kẹt ở bước xóa quá 15 phút | Kiểm AWS, gỡ finalizer theo C3, ghi lại |
| P4 | `AccessDenied` trên bucket **trong** prefix | Lỗi policy: sửa đúng 1 lần (thêm action, không nới resource), plan lại, `plan_assert`, apply |
| P5 | Phiên MFA còn < 40 phút trước destroy | Làm mới MFA trước |

### C5. Undo

Không có bước undo riêng. Trình tự dọn ở cuối bảng C1 chính là undo:
- teardown platform B5;
- destroy;
- inventory CLEAN với `p3_iam_roles=0` và `s3_buckets=1`.

Ngày hôm sau: chạy lại inventory và xem Bills (như DRF-12).
