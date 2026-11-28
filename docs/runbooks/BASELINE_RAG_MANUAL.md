# Baseline RAGSandbox thủ công (EXPERIMENT_PLAN §5.2, SPEC-P7 T4, D8)

> Trạng thái: **PLAN**. Viết 28/11, chưa chạy lần nào. Lần chạy đầu là dry run trong window 29/11 (`official=false`).
> Người chạy: **bạn** (owner). Claude chỉ ghi phiếu đếm thao tác ([BASELINE_INTERACTION_SHEET.md](BASELINE_INTERACTION_SHEET.md)).

So sánh dễ nhớ: nền tảng là **gọi món qua app**. Bạn viết một file `RAGSandbox` (PR), rồi kro và Crossplane lần lượt
làm hết: Job tạo schema/role/secret, bucket, ServiceAccount, Deployment, Service. Baseline là **tự nấu đúng món đó**,
từng bước bằng tay, cùng nguyên liệu (D8):
- cùng database chung;
- cùng role tenant tạo sẵn;
- cùng image;
- cùng probe kiểm tra.

So sánh này là về **số bước và thời gian**, không phải về quyền.

## Khác biệt cần bạn quyết (D8a, đề xuất 28/11)

D8 ghi "SQL by hand with the bootstrap tier from a platform Pod". Nhưng image `rag-sandbox` **không có `psql`**, và
gõ SQL tạo role bằng tay buộc phải gõ mật khẩu ra màn hình. Claude đề xuất cách khác: bạn chạy **chính lệnh
`bootstrap` của image một lần bằng tay** (một Job trong `zdr-platform`, SA `rag-bootstrap`). Lần chạy đó tính là
**1 interaction**, kèm `automated_actions_count = 8`:
- tạo secret: 1;
- tạo role: 1;
- grant/revoke trên schema: 6.

Điều này đúng luật §5.1 ("một script chạy một lần là một interaction, nhưng phải ghi `automated_actions_count`").
**Chưa áp dụng cho tới khi bạn duyệt**; nếu không duyệt thì phải thêm `psql` vào một image riêng (ngoài P7).

## Luật chơi

- **Mốc bắt đầu:** lúc bạn gõ lệnh đầu tiên của bước 1. **Mốc kết thúc:** lúc probe báo `RESULT: PASS` (readiness và DB
  query đều đạt). Quá `manual_rag_timeout_seconds = 5400` là run failed.
- Đếm thao tác theo §5.1, giống phiếu của đường nền tảng (PR, merge, retry đều được đếm).
- Không in ARN, host RDS, mật khẩu hay endpoint. Các giá trị lấy từ `platform-config` và chỉ giữ trong biến shell.

