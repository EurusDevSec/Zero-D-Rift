# P5 L2: Kyverno trên kind — audit, enforce, sập, gỡ (DRF-67, P5-T2.2 B)

> **TL;DR** · Để làm gì: tự thấy Kyverno chặn đúng ba luật D6, và tự thấy chuyện gì xảy ra khi Kyverno sập hoặc bị gỡ ·
> Trạng thái: Claude chạy thử 24/11; **owner chạy trọn 24/11** (cả bước 0b), mọi bước khớp "Phải thấy"
> (evidence `docs/evidence/p5/P5-T2.2_L2_KIND_KYVERNO_20261124.md`) ·
> Kết luận cần tự thấy: Kyverno chỉ canh namespace tenant; "sập êm" và "không gọi được" cho hai kết quả khác nhau ·
> Liên quan: SPEC-P5 §4 scenario 3, D6–D9; `gitops/platform/apps/45-kyverno.yaml`, `gitops/platform/policies/` ·
> Mục lục: 0 Chuẩn bị · 0b Pod tự xin token · 1 Audit · 2 Deny · 2b Tách case · 3 Sập · 4 Gỡ · 5 Dọn

Không AWS, không tốn tiền. Khoảng 45–60 phút. Làm sau lab baseline (`P5_L2_KIND_BASELINE.md`).

**Luật của lab:** trước mỗi bước, bạn **ghi dự đoán** vào bảng cuối file. Claude chỉ chép lại.

Ví von: Pod Security là **luật xây dựng** chung của cả toà nhà. Kyverno là **bảo vệ ở cửa từng căn hộ tenant**:
kiểm hàng có tem (digest), có hoá đơn (requests/limits), có đúng tên chủ hộ (nhãn tenant). Bảo vệ không đứng
ở cửa phòng kỹ thuật (namespace nền tảng), để thợ luôn vào được khi cần dỡ toà nhà.

## 0. Chuẩn bị

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
export PATH="/r/_Dev_tools/kind:$PATH"
kind create cluster --name zdr-p5-kyv \
  --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 --wait 180s
K="kubectl --context kind-zdr-p5-kyv"
$K apply -f gitops/platform/tenants/ > /dev/null

# Chart Kyverno đã pin (VERSION_MATRIX §9), kiểm sha256 trước khi dùng
LAB="$HOME/zdr-p5-kyv"; mkdir -p "$LAB/chart"
curl -fsSL -o "$LAB/chart/kyverno-3.10.0.tgz" https://kyverno.github.io/kyverno/kyverno-3.10.0.tgz
echo "55961392dc0821eb367323f0e9585c061dd4407ef7ada921bd56ea1642c2a301  $LAB/chart/kyverno-3.10.0.tgz" | sha256sum -c

# Cùng values như Argo CD dùng (lấy thẳng từ file Application), bỏ hook
python -I -c 'import sys,yaml,json; d=yaml.safe_load(open(sys.argv[1])); print(json.dumps(d["spec"]["source"]["helm"]["valuesObject"]))' \
  gitops/platform/apps/45-kyverno.yaml > "$LAB/values.json"
helm template kyverno "$LAB/chart/kyverno-3.10.0.tgz" -n kyverno -f "$LAB/values.json" --no-hooks > "$LAB/kyverno.yaml"
$K create namespace kyverno
$K apply -n kyverno --server-side -f "$LAB/kyverno.yaml" > /dev/null
$K -n kyverno wait --for=condition=Available deploy --all --timeout=300s
# "Available" chưa chắc webhook đã nhận kết nối: thử lại tới khi Kyverno nhận policy
until $K apply -f gitops/platform/policies/; do sleep 5; done
POD=labs/p5-kind/pod.sh
export IMAGE=ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox@sha256:850c77c200a798b5706ce56c7878164d4887fcf3661bbec91b2d8564df735263
```

**Phải thấy:** `55961392…: OK`; ba Deployment `condition met` (admission, background, reports; không có cleanup);
ba `validatingpolicy … created`. Có thể thấy trước đó một lần `failed calling webhook "validate-policy.kyverno.svc" …
connection refused`: Deployment đã `Available` nhưng webhook chưa nhận kết nối (Claude gặp 24/11); vòng `until` tự thử lại.

Xem webhook mà Kyverno tự sinh (SPEC yêu cầu kiểm ở đây, không chỉ trong values):

```bash
sleep 15
$K get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg -o json \
  | jq -c '.webhooks[] | {name, failurePolicy, ns: .namespaceSelector.matchExpressions, obj: .objectSelector}'
