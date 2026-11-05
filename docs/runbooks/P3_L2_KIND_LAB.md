# P3 L2 — Lab kind không AWS: Argo CD, Crossplane, kro (DRF-39)

Runbook để **tự gõ lại** toàn bộ lab trên máy mình. Không đụng AWS, không tốn tiền.
Mỗi bước có 3 phần: **gõ**, **phải thấy**, **nếu sai**. Cuối file có phần dọn và phần undo.

- Spec: `.agent/specs/SPEC-P3_FIRST_RESOURCE_GRAPH.md` Task 2.
- Pins: `docs/VERSION_MATRIX.md` §7, `docs/evidence/p3/DRF34_P3_PINS_20261105.md`.
- Manifest lab: `labs/p3-kind/` và `gitops/lab/`.
- Kết quả lần chạy đầu: `docs/evidence/p3/DRF14_L2_KIND_20261105.md`.

Thời gian: khoảng 30 phút nếu image đã có sẵn, 45 phút nếu phải tải lần đầu. Cần Docker Desktop đang chạy, và trống khoảng 4 GiB RAM.

## Sơ đồ

```
Git (gitops/lab)  ──Argo CD──▶  Deployment            E1, E2
kubectl apply     ──────────▶  Bucket (Crossplane)    E3: không có credential → Synced=False
ZdrRequest (kro)  ──kro─────▶  Deployment + Bucket    E4: readyWhen quyết định Ready
```

## 0. Chuẩn bị shell (Git Bash)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
export PATH="/r/_Dev_tools/kubectl:/r/_Dev_tools/kind:$PATH"
export LAB="$HOME/zdr-p3-lab"          # nơi tải file cài; KHÔNG nằm trong repo
mkdir -p "$LAB"
export KUBECONFIG="$LAB/kind.kubeconfig"   # kubeconfig riêng, không đè ~/.kube/config
kind version; kubectl version --client | head -1; helm version --short; docker version --format '{{.Server.Version}}'
```

**Phải thấy:** kind `v0.33.0`, kubectl `v1.35.x`, helm `v4.x`, và Docker có in ra version của server.

**Nếu sai:** nếu Docker không trả lời thì mở Docker Desktop rồi đợi khoảng 1 phút. Nếu thiếu kind thì xem `DRF34_P3_PINS_20261105.md` (đã có bước tải và kiểm sha256).

> `KUBECONFIG` trỏ vào file riêng. Mở terminal mới thì phải `export` lại cả 3 biến ở trên.

## 1. Tạo cluster kind 1.35 (pin bằng digest)

```bash
kind create cluster --name zdr-p3-lab \
  --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 \
  --wait 180s
kubectl get nodes
kubectl version -o json | jq -r .serverVersion.gitVersion
```

**Phải thấy:** 1 node `Ready`, version `v1.35.8`.

## 2. Cài Argo CD v3.5.7 (kiểm sha256 trước khi apply)

```bash
curl -fsSL -o "$LAB/argocd-install-v3.5.7.yaml" \
  https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.7/manifests/install.yaml
echo "09bfbb9041b4a8503c6e4fa22cf41c403fa62be17526de353648a4551f5beb77  $LAB/argocd-install-v3.5.7.yaml" | sha256sum -c
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f "$LAB/argocd-install-v3.5.7.yaml" > /dev/null
kubectl -n argocd wait --for=condition=Available deploy --all --timeout=300s
```

**Phải thấy:** `sha256sum` báo `OK`, sau đó 6 deployment báo `condition met`.

**Nếu sai:** nếu sha256 không khớp thì **dừng lại**, vì file đã khác bản đã pin. Phải dùng `--server-side`: CRD của Argo quá lớn so với giới hạn annotation của apply thường.

## 3. Cài Crossplane 2.4.3 (Helm chart đã pin)

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable 2>/dev/null; helm repo update crossplane-stable
helm pull crossplane-stable/crossplane --version 2.4.3 -d "$LAB"
echo "eeace77cdc7e727a8400cb7a229e290d4d28dd730b440a1b06fb6df4569cd33c  $LAB/crossplane-2.4.3.tgz" | sha256sum -c
helm install crossplane "$LAB/crossplane-2.4.3.tgz" -n crossplane-system --create-namespace --wait --timeout 6m
kubectl -n crossplane-system get pods
```

**Phải thấy:** 2 pod `crossplane-…` và `crossplane-rbac-manager-…` đều `Running`.

## 4. Cài provider S3 (pin bằng digest)

```bash
kubectl apply -f labs/p3-kind/providers.yaml
kubectl wait providers.pkg.crossplane.io --all --for=condition=Healthy --timeout=600s
kubectl get providers.pkg.crossplane.io
kubectl -n crossplane-system get sa provider-aws-s3
kubectl get crd -o name | grep -c 'aws.*upbound.io'
```

