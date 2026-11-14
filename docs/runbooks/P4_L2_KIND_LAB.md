# P4 L2 — Lab kind không AWS (DRF-40, sau này DRF-45, DRF-51)

Runbook để **tự gõ lại** trên máy mình. Không đụng AWS, không tốn tiền.
Mỗi bước có: **gõ**, **phải thấy**, **nếu sai**. Cuối file có phần dọn và undo.

- Spec: `.agent/specs/SPEC-P4_RAG_SANDBOX.md` §5 và §10.
- Kết quả lần chạy đầu: `docs/evidence/p4/P4-T1_KRO_SPIKE_20261114.md`.
- Cần Docker Desktop đang chạy. Mục S mất khoảng 15 phút.

## S. Spike kro: 4 tính năng mà RAGSandbox cần

Manifest: `labs/p4-kro-spike/`. Một API giả `KroSpike` sinh ra:
- đọc `platform-config` ở `zdr-platform` (externalRef);
- một Job ở `zdr-platform`, tên có số attempt;
- một ConfigMap `app` ở namespace tenant, chỉ được tạo sau khi Job thành công.

### S0. Chuẩn bị shell (Git Bash)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
export PATH="/r/_Dev_tools/kubectl:/r/_Dev_tools/kind:$PATH"
export LAB="$HOME/zdr-p4-spike"
mkdir -p "$LAB"
export KUBECONFIG="$LAB/kind.kubeconfig"
```

**Phải thấy:** không lỗi. Mở terminal mới thì `export` lại.

### S1. Cluster và kro 0.9.4

```bash
kind create cluster --name zdr-p4-spike --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 --wait 180s
kubectl apply -f labs/p4-kro-spike/kro-rbac.yaml
helm install kro oci://registry.k8s.io/kro/charts/kro --version 0.9.4 -n kro-system --create-namespace --set rbac.mode=aggregation --wait --timeout 5m
kubectl -n kro-system get pods
```

**Phải thấy:** pod kro `Running`.

### S2. Platform và RGD

```bash
kubectl apply -f labs/p4-kro-spike/platform.yaml
kubectl apply -f labs/p4-kro-spike/rgd.yaml
kubectl get rgd kro-spike
kubectl get rgd kro-spike -o jsonpath='{.status.topologicalOrder}'; echo
```

**Phải thấy:** `STATE=Active`, thứ tự `["platformConfig","job","app"]`.

**Nếu sai:** RGD `Inactive` với `cache sync timeout` → ClusterRole thiếu
`krospikes`; apply lại `kro-rbac.yaml`.

### S3. Attempt 0 fail

```bash
kubectl apply -f labs/p4-kro-spike/instance.yaml
kubectl -n zdr-platform get jobs -w        # Ctrl+C khi thấy Failed (~10 s)
kubectl -n tenant-a get krospike s1
kubectl -n tenant-a get jobs
kubectl -n tenant-a get cm s1-app
kubectl -n zdr-platform logs job/tenant-a-s1-boot-0
```

**Phải thấy:**
- Job `tenant-a-s1-boot-0` nằm ở **zdr-platform** và `Failed`;
- instance `IN_PROGRESS`, `READY=False`;
- `tenant-a` không có Job; `s1-app` NotFound;
- log in `host=lab-db.zdr-platform.svc` (giá trị lấy qua externalRef).

### S4. Retry: attempt 1 thành công

```bash
sed -e 's/attempt: 0/attempt: 1/' -e 's/exitCode: 1/exitCode: 0/' labs/p4-kro-spike/instance.yaml | kubectl apply -f -
kubectl -n tenant-a get krospike s1 -w     # Ctrl+C khi ACTIVE True
kubectl -n zdr-platform get jobs
kubectl -n tenant-a get cm s1-app -o jsonpath='{.data}'; echo
```

**Phải thấy:** instance `ACTIVE True`; chỉ còn Job `boot-1` (kro đã xóa `boot-0`);
`s1-app` có `bootJob=tenant-a-s1-boot-1`.

### S5. Fail lại sau khi đã thành công (kịch bản 6)

```bash
sed -e 's/attempt: 0/attempt: 2/' labs/p4-kro-spike/instance.yaml | kubectl apply -f -
kubectl -n tenant-a get krospike s1 -w     # Ctrl+C khi IN_PROGRESS False
kubectl -n zdr-platform get jobs
```

**Phải thấy:** instance về `READY=False`; còn cả `boot-1` Complete và `boot-2`
Failed (kro chưa dọn Job cũ khi attempt hiện tại đang fail).

### S6. Retry lần nữa, rồi xóa instance

```bash
sed -e 's/attempt: 0/attempt: 3/' -e 's/exitCode: 1/exitCode: 0/' labs/p4-kro-spike/instance.yaml | kubectl apply -f -
kubectl -n tenant-a get krospike s1 -w     # Ctrl+C khi ACTIVE True
kubectl -n zdr-platform get jobs,pods
kubectl -n tenant-a delete krospike s1
kubectl -n zdr-platform get jobs,pods,cm
kubectl -n tenant-a get cm
```

**Phải thấy:**
- sau retry: chỉ còn Job `boot-3`, nhưng **pod của boot-0..3 vẫn còn**;
- sau khi xóa: không còn Job nào, `s1-app` mất, `platform-config` còn nguyên,
  **4 pod vẫn còn** trong `zdr-platform` (pod mồ côi, xem evidence).

### Tự thử

1. **Bỏ `readyWhen`.** Xóa 2 dòng `readyWhen:` của node `job` trong
   `labs/p4-kro-spike/rgd.yaml`, apply lại RGD, làm lại S3. Phải thấy instance
   `ACTIVE` dù Job `Failed`, và `s1-app` được tạo ngay. Đó là lý do SPEC §10 không
   cho bỏ điều kiện Job. Trả file lại: `git checkout labs/p4-kro-spike/rgd.yaml`.
2. **Xem pod mồ côi.** `kubectl -n zdr-platform get pod -o jsonpath='{range .items[*]}{.metadata.name} owners={.metadata.ownerReferences}{"\n"}{end}'`
   → `owners=` rỗng. Dọn bằng tay: `kubectl -n zdr-platform delete pod -l job-name`.

### S7. Dọn

```bash
kubectl delete rgd kro-spike
kind delete cluster --name zdr-p4-spike
```

**Verify:**

```bash
kind get clusters
docker ps -a --filter name=zdr-p4-spike --format '{{.Names}}' | wc -l
```

**Phải thấy:** `No kind clusters found.` và `0`.

### Undo / gỡ hẳn

- `kind delete cluster --name zdr-p4-spike` là undo đầy đủ.
- Xóa thư mục kubeconfig: `rm -rf "$HOME/zdr-p4-spike"`.
- Không có tài nguyên AWS nào.

### Giới hạn

kind không chứng minh IRSA, Secrets Manager, RDS, S3 hay readiness `/readyz` của
Deployment thật (P4-T3.2, P4-T4.1).
