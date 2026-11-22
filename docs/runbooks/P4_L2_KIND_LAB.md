# P4 L2 — Lab kind không AWS (DRF-40, sau này DRF-45, DRF-51)

Runbook để **tự gõ lại** trên máy mình. Không đụng AWS, không tốn tiền.
Mỗi bước có: **gõ**, **phải thấy**, **nếu sai**. Cuối file có phần dọn và undo.

- Spec: `.agent/specs/SPEC-P4_RAG_SANDBOX.md` §5 và §10.
- Kết quả lần chạy đầu: `docs/evidence/p4/P4-T1_KRO_SPIKE_20261114.md` (mục S),
  `docs/evidence/p4/P4-T2.1_L2_KIND_DB_<ngày>.md` (mục D),
  `docs/evidence/p4/P4-T3.2_L2_KIND_GRAPH_20261119.md` (mục G).
- Cần Docker Desktop đang chạy. Mục S mất khoảng 15 phút, mục D khoảng 30 phút,
  mục G khoảng 40 phút.

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

Nếu builder của bạn dùng driver `docker-container` (log D1 có `creating container
buildx_buildkit_…`), lần build D1 còn để lại một container BuildKit, volume cache của nó
và image `moby/buildkit`. Kiểm tra bằng `docker ps -a | grep buildkit`; nếu có thì dọn:

```bash
docker rm -f buildx_buildkit_desktop-linux
docker volume rm buildx_buildkit_desktop-linux_state
docker image rm moby/buildkit:buildx-stable-1
```

Đổi `desktop-linux` thành tên builder của bạn (`docker buildx ls`). Chỉ xoá volume
`_state` của builder mà lab vừa dùng.

**Undo:** các lệnh trên là undo đầy đủ. Không có gì trên AWS.

### Giới hạn của mục D

- Master là superuser `postgres`. RDS dùng `rds_superuser`, không phải superuser. pgvector 0.8.2
  không phải extension trusted, nên trên PostgreSQL thường chỉ superuser cài được.
- Không có TLS (`DB_SSLMODE=disable`). RDS bắt TLS; `verify-full` chỉ được chứng minh ở L3.
- Secret là file JSON trên PVC (`SECRET_BACKEND=file`). Không chứng minh IRSA hay Secrets Manager.
- Lệnh chạy bằng `kubectl exec`, chưa qua Job do kro tạo. Phần đó là DRF-51.

## G. Graph RAGSandbox thật trên kind (DRF-51 phần C)

Lần này kro tự tạo mọi thứ từ một request, giống EKS: Job `bootstrap` ở `zdr-platform`,
rồi ServiceAccount, Deployment, Service ở namespace tenant. Bạn quan sát thứ tự, lúc
instance Ready, ba ca lỗi, retry bằng `bootstrapAttempt`, request âm và xoá.

Manifest:
- **thật, từ Git:** `gitops/platform/tenants/` (namespace, 2 ServiceAccount nền tảng),
  `gitops/platform/kro-rbac/clusterrole-p4.yaml`, các request trong `gitops/requests/`;
- **RGD lab:** `labs/p4-kind/lab_rgd.py` sinh ra từ `gitops/platform/rgd/rag-sandbox.yaml`, chỉ
  đổi 3 thứ: bỏ node `bucket`, secret đọc từ file, tắt TLS. Script tự kiểm phần còn lại không đổi;
- **chỉ cho lab:** `labs/p4-kind/lab.yaml` (PostgreSQL, kho secret), `db-init.yaml`,
  `platform-config.yaml`, `cleanup.yaml`.

Image app là image đã publish (`ghcr.io/.../rag-sandbox@sha256:850c77c2…`), kéo ẩn danh. Không cần build.
Mất khoảng 40 phút. **Trước mỗi bước, ghi dự đoán vào `Dự đoán:` rồi mới gõ.**