**Phải thấy:**
- 2 provider ở trạng thái `INSTALLED=True` và `HEALTHY=True`;
- ServiceAccount tên đúng là `provider-aws-s3` (sau này IRSA sẽ trust tên này);
- chỉ có CRD của S3 (lần chạy đầu: 55).

**Nếu sai:**
- Lỗi `cannot resolve package dependencies: invalid semantic version` nghĩa là `skipDependencyResolution: true` đã bị xóa khỏi file.
- Provider lớn nên có thể mất 3–5 phút để tải image.

**Tự thử (khuyến khích):** xóa dòng `skipDependencyResolution: true` khỏi một bản copy của file rồi apply lại để tự thấy lỗi trên. Xong thì apply lại file gốc.

## 5. Cài kro 0.9.4 (RBAC mode aggregation)

```bash
kubectl apply -f labs/p3-kind/kro-rbac.yaml
helm install kro oci://registry.k8s.io/kro/charts/kro --version 0.9.4 \
  -n kro-system --create-namespace --set rbac.mode=aggregation --wait --timeout 5m
kubectl -n kro-system get pods
kubectl -n kro-system get pods -o jsonpath='{.items[0].status.containerStatuses[0].imageID}{"\n"}'
```

**Phải thấy:** pod kro `Running`, và imageID kết thúc bằng `@sha256:eaf9fbad…`.

**Nếu sai:** viết `--version 0.9.4`, không có chữ `v`. Viết `v0.9.4` sẽ báo không tìm thấy chart.

## E1. Argo CD sync Deployment từ Git

```bash
kubectl apply -f labs/p3-kind/argocd-app.yaml
kubectl -n argocd get app zdr-lab -w        # Ctrl+C khi thấy Synced  Healthy
kubectl -n zdr-lab get deploy,pods
kubectl -n argocd get app zdr-lab -o jsonpath='{.status.sync.revision}{"\n"}'
```

**Phải thấy:**
- khoảng 15–20 giây sau, app ở `Synced  Healthy`;
- Deployment `zdr-lab-pause` ở `1/1`;
- revision là commit trên `main` đang chứa `gitops/lab/`.

App trỏ `targetRevision: main`. Muốn thử một nhánh khác thì đổi bằng `sed`, như lần chạy đầu:
`sed 's|targetRevision: main|targetRevision: <nhánh>|' labs/p3-kind/argocd-app.yaml | kubectl apply -f -`

**Tự thử (đổi trong Git):**
1. Tạo nhánh lab.
2. Sửa `replicas: 1` thành `2` trong `gitops/lab/deployment.yaml`, commit và push.
3. Trỏ app sang nhánh đó.
4. Đợi tối đa 3 phút (chu kỳ poll mặc định), hoặc bấm refresh ngay:

   `kubectl -n argocd annotate app zdr-lab argocd.argoproj.io/refresh=normal --overwrite`

**Phải thấy:** replicas lên 2 và revision đổi sang commit mới.

## E2. Sửa tay trên cluster, có và không có selfHeal

```bash
# a) selfHeal=false (giá trị trong file)
kubectl -n zdr-lab scale deploy zdr-lab-pause --replicas=3
kubectl -n argocd get app zdr-lab        # đợi 30-60 s rồi gõ lại
kubectl -n zdr-lab get deploy zdr-lab-pause

# b) bật selfHeal
kubectl -n argocd patch app zdr-lab --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
kubectl -n zdr-lab get deploy zdr-lab-pause -w    # Ctrl+C khi về 1/1

# c) sửa tay lần nữa khi selfHeal đang bật
kubectl -n zdr-lab scale deploy zdr-lab-pause --replicas=3
kubectl -n zdr-lab get deploy zdr-lab-pause -w
```

**Phải thấy:**
- (a) app `OutOfSync`, nhưng replicas **vẫn 3**: Argo chỉ báo lệch, không sửa.
- (b) và (c) replicas quay về 1 trong khoảng 5 giây.

## E3. Bucket không có credential AWS

```bash
B=bucket.s3.aws.m.upbound.io
kubectl apply -f labs/p3-kind/bucket-nocred.yaml
kubectl -n zdr-e3 get $B                    # đợi 1-2 phút, gõ lại vài lần
kubectl -n zdr-e3 get events

# Bước 2: thêm ClusterProviderConfig trỏ tới Secret KHÔNG tồn tại
kubectl apply -f labs/p3-kind/providerconfig-missing-secret.yaml
kubectl -n zdr-e3 annotate $B zero-drift-p3-lab-e3 zdr/nudge="$(date +%s)" --overwrite
kubectl -n zdr-e3 get $B
kubectl -n zdr-e3 get $B zero-drift-p3-lab-e3 -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
```

**Phải thấy:**
- **Bước 1:** cột `SYNCED` và `READY` **trống**, không có event nào. Không có ClusterProviderConfig thì provider im lặng hoàn toàn. Đây là cái bẫy: "không có lỗi" không có nghĩa là "đang chạy".
- **Bước 2:** khoảng 10 giây sau là `SYNCED=False`, `READY` trống, và có message `… cannot get credentials secret: Secret "aws-creds-does-not-exist" not found`.
- Đây là bằng chứng local cho **Synced ≠ Ready**: object đã được nhận, nhưng chưa bao giờ ra tới AWS.