## 0. Biến

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift && export AWS_PROFILE=zdr-tf AWS_REGION=us-east-1 T=tenant-a N=manual-qa; RUN=BL-RAG-$(date -u +%Y%m%dT%H%M%SZ); B=zero-drift-rag-$T-$N; echo "$RUN $B"
```

```bash
cfg(){ kubectl -n zdr-platform get cm platform-config -o jsonpath="{.data.$1}"; }; DBH=$(cfg dbHost); DBP=$(cfg dbPort); RID=$(cfg runId); EXP=$(cfg expiresAt); ROLEP=$(cfg tenantRoleArnPrefix); [[ -n "$DBH$DBP$RID$EXP$ROLEP" ]] && echo "platform-config OK"
```

## 1. Preflight (mốc bắt đầu)

```bash
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo "T0=$T0"; aws s3api head-bucket --bucket "$B" 2>&1 | grep -oE '404|Not Found|403' | head -1; aws secretsmanager describe-secret --secret-id "zero-drift/rag/$T/$N" 2>&1 | grep -oE 'ResourceNotFoundException' | head -1; kubectl -n $T get deploy,sa,svc rag-$N --no-headers 2>&1 | grep -c NotFound
```

**Phải thấy:** `404`, `ResourceNotFoundException` và `3` (chưa có gì của sandbox này). Nếu đã có thì dọn trước (bước 8).

## 2. Nền tenant (dùng chung với đường nền tảng, chỉ kiểm, không tạo)

Namespace, quota, RBAC, NetworkPolicy và Kyverno là phần **onboarding tenant** của nền tảng (P5). Một `RAGSandbox`
request không tạo chúng, nên baseline cũng không tạo (D8). Bước này là 1 interaction:

```bash
kubectl get ns $T -o name; kubectl -n $T get resourcequota,limitrange,networkpolicy,rolebinding --no-headers | wc -l; kubectl get clusterpolicy --no-headers | wc -l
```

## 3. Bucket S3 trong prefix của tenant

```bash
aws s3api create-bucket --bucket "$B" >/dev/null && aws s3api put-bucket-tagging --bucket "$B" --tagging "TagSet=[{Key=Project,Value=Zero-D-Rift},{Key=Owner,Value=HoangLV},{Key=Environment,Value=PoC},{Key=ManagedBy,Value=Manual},{Key=RunId,Value=$RID},{Key=ExpiresAt,Value=$EXP}]" && echo "bucket OK $(date -u +%T)Z"
```

## 4. Schema, role và secret trên RDS chung (D8a)

```bash
cat <<EOF | kubectl apply -f - >/dev/null && echo "bootstrap Job created $(date -u +%T)Z"
apiVersion: batch/v1
kind: Job
metadata: {name: $T-$N-boot-manual, namespace: zdr-platform, labels: {app.kubernetes.io/name: ragsandbox, app.kubernetes.io/component: bootstrap, zero-drift.io/role: baseline}}
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 300
  template:
    metadata: {labels: {app.kubernetes.io/name: ragsandbox, app.kubernetes.io/component: bootstrap, rag.zero-drift.io/tenant: $T, rag.zero-drift.io/sandbox: $N}}
    spec:
      restartPolicy: Never
      serviceAccountName: rag-bootstrap
      automountServiceAccountToken: false
      securityContext: {runAsNonRoot: true, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: bootstrap
          image: ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox@sha256:850c77c200a798b5706ce56c7878164d4887fcf3661bbec91b2d8564df735263
          args: ["bootstrap"]
          env:
            - {name: SANDBOX_TENANT, value: "$T"}
            - {name: SANDBOX_NAME, value: "$N"}
            - {name: SECRET_BACKEND, value: aws}
            - {name: AWS_REGION, value: "$AWS_REGION"}
            - {name: AWS_DEFAULT_REGION, value: "$AWS_REGION"}
            - {name: DB_HOST, value: "$DBH"}
            - {name: DB_PORT, value: "$DBP"}
            - {name: DB_SSLMODE, value: verify-full}
            - {name: SECRET_TAGS, value: "Project=Zero-D-Rift,Owner=HoangLV,Environment=PoC,ManagedBy=Manual,RunId=$RID,ExpiresAt=$EXP"}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 50m, memory: 96Mi}, limits: {memory: 192Mi}}
