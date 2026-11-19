# P4 L2 — Lab kind không AWS (DRF-40, sau này DRF-45, DRF-51)

Runbook để **tự gõ lại** trên máy mình. Không đụng AWS, không tốn tiền.
Mỗi bước có: **gõ**, **phải thấy**, **nếu sai**. Cuối file có phần dọn và undo.

- Spec: `.agent/specs/SPEC-P4_RAG_SANDBOX.md` §5 và §10.
- Kết quả lần chạy đầu: `docs/evidence/p4/P4-T1_KRO_SPIKE_20261114.md` (mục S),
  `docs/evidence/p4/P4-T2.1_L2_KIND_DB_<ngày>.md` (mục D).
- Cần Docker Desktop đang chạy. Mục S mất khoảng 15 phút, mục D khoảng 30 phút.

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

## D. Ranh giới database trên kind (DRF-45 phần B)

Một PostgreSQL 17 có pgvector chạy trong kind, đóng vai RDS. Bạn chạy ba entry
point `db-init`, `bootstrap`, `cleanup` (code ở `workloads/rag-sandbox/`) từ pod
`toolbox`, rồi tự kiểm quyền bằng `psql`.

Manifest: `labs/p4-kind-db/`. Trong `zdr-platform` có:
- `lab-db`: PostgreSQL. initContainer `seed-master` tạo secret master giả, giống secret mà RDS tạo;
- `toolbox`: cùng môi trường như các Job sau này, thêm `psql-as <secret>` để đăng nhập bằng một secret.

**Cách làm:** trước mỗi bước, ghi **dự đoán** vào chỗ `Dự đoán:` rồi mới gõ.
Lab chấm cách bạn đoán và giải thích, không chấm tốc độ.