**Nếu muốn xem provider đang làm gì:** bật log debug (chỉ trong lab):

```bash
kubectl patch deploymentruntimeconfig provider-aws-s3 --type merge \
  -p '{"spec":{"deploymentTemplate":{"spec":{"selector":{},"template":{"spec":{"containers":[{"name":"package-runtime","args":["--debug"]}]}}}}}}'
kubectl -n crossplane-system logs deploy/$(kubectl -n crossplane-system get deploy -o name | grep provider-aws-s3 | cut -d/ -f2) -f | grep -v 'gvk is ready'
```

## E4. kro: một API mới sinh ra Deployment và Bucket

```bash
kubectl apply -f labs/p3-kind/rgd.yaml
kubectl get rgd zdr-request -w                      # Ctrl+C khi STATE=Active
kubectl get crd zdrrequests.kro.run                 # kind mới do kro sinh ra
kubectl apply -f labs/p3-kind/instance.yaml
kubectl -n zdr-e4 get zdrrequest,deploy,bucket.s3.aws.m.upbound.io
kubectl -n zdr-e4 get zdrrequest demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
```

**Phải thấy:**
- RGD `Active`;
- `demo-app` ở `1/1`;
- Bucket `SYNCED=False` (vẫn chưa có credential thật);
- instance `IN_PROGRESS`, có message `waiting for node "bucket": readyWhen condition evaluated to false`.

**Tự thử 1: bỏ `readyWhen`.** Xóa 3 dòng `readyWhen:` của node `bucket` trong `labs/p3-kind/rgd.yaml`, apply lại, rồi xem instance.

**Phải thấy:** instance **`ACTIVE`, `READY=True`** dù Bucket vẫn `Synced=False`. Khi không có `readyWhen`, kro coi "đã tạo object" là xong. Vì vậy RGD của P3 bắt buộc phải có `readyWhen`. Thử xong thì trả file về như cũ: `git checkout labs/p3-kind/rgd.yaml`.

**Tự thử 2: kro tự sửa con.**

```bash
kubectl -n zdr-e4 delete deploy demo-app
kubectl -n zdr-e4 get deploy -w        # kro tạo lại trong khoảng 3 giây, UID mới
```

**Nếu RGD đứng ở `Inactive` với `cache sync timeout`:** ClusterRole `kro-zdr-p3-children` đang thiếu rule cho `kro.run` / `zdrrequests`. Đó là quyền trên chính kind mà RGD sinh ra; mode aggregation không tự cấp quyền này. Apply lại `labs/p3-kind/kro-rbac.yaml`.

## 6. Dọn theo thứ tự (con trước, cluster sau)

```bash
B=bucket.s3.aws.m.upbound.io
kubectl -n zdr-e4 delete zdrrequest demo             # kro xóa Deployment + Bucket con
kubectl -n zdr-e4 get zdrrequest,deploy,$B           # phải: No resources found
kubectl -n zdr-e3 delete $B zero-drift-p3-lab-e3     # policy không có Delete → chỉ gỡ khỏi cluster
kubectl delete rgd zdr-request
# Argo: tắt auto-sync TRƯỚC, rồi mới xóa app kèm tài nguyên của nó
kubectl -n argocd patch app zdr-lab --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
kubectl -n argocd patch app zdr-lab --type merge -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}'
kubectl -n argocd delete app zdr-lab
kubectl delete clusterproviderconfig.aws.m.upbound.io default --ignore-not-found
kubectl delete ns zdr-e3 zdr-e4 zdr-lab --ignore-not-found
kubectl get managed -A                               # phải: No resources found
kind delete cluster --name zdr-p3-lab
```

## Verify sau khi dọn

```bash
kind get clusters                                         # No kind clusters found.
docker ps -a --filter name=zdr-p3-lab --format '{{.Names}}' | wc -l   # 0
```

## Undo / gỡ hẳn

- Lab không tạo gì ngoài cluster kind. `kind delete cluster --name zdr-p3-lab` là undo đầy đủ.
- Xóa file cài đã tải: `rm -rf "$HOME/zdr-p3-lab"`.
- Lấy lại dung lượng image Docker (không bắt buộc): `docker image rm kindest/node:v1.35.8` (image vẫn có thể còn được tham chiếu bằng digest).
- Repo Helm: `helm repo remove crossplane-stable`.
- Không có tài nguyên AWS nào, nên không cần inventory AWS.

## Giới hạn: kind KHÔNG chứng minh được

- IRSA (không có OIDC của EKS), quyền IAM thật, bucket thật trên S3.
- Mạng, giới hạn pod và kích thước node của EKS.

Những điều này phải kiểm lại trong window L3 (DRF-37).