### G0. Chuẩn bị shell (Git Bash)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
export PATH="/r/_Dev_tools/kubectl:/r/_Dev_tools/kind:$PATH"
export MSYS_NO_PATHCONV=1
export LAB="$(cygpath -m "$HOME/zdr-p4-kind")"
mkdir -p "$LAB"
export KUBECONFIG="$LAB/kind.kubeconfig"
kn() { docker exec zdr-p4-kind-control-plane "$@"; }      # lệnh chạy trên node kind
q() { kubectl -n "$1" exec deploy/rag-docs-qa -- python -c "import sys,urllib.request as u
try: r=u.urlopen('http://localhost:8080'+sys.argv[1],timeout=30); print(r.status, r.read().decode())
except Exception as e: print(getattr(e,'code',e), getattr(e,'read',lambda:b'')().decode())" "$2"; }
export -f q                                               # để G9 gọi được q dưới `timeout`
```

Dán **từng khối một**. Nếu dán nhiều khối rồi bấm Ctrl+C, các dòng phía sau có thể bị bỏ
hoặc vẫn chạy, nên không biết chắc trạng thái.

`q tenant-a /readyz` gọi app từ trong Pod của nó (image không có curl). `LAB` dạng
`C:/Users/...` dùng được cho cả Git Bash lẫn `kubectl.exe` khi đã tắt đổi đường dẫn.

### G1. Cluster và kro 0.9.4 (image pin digest như `gitops/platform/apps/30-kro.yaml`)

```bash
kind create cluster --name zdr-p4-kind --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 --wait 180s
helm install kro oci://registry.k8s.io/kro/charts/kro --version 0.9.4 -n kro-system --create-namespace \
  --set rbac.mode=aggregation --set image.repository=registry.k8s.io/kro/kro \
  --set image.tag='v0.9.4@sha256:eaf9fbaddd9d7f6cf400a8d47ab066b14cbef22b92a79be7bbdc7b3673376fb9' --wait --timeout 5m
```

**Phải thấy:** `Install complete`.

### G2. Kho secret lab, object nền tảng, database, db-init

```bash
kn sh -c 'mkdir -p /var/lib/zdr-lab/secrets/zero-drift/rag/tenant-a /var/lib/zdr-lab/secrets/zero-drift/rag/tenant-b && chown -R 10001:10001 /var/lib/zdr-lab && chmod -R 0700 /var/lib/zdr-lab/secrets'
kubectl apply -f gitops/platform/tenants/
kubectl apply -f gitops/platform/kro-rbac/clusterrole-p4.yaml
kubectl -n zdr-platform create configmap lab-seed --from-file=labs/p4-kind-db/seed_master.py
kubectl apply -f labs/p4-kind/lab.yaml
kubectl -n zdr-platform wait pod/lab-db --for=condition=Ready --timeout=240s
kubectl apply -f labs/p4-kind/db-init.yaml
kubectl -n zdr-platform wait job/db-init --for=condition=Complete --timeout=180s
kubectl -n zdr-platform logs job/db-init
kubectl get pvc -A
```

**Phải thấy:** 3 PVC `lab-secrets` `Bound` (zdr-platform, tenant-a, tenant-b); log db-init có
`"bootstrap_secret_created": true`, `"vector_version": "0.8.2"`.

**Vì sao PV hostPath:** Pod Security `restricted` (label trên namespace trong Git) cấm volume
`hostPath` trong Pod, nhưng cho PVC. PV của tenant-a chỉ trỏ vào `zero-drift/rag/tenant-a`,
nên app tenant-a không thấy secret master, bootstrap hay tenant-b, giống role IAM trên EKS.

### G3. RGD lab

Dự đoán: thứ tự topo có những node nào, theo thứ tự nào? `bucket` có mặt không?

```bash
python labs/p4-kind/lab_rgd.py > "$LAB/lab-rgd.yaml"
kubectl apply -f "$LAB/lab-rgd.yaml"
kubectl get rgd rag-sandbox -o wide
```

**Phải thấy:** `Active`, `["platformConfig","bootstrap","serviceAccount","app","service"]`.
**Nếu sai:** `Inactive` + `cache sync timeout` → thiếu `ragsandboxes` trong ClusterRole (G2).

### G4. Request khi chưa có `platform-config`

Dự đoán: Job bootstrap có chạy không? Instance báo gì?

```bash
kubectl apply -f gitops/requests/tenant-a-docs-qa.yaml
sleep 20
kubectl -n tenant-a get ragsandbox docs-qa -o wide
kubectl -n tenant-a get ragsandbox docs-qa -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'; echo
kubectl -n zdr-platform get jobs
```

**Phải thấy:** `IN_PROGRESS`, message `waiting for external reference "platformConfig": not found`,
chỉ có Job `db-init`. Đây là cổng của window: `platform-config` chỉ được apply sau khi
db-init thành công, nên không Job bootstrap nào chạy trước database.

### G5. Apply `platform-config`: thứ tự tạo và lúc Ready

Dự đoán: object nào xuất hiện trước? Bao lâu thì `ACTIVE`?

```bash
date -u +%T; kubectl apply -f labs/p4-kind/platform-config.yaml
kubectl -n tenant-a wait ragsandbox/docs-qa --for=jsonpath='{.status.state}'=ACTIVE --timeout=240s; date -u +%T
kubectl -n tenant-a get ragsandbox docs-qa -o jsonpath='{.status}'; echo
{ kubectl -n zdr-platform get job -l rag.zero-drift.io/sandbox=docs-qa -o jsonpath='{range .items[*]}{.metadata.creationTimestamp} job/{.metadata.name} done={.status.completionTime}{"\n"}{end}'
  kubectl -n tenant-a get sa,deploy,svc -o jsonpath='{range .items[*]}{.metadata.creationTimestamp} {.kind}/{.metadata.name}{"\n"}{end}'; } | sort
q tenant-a /readyz
q tenant-a '/query?v=1,0,0,0&k=2'
kubectl -n tenant-a exec deploy/rag-docs-qa -- ls -lR /secrets
```

**Phải thấy:**
- Job `tenant-a-docs-qa-boot-0` tạo trước; SA, Deployment, Service chỉ xuất hiện **sau** khi Job xong;
- status có `endpoint`, `schema rag_tenant_a__docs_qa`, `secretName`, `bootstrapJob`,
  `bootstrapState Succeeded`, `availableReplicas 1`;
- `/readyz` 200 với `"bucket": "skipped"`; `/query` trả 2 dòng seed;
- trong Pod chỉ có `/secrets/zero-drift/rag/tenant-a/docs-qa.json`.

### G6. Lỗi 1: secret bootstrap sai → Job `Failed`

Dự đoán: Job retry mấy lần? Có gì được tạo trong `tenant-b` không? Có secret nào được ghi không?

```bash
B=/var/lib/zdr-lab/secrets/zero-drift/rag/platform/bootstrap.json
kn sh -c "cp -p $B $B.bak && sed -i 's/\"password\": \"[^\"]*\"/\"password\": \"wrong\"/' $B"
cp gitops/requests/tenant-b-docs-qa.yaml "$LAB/tenant-b.yaml"
kubectl apply -f "$LAB/tenant-b.yaml"
kubectl -n zdr-platform wait job/tenant-b-docs-qa-boot-0 --for=condition=Failed --timeout=120s
kubectl -n zdr-platform logs job/tenant-b-docs-qa-boot-0
kubectl -n tenant-b get ragsandbox docs-qa -o jsonpath='{.status.state} {.status.bootstrapState}{"\n"}'
kubectl -n tenant-b get sa,deploy,svc
kn find /var/lib/zdr-lab/secrets -name '*.json'
```

**Phải thấy:** Job `Failed` (`backoffLimit: 0`, không retry); log đúng một dòng
`OperationalError: authentication failed` (không host, không mật khẩu); instance `IN_PROGRESS Failed`;
tenant-b chỉ có `default` SA. Có file `tenant-b/docs-qa.json`: bootstrap ghi secret **trước** khi
đăng nhập database, lần sau dùng lại nó.

### G7. Retry: sửa nguyên nhân, tăng `bootstrapAttempt` trong file

Dự đoán: Job tên gì? `secret_created`, `role_created`? Job cũ `boot-0` và Pod của nó ra sao?

```bash
kn mv $B.bak $B                                             # sửa nguyên nhân (phía nền tảng)
sed -i 's/bootstrapAttempt: 0/bootstrapAttempt: 1/' "$LAB/tenant-b.yaml"
kubectl apply -f "$LAB/tenant-b.yaml"                        # như một lần Argo sync
kubectl -n tenant-b wait ragsandbox/docs-qa --for=jsonpath='{.status.state}'=ACTIVE --timeout=240s
kubectl -n zdr-platform logs job/tenant-b-docs-qa-boot-1
sleep 15; kubectl -n zdr-platform get jobs
kubectl -n zdr-platform get pods -l rag.zero-drift.io/tenant=tenant-b -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,OWNER:.metadata.ownerReferences[0].name
```

**Phải thấy:** `boot-1` thành công với `secret_created false`, `role_created true`; `ACTIVE`.
Job `boot-0` biến mất (kro xoá khi graph Ready) nhưng **Pod `boot-0-…` còn, OWNER `<none>`**.
Không sửa hay xoá gì bằng tay trong cluster.

### G8. Lỗi 2: app cầm credential sai

Dự đoán: instance còn Ready không? Sửa lại secret thì phải restart app không?

```bash
S=/var/lib/zdr-lab/secrets/zero-drift/rag/tenant-a/docs-qa.json
kn sh -c "cp -p $S /var/lib/zdr-lab/a.bak && sed -i 's/\"password\": \"[^\"]*\"/\"password\": \"wrong\"/' $S"
kubectl -n tenant-a delete pod -l rag.zero-drift.io/sandbox=docs-qa      # Pod mới đọc secret sai
sleep 45; kubectl -n tenant-a get ragsandbox docs-qa -o wide; q tenant-a /readyz
kn cp -p /var/lib/zdr-lab/a.bak $S                                       # trả secret đúng
kubectl -n tenant-a wait ragsandbox/docs-qa --for=jsonpath='{.status.state}'=ACTIVE --timeout=120s
kubectl -n tenant-a get pods
```

**Phải thấy:** `IN_PROGRESS False`, `/readyz` 503 `authentication failed`; sau khi trả secret,
`ACTIVE` lại trong khoảng 10 giây, `RESTARTS 0`: app đọc lại secret sau lỗi đăng nhập.

### G9. Lỗi 3: database không tới được

Dự đoán: `/readyz` trả lời sau bao lâu? Cả hai instance cùng mất Ready?

Khối 1, cắt mạng (lệnh gọi app bị chặn ở 90 giây, không thể treo mãi):

```bash
IP="$(kubectl -n zdr-platform get pod lab-db -o jsonpath='{.status.podIP}')"; echo "IP=$IP"
date -u +%T; kn iptables -I FORWARD 1 -d "$IP" -j DROP; kn iptables -I FORWARD 1 -s "$IP" -j DROP
time timeout 90 bash -c 'q tenant-a /readyz'; echo "exit=$?"
sleep 40; date -u +%T; kubectl get ragsandbox -A -o wide; kubectl -n tenant-a get pods
```

Khối 2, nối lại mạng. **Luôn chạy**, kể cả khi khối 1 lỗi hay bị ngắt:

```bash
kn iptables -D FORWARD -d "$IP" -j DROP; kn iptables -D FORWARD -s "$IP" -j DROP
kn iptables -S FORWARD | grep -c DROP                      # phải là 0
kubectl -n tenant-a wait ragsandbox/docs-qa --for=jsonpath='{.status.state}'=ACTIVE --timeout=120s
kubectl -n tenant-b wait ragsandbox/docs-qa --for=jsonpath='{.status.state}'=ACTIVE --timeout=120s
```

**Phải thấy:** `/readyz` 503 `ConnectionTimeout: timeout` trong khoảng 4–8 giây; cả hai `IN_PROGRESS`;
bỏ luật DROP thì cả hai `ACTIVE` lại trong vài giây. `exit=124` nghĩa là bị cắt ở 90 giây,
tức app treo: ghi lại trong evidence, đừng bỏ qua.

**Vì sao không đổi selector của Service:** lần chạy đầu thử cách đó và app vẫn Ready: kết nối TCP
đã mở đi thẳng tới IP Pod, không qua Service nữa. DROP trên node mới cắt cả kết nối đang mở.

### G10. Hai request âm

Dự đoán: cái nào bị chặn ở đâu? Exit code? Có tạo gì ở namespace tenant không?

```bash
kubectl create namespace zdr-requests                        # trên EKS do Argo tạo
kubectl apply -f gitops/requests/disabled/rag-sandbox-no-tenant-role.yaml -f gitops/requests/disabled/rag-sandbox-bad-name.yaml
kubectl -n zdr-platform wait job/zdr-requests-docs-qa-boot-0 job/tenant-a-docs--qa-boot-0 --for=condition=Failed --timeout=120s
kubectl -n zdr-platform logs job/zdr-requests-docs-qa-boot-0
kubectl -n zdr-platform logs job/tenant-a-docs--qa-boot-0
kubectl get ragsandbox -A -o wide
kubectl -n zdr-requests get sa,deploy,svc
bash gitops/check.sh | grep negative
```

**Phải thấy:** cả hai Job `Failed`, log `invalid input: tenant 'zdr-requests' is not one of …` và
`sandbox name 'docs--qa' must be …`; không SA/Deployment/Service, không secret mới; `check.sh` cũng chặn cả hai.

### G11. Xoá request, rồi `cleanup`

Dự đoán: kro gỡ những gì? Schema, role, secret, Pod của Job còn không?

```bash
kubectl delete -f gitops/requests/disabled/rag-sandbox-no-tenant-role.yaml -f gitops/requests/disabled/rag-sandbox-bad-name.yaml
kubectl delete -f "$LAB/tenant-b.yaml"
kubectl -n tenant-b get sa,deploy,svc; kubectl -n zdr-platform get jobs
kubectl -n zdr-platform get pods -L rag.zero-drift.io/tenant,rag.zero-drift.io/sandbox
kn find /var/lib/zdr-lab/secrets -name '*.json'
kubectl -n zdr-platform exec lab-db -c postgres -- psql -U postgres -d rag -tAc "select nspname from pg_namespace where nspname like 'rag_tenant%'"
kubectl apply -f labs/p4-kind/cleanup.yaml
kubectl -n zdr-platform wait job/cleanup-tenant-b-docs-qa --for=condition=Complete --timeout=120s
kubectl -n zdr-platform logs job/cleanup-tenant-b-docs-qa
kubectl -n zdr-platform delete pods -l rag.zero-drift.io/tenant=tenant-b,rag.zero-drift.io/sandbox=docs-qa
q tenant-a /readyz
```

**Phải thấy:** kro gỡ SA, Deployment, Service và Job; **schema, role, secret và các Pod của Job
vẫn còn** (kro không có hook xoá, D9); `platform-config` còn nguyên. `cleanup` in
`schema_dropped/role_dropped/secret_deleted true`; Pod xoá theo label; tenant-a vẫn 200.

### G12. (Tuỳ chọn) RGD thật có node `bucket` có biên dịch được không

kind không có Crossplane. Chỉ cài CRD `Bucket` lấy từ package provider đã pin, rồi cho kro biên
dịch RGD thật dưới một kind khác, để không đụng instance đang chạy.

```bash
PKG=xpkg.crossplane.io/crossplane-contrib/provider-aws-s3@sha256:4e6277277e91672d4a8b444f98b22723b4ca984d2e5845042188f429807919bd
docker pull -q "$PKG"; cid=$(docker create "$PKG" x); docker cp "$cid:/package.yaml" "$LAB/package.yaml"; docker rm "$cid"
python - "$LAB" <<'EOF'
import sys, yaml
lab = sys.argv[1]
crd = next(d for d in yaml.safe_load_all(open(lab + "/package.yaml", encoding="utf-8"))
           if d and d.get("kind") == "CustomResourceDefinition" and d["metadata"]["name"] == "buckets.s3.aws.m.upbound.io")
crd["spec"]["conversion"] = {"strategy": "None"}          # không có webhook của Crossplane
yaml.safe_dump(crd, open(lab + "/bucket-crd.yaml", "w"))
rgd = yaml.safe_load(open("gitops/platform/rgd/rag-sandbox.yaml", encoding="utf-8"))
rgd["metadata"]["name"] = "rag-sandbox-compile-check"; rgd["spec"]["schema"]["kind"] = "RAGSandboxCompileCheck"
yaml.safe_dump(rgd, open(lab + "/real-check.yaml", "w"), sort_keys=False)
EOF
kubectl apply --server-side -f "$LAB/bucket-crd.yaml"
kubectl -n kro-system rollout restart deploy/kro && kubectl -n kro-system rollout status deploy/kro
kubectl apply -f "$LAB/real-check.yaml"; sleep 15
kubectl get rgd rag-sandbox-compile-check -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
kubectl delete rgd rag-sandbox-compile-check
```

**Phải thấy:** `GraphAccepted=True`, thứ tự có `bucket` ngay sau `bootstrap`. `ControllerReady=False`
(`cache sync timeout`) là bình thường: kind thử nghiệm không có RBAC. **Đừng** `kubectl apply` RGD
thật với tên `rag-sandbox` lên cluster lab: nó thay RGD lab (lần chạy đầu lỡ làm vậy, xem evidence).

### Tự thử (không bắt buộc)

- Đóng băng PostgreSQL thay vì DROP: `kubectl -n zdr-platform exec lab-db -c postgres -- sh -c 'for d in /proc/[0-9]*; do [ "$(cat $d/comm 2>/dev/null)" = postgres ] && kill -STOP ${d#/proc/}; done'`
  (sau đó `kill -CONT`). Đoán xem `/readyz` có trả lời trong 8 giây không, và vì sao khác G9.
- Tăng `bootstrapAttempt` của một request **đang Ready**: Job mới chạy lại, có đổi mật khẩu không?

### G13. Dọn

```bash
kind delete cluster --name zdr-p4-kind
rm -rf "$LAB"
docker image rm xpkg.crossplane.io/crossplane-contrib/provider-aws-s3@sha256:4e6277277e91672d4a8b444f98b22723b4ca984d2e5845042188f429807919bd   # nếu đã làm G12
```

**Undo:** các lệnh trên là undo đầy đủ. Kho secret nằm trong node kind nên mất cùng cluster.
Không có gì trên AWS.

### Giới hạn của mục G

- Không bucket, không Crossplane, không IRSA, không Secrets Manager, không TLS: kind không chứng
  minh gì về chúng (SPEC P4-T3.2). G12 chỉ chứng minh RGD thật **biên dịch** được.
- Request được `kubectl apply`, không qua Argo CD: "Argo Synced" của request âm chỉ thấy ở L3.
- Một node: không kiểm Pod ở node khác, không kiểm NetworkPolicy.