### D0. Chuẩn bị shell (Git Bash)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
export PATH="/r/_Dev_tools/kubectl:/r/_Dev_tools/kind:$PATH"
export MSYS_NO_PATHCONV=1
export LAB="$HOME/zdr-p4-db"
mkdir -p "$LAB"
export KUBECONFIG="$(cygpath -w "$LAB/kind.kubeconfig")"
tb() { kubectl -n zdr-platform exec toolbox -- "$@"; }
```

**Vì sao có 2 dòng lạ:** `MSYS_NO_PATHCONV=1` ngăn Git Bash đổi `/secrets/...` thành
`C:/Program Files/Git/secrets/...`. Khi đã tắt việc đổi đường dẫn, `kubectl.exe` không đọc
được `/c/Users/...`, nên `KUBECONFIG` phải ở dạng Windows (`cygpath -w`).

**Nếu sai:** lỗi `localhost:8080 ... refused` nghĩa là `KUBECONFIG` sai; `export` lại dòng cuối.

### D1. Image lab, cluster, database

```bash
docker build --load -f labs/p4-kind-db/Dockerfile --build-context app=workloads/rag-sandbox -t zdr-ragsandbox:lab labs/p4-kind-db
kind create cluster --name zdr-p4-db --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 --wait 180s
kind load docker-image zdr-ragsandbox:lab --name zdr-p4-db
kubectl apply -f labs/p4-kind-db/lab.yaml
kubectl -n zdr-platform wait pod/lab-db pod/toolbox --for=condition=Ready --timeout=240s
```

**Phải thấy:** hai pod `condition met`.

**Nếu sai:** pod `ErrImageNeverPull` → chưa `kind load`; chạy lại lệnh `kind load`.

### D2. `db-init` hai lần

Dự đoán: lần 2 thì `database_created`, `bootstrap_role_created`, `bootstrap_secret_created` là gì? ___

```bash
tb python -m ragsandbox db-init
tb python -m ragsandbox db-init
tb psql-as lab/master -d postgres -Atc "select rolname, rolsuper, rolcreaterole, rolcreatedb from pg_roles where rolname = 'rag_bootstrap'"
```

**Phải thấy:** lần 1 toàn `true`, `vector_version` là `0.8.2`; lần 2 toàn `false`.
`rag_bootstrap|f|t|f` nghĩa là không superuser, có CREATEROLE, không CREATEDB.

### D3. `bootstrap` hai sandbox, rồi chạy lại một cái

Dự đoán: chạy lại `tenant-a/s1` thì mật khẩu có đổi không? Kiểm bằng gì? ___

```bash
tb python -m ragsandbox bootstrap --tenant tenant-a --name s1
tb python -m ragsandbox bootstrap --tenant tenant-b --name s2
tb psql-as lab/master -d postgres -Atc "select md5(rolpassword) from pg_authid where rolname = 'rag_tenant_a__s1'"
tb python -m ragsandbox bootstrap --tenant tenant-a --name s1
tb psql-as lab/master -d postgres -Atc "select md5(rolpassword) from pg_authid where rolname = 'rag_tenant_a__s1'"
```

**Phải thấy:** lần chạy lại có `"password_changed": false`, `"role_created": false`. Hai dòng
md5 **giống hệt nhau**. `md5` chỉ dùng để in gọn dấu vân tay của verifier SCRAM, không lộ mật khẩu.

### D4. Chiều được phép: bảng vector và truy vấn similarity

Dự đoán: bảng `items` nằm ở schema nào? Hàng nào gần `[1,0,0]` nhất? ___

```bash
tb psql-as zero-drift/rag/tenant-a/s1 -c "create table items (id int primary key, embedding vector(3))"
tb psql-as zero-drift/rag/tenant-a/s1 -c "insert into items values (1,'[1,0,0]'), (2,'[0,1,0]'), (3,'[0.9,0.1,0]')"
tb psql-as zero-drift/rag/tenant-a/s1 -c "select id, embedding <-> '[1,0,0]' as dist from items order by 2 limit 2"
tb psql-as zero-drift/rag/tenant-a/s1 -c "select current_user, current_schema()"
```

**Phải thấy:** `1` (dist 0) rồi `3` (≈0.141); schema là `rag_tenant_a__s1`.

### D5. Chiều bị từ chối

Dự đoán từng dòng: lệnh nào lỗi, thông báo gì? ___

```bash
tb psql-as zero-drift/rag/tenant-b/s2 -c "select * from rag_tenant_a__s1.items"
tb psql-as zero-drift/rag/tenant-a/s1 -c "create role intruder"
tb psql-as zero-drift/rag/platform/bootstrap -c "alter role rag_bootstrap superuser"
tb python -m ragsandbox bootstrap --tenant tenant-c --name s1; echo "exit=$?"
```

**Phải thấy:**
1. `permission denied for schema rag_tenant_a__s1` (B không có USAGE trên schema của A);
2. `Only roles with the CREATEROLE attribute may create roles`;
3. `Only roles with the SUPERUSER attribute may change the SUPERUSER attribute`;
4. `invalid input: tenant 'tenant-c' ...`, `exit=2`.

### D6. `cleanup` và kiểm không còn gì

Dự đoán: chạy `cleanup` lần hai thì sao? `tenant-b/s2` có bị ảnh hưởng không? ___

```bash
tb python -m ragsandbox cleanup --tenant tenant-a --name s1
tb python -m ragsandbox cleanup --tenant tenant-a --name s1
tb psql-as lab/master -Atc "select count(*) from pg_roles where rolname = 'rag_tenant_a__s1'" -c "select count(*) from pg_namespace where nspname = 'rag_tenant_a__s1'"
tb ls -R /secrets/zero-drift/rag
tb psql-as zero-drift/rag/tenant-b/s2 -Atc "select current_user"
```

**Phải thấy:** lần 1 toàn `true`, lần 2 toàn `false` (không lỗi); hai số `0`; thư mục
`tenant-a` rỗng; `s2` vẫn đăng nhập được.

### Tự thử (không bắt buộc)

- Xóa riêng secret của `s2` (`tb rm /secrets/zero-drift/rag/tenant-b/s2.json`) rồi `bootstrap` lại
  `s2`: đoán trước `secret_created` và `password_changed`, rồi kiểm `psql-as` còn vào được không.
- Thử một tên sai: `--name S1`, `--name a--b`, `--name x" ; drop role postgres; --`.

### D7. Dọn

```bash
kind delete cluster --name zdr-p4-db
rm -rf "$LAB"
docker image rm zdr-ragsandbox:lab
```

**Undo:** ba lệnh trên là undo đầy đủ. Không có gì trên AWS.

### Giới hạn của mục D

- Master là superuser `postgres`. RDS dùng `rds_superuser`, không phải superuser. pgvector 0.8.2
  không phải extension trusted, nên trên PostgreSQL thường chỉ superuser cài được.
- Không có TLS (`DB_SSLMODE=disable`). RDS bắt TLS; `verify-full` chỉ được chứng minh ở L3.
- Secret là file JSON trên PVC (`SECRET_BACKEND=file`). Không chứng minh IRSA hay Secrets Manager.
- Lệnh chạy bằng `kubectl exec`, chưa qua Job do kro tạo. Phần đó là DRF-51.
