# P5 L2: phá từng lớp baseline trên kind (DRF-66, P5-T2.1 B)

> **TL;DR** · Để làm gì: tự tay phá từng lớp RBAC, Pod Security, quota, AppProject và xem lớp nào chặn ·
> Trạng thái: Claude chạy thử cả 5 bước trên kind ngày 22/11 (khớp "Phải thấy"); owner chưa làm ·
> Kết luận cần tự thấy: mỗi lần chỉ một lớp chặn, kèm đúng thông báo của lớp đó · Liên quan: SPEC-P5 §4 scenario 2–3,
> D1–D4; manifest `gitops/platform/tenants/`, `gitops/platform/apps/85-project-requests.yaml` ·
> Mục lục: 0 Chuẩn bị · 1 RBAC · 2 Pod Security · 3 Quota · 4 AppProject · 5 Dọn

Không AWS, không tốn tiền. Khoảng 60–90 phút.

**Luật của lab:** trước mỗi bước, bạn **ghi dự đoán** vào bảng ở cuối file: lớp nào chặn và thông báo
đại ý thế nào. Gõ xong mới so. Claude chỉ chép lại dự đoán và kết quả của bạn, không tự điền.

Ví von: tòa chung cư. RBAC là **thẻ từ** (vào được tầng nào), Pod Security là **luật xây dựng**
(không đục tường chịu lực), quota là **đồng hồ điện** của căn hộ, AppProject là **hộp thư**
chỉ nhận đúng mẫu đơn.

## 0. Chuẩn bị

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
export PATH="/r/_Dev_tools/kind:$PATH"
kind create cluster --name zdr-p5-lab \
  --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 --wait 180s
K="kubectl --context kind-zdr-p5-lab"
$K apply -f gitops/platform/tenants/
POD=labs/p5-kind/pod.sh
```

**Phải thấy:** namespace, 2 ResourceQuota, 2 LimitRange, 2 Role, 2 RoleBinding, 4 ServiceAccount.
Có cảnh báo `missing the kubectl.kubernetes.io/last-applied-configuration` cho SA `default`, vì
Kubernetes tự tạo SA đó trước; bỏ qua được.

**Nếu sai:**
- **Luôn dùng `$K`, không gõ `kubectl` trần.** Context mặc định trên máy vẫn trỏ tới cluster EKS
  đã xóa.
- Docker không chạy: mở Docker Desktop rồi đợi khoảng 1 phút.

## 1. RBAC: thẻ từ (D1)

Người dùng giả `dev-a` thuộc group `zdr:tenant-a:developers`. Admin "đóng vai" họ bằng
`--as` / `--as-group`; không có IAM hay access entry nào (D1).

```bash
for v in "get pods -n tenant-a" "list pods -n tenant-b" "get secrets -n tenant-a" \
         "create pods -n tenant-a" "delete deployments.apps -n tenant-a" "list namespaces"; do
  printf '%-38s %s\n' "$v" "$($K auth can-i $v --as=dev-a --as-group=zdr:tenant-a:developers 2>/dev/null)"
done
```

**Dự đoán trước:** 6 dòng, dòng nào `yes`?

**Phải thấy:** chỉ `get pods -n tenant-a` là `yes`. Không được tạo hay xóa (tenant thay đổi bằng
Git), không thấy tenant-b, không đọc Secret.

Token API **trong Pod** (bằng chứng cho D2). Pod lab này **không** tự ghi
`automountServiceAccountToken`, nên quyết định nằm ở SA `default` của namespace:

```bash
$POD notoken tenant-a | jq 'del(.spec.automountServiceAccountToken)' | $K create --dry-run=server -f - -o json \
  | jq -c '{sa: .spec.serviceAccountName, volumes: [.spec.volumes[]?.name]}'
```

**Dự đoán trước:** Pod dùng SA `default` của tenant-a. Có volume `kube-api-access-…` (token API) không?

**Phải thấy:** `{"sa":"default","volumes":[]}`. Không có volume token, nên Pod không gọi được API dù
muốn (D2: SA `default` có `automountServiceAccountToken: false`).

**Nếu sai:** thấy `kube-api-access-xxxxx` → SA `default` chưa được áp. Chạy lại bước 0 và kiểm
`$K -n tenant-a get sa default -o yaml`.

## 2. Pod Security: luật xây dựng

Mỗi lệnh chỉ đổi đúng **một** chỗ trên Pod hợp lệ. `pod.sh` **gộp lồng** phần đổi vào Pod gốc,
nên muốn bỏ seccomp phải ghi `Unconfined`, không chỉ bỏ trống. Dùng `--dry-run=server`: API
server xét duyệt đầy đủ nhưng không chạy Pod.

```bash
$POD ok          tenant-a | $K create --dry-run=server -f -
$POD privileged  tenant-a '{"securityContext":{"privileged":true,"allowPrivilegeEscalation":true}}' | $K create --dry-run=server -f -
$POD hostnet     tenant-a '{}' '{"hostNetwork":true}' | $K create --dry-run=server -f -
$POD hostpath    tenant-a '{"volumeMounts":[{"name":"h","mountPath":"/h"}]}' '{"volumes":[{"name":"h","hostPath":{"path":"/"}}]}' | $K create --dry-run=server -f -
$POD root        tenant-a '{}' '{"securityContext":{"runAsNonRoot":false,"runAsUser":0}}' | $K create --dry-run=server -f -
$POD noseccomp   tenant-a '{}' '{"securityContext":{"seccompProfile":{"type":"Unconfined"}}}' | $K create --dry-run=server -f -
```

**Dự đoán trước:** dòng nào qua? Các dòng còn lại báo lỗi chứa chữ gì?

**Phải thấy:**
- `ok` → `created (server dry run)`.
- Năm dòng kia → `violates PodSecurity "restricted:v1.35"`, mỗi dòng nêu đúng lỗi của nó:
  `privileged`, `host namespaces (hostNetwork=true)`, `restricted volume types (... "h" uses restricted volume type "hostPath")`,
  `runAsNonRoot != true` hoặc `runAsUser=0`, `seccompProfile`.

Image tham chiếu của dự án cũng phải qua. Xem trong log của P4 window: app đã chạy dưới
`restricted` trên EKS. Ở đây không cần pull lại.

## 3. Quota: đồng hồ điện (D3)

```bash
$POD noreq tenant-a | $K create --dry-run=server -f - -o jsonpath='{.spec.containers[0].resources}{"\n"}'
$POD big   tenant-a '{"resources":{"limits":{"memory":"1Gi"}}}' | $K create --dry-run=server -f -
$POD gpu   tenant-a '{"resources":{"limits":{"nvidia.com/gpu":"1"}}}' | $K create --dry-run=server -f -
for i in 1 2 3 4 5; do
  $K -n tenant-a create service clusterip s$i --tcp=80:80 2>&1 | tail -1