```

**Dự đoán trước:** webhook của policy có `failurePolicy` gì? Nó canh những namespace nào?

**Phải thấy:** `vpol.validate.kyverno.svc-fail` với `Fail`, chỉ namespace có nhãn `rag.zero-drift.io/tenant`.
Thêm một webhook nội bộ `protect-generation-labels` (`Fail`, mọi namespace) nhưng `objectSelector` chỉ bắt object có
nhãn `generate.kyverno.io/policy-name`; dự án không có policy generate nào nên nó không chạm gì.

## 0b. Bổ sung lab baseline: Pod tự xin chìa khoá API (P5-T2.1 B)

Hai mục còn thiếu của lab baseline, làm ở đây vì cluster này đã có image dự án:
một Pod **thật** chạy image dự án dưới `restricted`, và một lần **gọi API thật** bằng token.

Ví von: SA `default` của căn hộ đã dặn "không phát chìa khoá" (bước 1 lab baseline). Nhưng Pod vẫn
có thể **tự ghi trong đơn** "tôi cần chìa khoá", và Kubernetes nghe Pod. Vậy cầm chìa khoá rồi thì
mở được gì?

```bash
labs/p5-kind/api-call.sh tenant-a | $K create -f -
$K -n tenant-a wait --for=jsonpath='{.status.phase}'=Succeeded pod/apicall --timeout=240s
$K -n tenant-a logs apicall
$K -n tenant-a get pod apicall -o jsonpath='{.status.phase} {.spec.volumes[*].name}{"\n"}'
$K -n tenant-a delete pod apicall
```

**Phải thấy** (Claude chạy thử 24/11):
- `pod/apicall condition met`: image dự án chạy thật trong `tenant-a`, qua Pod Security `restricted`.
- Hai dòng `403 … User "system:serviceaccount:tenant-a:default" cannot list resource "pods"` và
  `… "secrets"`: có chìa khoá nhưng thẻ từ không mở được cửa nào, vì SA này không có RoleBinding.
- `Succeeded kube-api-access-…`: lần này Pod **có** volume token (khác bước 1 lab baseline).

Bài học: tắt token (D2) và RBAC (D1) là **hai lớp**. Pod tự bật lại token thì RBAC vẫn đỡ.

## 1. Audit: chỉ ghi, chưa chặn

Một Pod hợp lệ chạy thật (image dự án; app sẽ lỗi vì không có DB, không sao), một Pod sai thử bằng dry-run:

```bash
$POD good tenant-a | $K create -f -
IMAGE=busybox:1.37 $POD tagimg tenant-a | $K create --dry-run=server -f -
sleep 60
$K -n tenant-a get policyreport -o json | jq -r '.items[].results[] | "\(.policy) \(.result)"' | sort | uniq -c
```

**Dự đoán trước:** ở `Audit`, Pod `tagimg` bị chặn không? Báo cáo của Pod `good` ghi gì?

**Phải thấy:** `tagimg created (server dry run)` (Audit không chặn). Báo cáo: ba dòng `pass`, mỗi policy một dòng.
Báo cáo sạch thì mới được chuyển sang Deny.

## 2. Deny: chặn thật (§4 scenario 3)

```bash
for p in zdr-image-digest zdr-require-resources zdr-tenant-label; do
  $K patch validatingpolicy $p --type merge -p '{"spec":{"validationActions":["Deny"]}}'