EOF
```

```bash
kubectl -n zdr-platform wait job/$T-$N-boot-manual --for=condition=complete --timeout=300s && kubectl -n zdr-platform logs job/$T-$N-boot-manual | tail -1 | grep -oE '"(schema|role)": "[^"]*"'
```

**Phải thấy:** `schema rag_tenant_a__manual_qa`, `role rag_tenant_a__manual_qa`. Dòng log không chứa secret.

## 5. ServiceAccount, Deployment, Service

Cùng spec với graph `rag-sandbox` (role của tenant đã tạo sẵn và tin `system:serviceaccount:<tenant>:rag-*`):

```bash
cat <<EOF | kubectl apply -f - >/dev/null && echo "app objects created $(date -u +%T)Z"
apiVersion: v1
kind: ServiceAccount
metadata: {name: rag-$N, namespace: $T, annotations: {eks.amazonaws.com/role-arn: "$ROLEP$T"}}
automountServiceAccountToken: false
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: rag-$N, namespace: $T, labels: {app.kubernetes.io/name: ragsandbox, app.kubernetes.io/component: app, rag.zero-drift.io/sandbox: $N}}
spec:
  replicas: 1
  selector: {matchLabels: {app.kubernetes.io/name: ragsandbox, rag.zero-drift.io/sandbox: $N}}
  template:
    metadata: {labels: {app.kubernetes.io/name: ragsandbox, app.kubernetes.io/component: app, rag.zero-drift.io/sandbox: $N, rag.zero-drift.io/tenant: $T}}
    spec:
      serviceAccountName: rag-$N
      automountServiceAccountToken: false
      securityContext: {runAsNonRoot: true, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: app
          image: ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox@sha256:850c77c200a798b5706ce56c7878164d4887fcf3661bbec91b2d8564df735263
          args: ["serve"]
          ports: [{name: http, containerPort: 8080}]
          env:
            - {name: DB_SECRET_ID, value: "zero-drift/rag/$T/$N"}
            - {name: SANDBOX_TENANT, value: "$T"}
            - {name: SANDBOX_NAME, value: "$N"}
            - {name: S3_BUCKET, value: "$B"}
            - {name: SECRET_BACKEND, value: aws}
            - {name: AWS_REGION, value: "$AWS_REGION"}
            - {name: AWS_DEFAULT_REGION, value: "$AWS_REGION"}
            - {name: DB_HOST, value: "$DBH"}
            - {name: DB_PORT, value: "$DBP"}
            - {name: DB_SSLMODE, value: verify-full}
          readinessProbe: {httpGet: {path: /readyz, port: http}, periodSeconds: 10, timeoutSeconds: 8, failureThreshold: 3}
          livenessProbe: {httpGet: {path: /healthz, port: http}, periodSeconds: 20, timeoutSeconds: 3}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 50m, memory: 96Mi}, limits: {memory: 192Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: rag-$N, namespace: $T, labels: {app.kubernetes.io/name: ragsandbox}}
spec:
  selector: {app.kubernetes.io/name: ragsandbox, rag.zero-drift.io/sandbox: $N, rag.zero-drift.io/tenant: $T}
  ports: [{name: http, port: 8080, targetPort: http}]
EOF
```

## 6. Readiness và kiểm DB độc lập (mốc kết thúc)

```bash
kubectl -n $T rollout status deploy/rag-$N --timeout=600s && bash infra/p4-window/window.sh probe sandbox $T $N; TEND=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo "TEND=$TEND"
```

**Phải thấy:** `RESULT: PASS` với cùng 6 kiểm tra như đường nền tảng:
- đọc được secret của mình;
- `≥ 6 seeded rows`;
- `nearest id 1`;
- `HeadBucket 200`;
- `/readyz` qua Service;
- `/query` qua Service.

Cycle time của baseline = `TEND − T0`.

## 7. Ghi lại

Ghi vào phiếu:
- số interactions, số commands, thời gian chờ, lỗi và cách sửa;
- `automated_actions_count`: 8 ở bước 4 (D8a), 3 object ở bước 5;
- T0 và TEND.

## 8. Dọn (theo allowlist của sandbox)

Lệnh `window.sh cleanup` chỉ chạy khi không có `RAGSandbox` tên này, và ở đây không có (đây là sandbox tạo tay):

```bash
kubectl -n $T delete deploy,svc,sa rag-$N --ignore-not-found && kubectl -n zdr-platform delete job $T-$N-boot-manual --ignore-not-found && bash infra/p4-window/window.sh cleanup $T $N
```

```bash
aws s3 rm "s3://$B" --recursive --quiet; aws s3api delete-bucket --bucket "$B" && aws s3api head-bucket --bucket "$B" 2>&1 | grep -oE '404|Not Found' | head -1
```

**Phải thấy:**
- cleanup in ra `role_dropped`, `schema_dropped` và `secret_deleted` đều `true`;
- `head-bucket` trả `404`.

**Việc cần làm trước window:** `window.sh` (P4) hiện chỉ nhận `RUN_ID` có prefix P4 hoặc P5 (`need_run_vars`). Khi chuẩn bị
window 29/11 phải cho nó nhận cả RUN_ID của window chung. Nếu không, lệnh cleanup sẽ dừng ngay ở bước kiểm biến.