done
$K -n tenant-a describe resourcequota tenant-quota | grep -E 'services |pods '
```

**Dự đoán trước:**
- Pod `noreq` không khai báo resources thì bị chặn hay được gán gì?
- `big` bị lớp nào chặn, quota hay LimitRange?
- Service thứ mấy bị từ chối?

**Phải thấy:**
- `noreq` được LimitRange gán `{"limits":{"memory":"192Mi"},"requests":{"cpu":"50m","memory":"96Mi"}}`.
- `big` → `maximum memory usage per Container is 512Mi, but limit is 1Gi` (LimitRange, không phải quota).
- `gpu` → `exceeded quota: tenant-quota, requested: requests.nvidia.com/gpu=1 ... limited: ...=0`.
- Service `s1`–`s4` được tạo; `s5` → `exceeded quota ... services=1, used: services=4, limited: services=4`.

## 4. AppProject: hộp thư (D4) — cần Argo CD

Cài Argo CD v3.5.7 như P3 (kiểm sha256 trước khi apply):

```bash
LAB="$HOME/zdr-p5-lab"; mkdir -p "$LAB"
curl -fsSL -o "$LAB/argocd-install-v3.5.7.yaml" https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.7/manifests/install.yaml
echo "09bfbb9041b4a8503c6e4fa22cf41c403fa62be17526de353648a4551f5beb77  $LAB/argocd-install-v3.5.7.yaml" | sha256sum -c
$K create namespace argocd
$K apply -n argocd --server-side -f "$LAB/argocd-install-v3.5.7.yaml" > /dev/null
$K -n argocd wait --for=condition=Available deploy --all --timeout=300s
$K apply -f gitops/platform/apps/85-project-requests.yaml
```

Hai Application cố tình sai, cùng trong project `zdr-requests`:
- `bad-kind`: lấy `gitops/lab`, nơi có một Deployment, tức một kind lạ.
- `bad-ns`: đích là `zdr-platform`, tức một namespace lạ.

```bash
for spec in "bad-kind gitops/lab tenant-a" "bad-ns gitops/requests zdr-platform"; do
  set -- $spec
  cat <<EOF | $K apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: $1, namespace: argocd}
spec:
  project: zdr-requests
  source: {repoURL: https://github.com/EurusDevSec/Zero-D-Rift.git, targetRevision: main, path: $2}
  destination: {server: https://kubernetes.default.svc, namespace: $3}
  syncPolicy: {automated: {}}
EOF
done
sleep 30
for a in bad-kind bad-ns; do
  echo "== $a"; $K -n argocd get app $a -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}{.status.operationState.message}{"\n"}'
done
$K -n tenant-a get deploy
```

**Dự đoán trước:** hai lỗi này hiện ra ở lúc nào: lúc Argo đọc spec, hay lúc sync từng object?
Có Deployment nào được tạo không?

**Phải thấy** (Claude chạy thử 22/11):
- `bad-ns`: `InvalidSpecError: application destination server 'https://kubernetes.default.svc' and namespace
  'zdr-platform' do not match any of the allowed destinations in project 'zdr-requests'`. Argo chặn ngay
  khi đọc spec, chưa sync gì.
- `bad-kind`: `one or more synchronization tasks are not valid: resource apps:Deployment is not permitted
  in project zdr-requests`. Argo chặn lúc sync, từng object một.
- `No resources found in tenant-a namespace.`

**Nếu sai:**
- Dòng `bad-kind` còn trống → Argo chưa kịp đọc Git; đợi thêm rồi chạy lại vòng `for`.
- Deployment **được tạo** → dừng lại và gửi output: AppProject không chặn như SPEC giả định.

## 5. Dọn

```bash
kind delete cluster --name zdr-p5-lab; rm -rf "$HOME/zdr-p5-lab"; unset K POD LAB
```

## Bảng dự đoán (owner tự điền, rồi gửi lại cho Claude)

| Bước | Dự đoán: lớp chặn và thông báo | Thực tế | Đúng? |
|---|---|---|---|
| 1 can-i (6 dòng) | | | |
| 1 token trong Pod | | | |
| 2 privileged / hostnet / hostpath / root / noseccomp | | | |
| 3 noreq / big / gpu / service thứ 5 | | | |
| 4 bad-kind / bad-ns | | | |

Sau lab, trả lời một câu: **vì sao `big` bị LimitRange chặn chứ không phải quota, và hai lớp này khác nhau ở đâu?**