done
sleep 10
$POD ok tenant-a | $K create --dry-run=server -f -
IMAGE=busybox:1.37 $POD tagimg tenant-a | $K create --dry-run=server -f -
$POD nolabel tenant-a | jq 'del(.metadata.labels["rag.zero-drift.io/tenant"])' | $K create --dry-run=server -f -
$POD wronglabel tenant-a | jq '.metadata.labels["rag.zero-drift.io/tenant"]="tenant-b"' | $K create --dry-run=server -f -
$POD noreq tenant-a | $K create --dry-run=server -f - -o jsonpath='{.spec.containers[0].resources}{"\n"}'
IMAGE=busybox:1.37 $POD tagimg zdr-platform | jq 'del(.metadata.labels)' | $K create --dry-run=server -f -
$K -n tenant-a create deployment badimg --image=busybox:1.37 --dry-run=server
```

**Dự đoán trước:**
- dòng nào qua, dòng nào bị chặn, bởi policy nào?
- `noreq` (không khai báo resources) bị Kyverno chặn không?
- Deployment `badimg` bị chặn ngay không?

**Phải thấy** (Claude chạy thử 24/11):
- `ok` → `created (server dry run)`.
- `tagimg` → `Policy zdr-image-digest failed: image must come from ghcr.io/eurusdevsec/zero-d-rift/ and be pinned by @sha256`.
- `nolabel`, `wronglabel` → `Policy zdr-tenant-label failed: Pod label rag.zero-drift.io/tenant must equal its tenant namespace`.
- `noreq` → **qua**, với `{"limits":{"memory":"192Mi"},"requests":{"cpu":"50m","memory":"96Mi"}}`: LimitRange điền
  trước (bước mutating), Kyverno thấy Pod đã đủ. `zdr-require-resources` là lưới dự phòng khi LimitRange thiếu.
- `tagimg` ở `zdr-platform` → qua: ngoài phạm vi Kyverno (namespace nền tảng không có nhãn tenant).
- `badimg` → `created`: autogen tắt, Kyverno chỉ xét Pod; Pod của nó sẽ bị chặn khi ReplicaSet tạo.

## 2b. Tách ba case còn gộp hoặc thiếu ở bước 2 (§4 scenario 3)

Ở bước 2, `busybox:1.37` sai **hai** điều cùng lúc: không có digest và sai registry. Còn `noreq` tới
Kyverno khi LimitRange đã điền resources mặc định, nên `zdr-require-resources` không có gì để bắt. Bước này tách từng điều một:

```bash
IMAGE=ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox:latest $POD tagonly tenant-a | $K create --dry-run=server -f -
IMAGE=docker.io/eurusdevsec/rag-sandbox@${IMAGE#*@} $POD otherreg tenant-a | $K create --dry-run=server -f -
$K -n tenant-a delete limitrange tenant-defaults
$POD noreq2 tenant-a | $K create --dry-run=server -f -
$K apply -f gitops/platform/tenants/quota.yaml | grep limitrange
```

**Dự đoán trước:** khi gỡ "cầu chì" LimitRange, ai chặn Pod `noreq2`?

**Phải thấy** (Claude chạy thử 24/11):
- `tagonly` (đúng registry, chỉ có tag) → `Policy zdr-image-digest failed: …`.
- `otherreg` (có digest, sai registry) → cùng policy `zdr-image-digest`.
- `limitrange "tenant-defaults" deleted`, rồi `noreq2` → `Policy zdr-require-resources failed: every container needs
  requests.cpu, requests.memory and limits.memory`: không còn LimitRange điền hộ, lưới dự phòng mới bắt.
- `limitrange/tenant-defaults created` (lắp lại cầu chì cho tenant-a) và `unchanged` (tenant-b).

Làm riêng sau lab (cluster đã dọn): chạy mục 0, vòng `for … Deny` đầu mục 2, rồi mục này, rồi mục 5.

## 3. Sập: hai kiểu cho hai kết quả (D8)

**3a. Sập "êm":** scale admission controller về 0.

```bash
$K -n kyverno scale deploy kyverno-admission-controller --replicas=0
sleep 40
$K get validatingwebhookconfigurations -o name | grep kyverno || echo "không còn webhook kyverno"
$POD ok tenant-a | $K create --dry-run=server -f -
IMAGE=busybox:1.37 $POD bad tenant-a | $K create --dry-run=server -f -
$K -n kyverno scale deploy kyverno-admission-controller --replicas=1
$K -n kyverno rollout status deploy kyverno-admission-controller; sleep 20
```

**3b. Không gọi được:** controller vẫn chạy, nhưng Service trỏ vào hư không (giống crash hay đứt mạng).

```bash
$K -n kyverno patch svc kyverno-svc --type merge -p '{"spec":{"selector":{"zdr-lab":"nothing"}}}'
sleep 5
$POD ok tenant-a | $K create --dry-run=server -f -
$POD sys kube-system | jq 'del(.metadata.labels)' | $K create --dry-run=server -f -
$K -n kyverno patch svc kyverno-svc --type json -p '[{"op":"remove","path":"/spec/selector/zdr-lab"}]'
```

**Dự đoán trước:** ở 3a và 3b, Pod hợp lệ trong `tenant-a` có được tạo không? Pod sai ở 3a thì sao?

**Phải thấy** (Claude chạy thử 24/11):
- 3a: `không còn webhook kyverno`; **cả** `ok` **lẫn** `bad` đều `created`. Khi tắt êm, Kyverno tự gỡ webhook của mình,
  nên cửa mở (fail open).
- 3b: `ok` ở `tenant-a` → `failed calling webhook "vpol.validate.kyverno.svc-fail" … connection refused` (fail closed);
  `sys` ở `kube-system` → `created`.

Nghĩa là D8 "fail closed" đúng khi Kyverno **không gọi được** (crash, mạng), **không** đúng khi ai đó **tắt êm** nó.
Tắt êm cần quyền admin nền tảng trên namespace `kyverno`; tenant chỉ có quyền đọc (D1), nên tenant không tự làm được.
Đây là giới hạn ghi vào evidence (T15).

## 4. Gỡ: policy trước, rồi Kyverno, rồi kiểm webhook

```bash
$K delete -f gitops/platform/policies/
$K -n kyverno scale deploy kyverno-admission-controller --replicas=0
sleep 40
$K delete -n kyverno -f "$LAB/kyverno.yaml" --wait=true > /dev/null
$K get validatingwebhookconfigurations,mutatingwebhookconfigurations -o name | grep kyverno || echo "không còn webhook kyverno"
```

**Dự đoán trước:** nếu bỏ dòng `scale … --replicas=0` thì sao?

**Phải thấy:** `không còn webhook kyverno`.

Claude đã thử gỡ **không** scale trước (xoá thẳng): còn sót **8** webhook configuration của Kyverno (5 validating,
3 mutating) khi controller đã mất. Đó là điều kiện dừng của window L3 ("webhook survives its controller"). Vì vậy
teardown luôn scale về 0 trước, rồi xoá, rồi chạy dòng kiểm cuối.

## 5. Dọn

```bash
kind delete cluster --name zdr-p5-kyv; rm -rf "$HOME/zdr-p5-kyv"; unset K POD LAB IMAGE
```

## Bảng dự đoán (owner tự điền, rồi gửi lại cho Claude)

| Bước | Dự đoán | Thực tế | Đúng? |
|---|---|---|---|
| 0 webhook: failurePolicy, namespace | | | |
| 0b Pod có token: gọi pods, secrets | | | |
| 1 Audit: `tagimg`; báo cáo của `good` | | | |
| 2 Deny: 7 dòng | | | |
| 2b tagonly / otherreg / noreq2 khi không có LimitRange | | | |
| 3a tắt êm: `ok`, `bad` | | | |
| 3b không gọi được: `ok`, `sys` | | | |
| 4 bỏ bước scale thì sao | | | |

Sau lab, trả lời một câu: **vì sao `noreq` không bị Kyverno chặn, và khi nào `zdr-require-resources` mới có tác dụng?**
