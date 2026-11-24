# P5 isolation suite: chạy, đọc kết quả, tự kiểm (DRF-70, P5-T4.1)

> **TL;DR** · Để làm gì: một lệnh thử mọi lớp chặn (RBAC, Pod Security, Kyverno, quota, NetworkPolicy, IAM/DB)
> và ghi `acceptance.json` ·
> Trạng thái: Claude chạy trên kind 24/11 sau review Codex (Kyverno `Deny`, có Argo CD): 39 case, 33 PASS, 0 FAIL,
> 6 SKIPPED_NEEDS_EKS ·
> Liên quan: `tests/isolation/run.sh`, SPEC-P5 P5-T4.1, THREAT_MODEL §11 ·
> Mục lục: 0 Dựng kind · 1 Chạy · 2 Đọc kết quả · 3 Tự kiểm bộ test · 4 Dọn · 5 Trên EKS

Ví von: mỗi case là một **người thử cửa**. Họ ghi lại cửa nào chặn mình (`deny:pod-security`, `deny:kyverno`…),
không chỉ "bị chặn". Chặn đúng nhưng **sai cửa** cũng là FAIL: lớp mình tưởng đang canh thật ra không canh.

## 0. Dựng kind (không AWS, ~8 phút)

Giống mục 0 của `P5_L2_KIND_KYVERNO.md`, nhưng policy bật thẳng `Deny`, thêm Argo CD cho hai case T03:

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
export PATH="/r/_Dev_tools/kind:$PATH"
kind create cluster --name zdr-p5-iso \
  --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 --wait 180s
K="kubectl --context kind-zdr-p5-iso"
$K apply -f gitops/platform/tenants/ > /dev/null
LAB="$HOME/zdr-p5-iso"; mkdir -p "$LAB"
curl -fsSL -o "$LAB/kyverno-3.10.0.tgz" https://kyverno.github.io/kyverno/kyverno-3.10.0.tgz
echo "55961392dc0821eb367323f0e9585c061dd4407ef7ada921bd56ea1642c2a301  $LAB/kyverno-3.10.0.tgz" | sha256sum -c
python -I -c 'import sys,yaml,json; d=yaml.safe_load(open(sys.argv[1])); print(json.dumps(d["spec"]["source"]["helm"]["valuesObject"]))' \
  gitops/platform/apps/45-kyverno.yaml > "$LAB/values.json"
helm template kyverno "$LAB/kyverno-3.10.0.tgz" -n kyverno -f "$LAB/values.json" --no-hooks > "$LAB/kyverno.yaml"
$K create namespace kyverno
$K apply -n kyverno --server-side -f "$LAB/kyverno.yaml" > /dev/null
$K -n kyverno wait --for=condition=Available deploy --all --timeout=300s
mkdir -p "$LAB/policies"
for f in gitops/platform/policies/*.yaml; do
  python -I -c 'import sys,yaml,json; d=yaml.safe_load(open(sys.argv[1])); d["spec"]["validationActions"]=["Deny"]; print(json.dumps(d))' "$f" > "$LAB/policies/$(basename "$f")"
done
# "Available" chưa chắc webhook đã nhận kết nối: thử lại tới khi Kyverno nhận policy
until $K apply -f "$LAB/policies/"; do sleep 5; done
curl -fsSL -o "$LAB/argocd-install-v3.5.7.yaml" https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.7/manifests/install.yaml
echo "09bfbb9041b4a8503c6e4fa22cf41c403fa62be17526de353648a4551f5beb77  $LAB/argocd-install-v3.5.7.yaml" | sha256sum -c
$K create namespace argocd
$K apply -n argocd --server-side -f "$LAB/argocd-install-v3.5.7.yaml" > /dev/null
$K -n argocd wait --for=condition=Available deploy --all --timeout=300s
$K apply -f gitops/platform/apps/85-project-requests.yaml
sleep 30
```

**Phải thấy:** hai dòng `OK` (sha256), các Deployment `condition met`, ba `validatingpolicy … created` (có thể kèm một lần
`connection refused` trước đó, vòng `until` tự thử lại), `appproject.argoproj.io/zdr-requests created`.

## 1. Chạy

```bash
MODE=kind CTX=kind-zdr-p5-iso OUT="$LAB/acceptance.json" bash tests/isolation/run.sh; echo "exit=$?"
```

**Dự đoán trước:** Pod `privileged` bị lớp nào chặn? Pod gắn nhãn `tenant-b` trong `tenant-a`? Pod xin 1Gi?

**Phải thấy:** `total 39, pass 33, fail 0, skipped 6`, dòng `PASS … cleanup … verified-empty`, `RESULT: PASS`, `exit=0`.
Không cài Argo CD thì hai case T03 thành SKIPPED: `total 39, pass 31, skipped 8`. Case `cleanup` chỉ PASS khi suite
**đọc được** danh sách và thấy trống; đọc lỗi thì là `unverified`, tính FAIL.

## 2. Đọc kết quả

```bash
jq -r '.cases[] | "\(.result)\t\(.threat)\t\(.id)\t\(.observed)"' "$LAB/acceptance.json" | column -t
jq '.summary' "$LAB/acceptance.json"
```

Cột `observed` cho biết **lớp nào** trả lời: `deny:rbac`, `deny:pod-security`, `deny:kyverno:<tên policy>`, `deny:quota`,
`deny:limitrange`, `deny:argocd`. Bắt đầu bằng `error:` (webhook không gọi được, SubjectAccessReview báo `evaluationError`, mạng `refused`, Job không `Complete`…) nghĩa là
**không ai quyết định cả**, nên tính FAIL chứ không tính là bị chặn. `SKIPPED_NEEDS_EKS` = kind không có VPC CNI, IRSA, RDS, Argo CD; **không bao giờ** tính là PASS.
File không chứa tên context (trên EKS tên đó có account ID).

## 3. Tự kiểm bộ test: nó có biết FAIL không?

Một bộ test chỉ biết nói PASS thì vô dụng. Hạ một policy về `Audit` rồi chạy lại:

```bash
$K patch validatingpolicy zdr-image-digest --type merge -p '{"spec":{"validationActions":["Audit"]}}'
sleep 15
MODE=kind CTX=kind-zdr-p5-iso OUT="$LAB/neg.json" bash tests/isolation/run.sh | grep -E '^FAIL|RESULT'; echo "exit=${PIPESTATUS[0]}"
$K patch validatingpolicy zdr-image-digest --type merge -p '{"spec":{"validationActions":["Deny"]}}'
```

**Phải thấy** (Claude chạy 24/11): `FAIL` ở `T14-tag`, `T14-registry` (observed `allow`) và `T15-policies-enforced`;
`RESULT: FAIL`; `exit=1`.

Bài học Claude gặp khi viết suite: `pod … | case_admit` chạy vế phải trong **subshell**, nên kết quả (kể cả FAIL)
bị mất, suite vẫn báo PASS với 18/30 case. Sửa bằng `shopt -s lastpipe`. Bước 3 này là để bắt đúng loại lỗi đó.

Điều Claude phát hiện khi thử wrapper Job (24/11): kindnet của kind **cũng** thực thi NetworkPolicy. Một Job trong tenant-a
gọi `kubernetes.default.svc:443` bị TIMEOUT, vì sau DNAT API server nằm ở cổng 6443, mà policy chỉ mở 443. Suite vẫn để
case mạng SKIPPED trên kind, vì thứ cần chứng minh là VPC CNI trên EKS (PolicyEndpoint, standard mode), không phải kindnet.

## 4. Dọn

```bash
kind delete cluster --name zdr-p5-iso; rm -rf "$HOME/zdr-p5-iso"; unset K LAB
kind get clusters
```

**Phải thấy:** `No kind clusters found.`

## 5. Trên EKS (window L3, P5-T4.2; cần phê duyệt riêng)

Chạy **hai pha**. Ví von: muốn chứng minh cửa khóa được thì trước hết phải thấy cửa **mở** khi chưa khóa.
Nếu không, "bị chặn" có thể chỉ là do đường mạng hỏng.

**Pha control** (chưa có NetworkPolicy): tạm dừng auto-sync của app root và `25-tenants`, xóa NetworkPolicy
của hai tenant, rồi chạy:

```bash
MODE=eks CTX="$(kubectl config current-context)" NET_PHASE=control RUN_ID=P5-L3-<ngày>-01-control OUT=control.json bash tests/isolation/run.sh
```

Suite chỉ chạy 4 đường mạng: own-app, a→b, b→a, metadata. Cả 4 phải `allow`. Nếu còn NetworkPolicy, hoặc không đọc được
danh sách NetworkPolicy, suite dừng trước khi thử mạng.

**Pha enforced**: bật lại sync. Argo trả NetworkPolicy từ Git. Kyverno `Audit` → báo cáo sạch → commit `Deny`.
Sau đó chạy:

```bash
MODE=eks CTX="$(kubectl config current-context)" NET_PHASE=enforced CONTROL=control.json RUN_ID=P5-L3-<ngày>-01 OUT=acceptance.json bash tests/isolation/run.sh
```

- Không in `CTX` ra màn hình (có account ID). Suite từ chối chạy nếu `CTX` khác context hiện tại,
  vì `window.sh probe` dùng context hiện tại. Mọi dòng ghi ra đều đã lọc tên context, ARN, account ID.
- Ở `eks`, **không case nào được SKIPPED**. Probe mạng và T07 chạy bằng **Job**, vì VPC CNI không áp
  NetworkPolicy cho Pod không có owner. Mỗi Job chờ 20 s cho khoảng hở của standard mode.
  - Mạng: chỉ `TIMEOUT` mới tính là NetworkPolicy chặn. `refused` hay lỗi DNS là FAIL.
  - T07: chỉ `AccessDenied` mới tính là IAM chặn.
- Pha enforced chỉ nhận file control của **đúng** `RUN_ID-control`, cùng sandbox, và mọi case đều PASS (case `net-control-receipt`).
- Trước các case mạng, suite đợi mỗi NetworkPolicy trong Git có một PolicyEndpoint, tức node agent đã nạp.
- Kết quả của một Job chỉ được đọc khi Job đã `Complete`; Job thất bại thì là lỗi, kể cả khi log đã in `RESULT TIMEOUT`.
- Probe P4 (`platform`, `sandbox`, `cross` cho cả hai tenant) phải exit 0 và in **đủ** từng case. Thiếu case
  hay có `SKIP` đều là FAIL.
- Suite tự xóa Job, Pod, ServiceAccount và Argo app nó tạo (nhãn `app.kubernetes.io/name=zdr-isolation`),
  cùng Pod probe của `window.sh` **của chính lần chạy này** (nhãn `zdr-probe` và `rag.zero-drift.io/probe-run`,
  do suite đặt qua biến `PROBE_RUN`), đợi chúng biến mất rồi kiểm lại. Probe của lần chạy khác không bị đụng tới.
  Còn sót, hoặc không đọc được danh sách, thì exit 1.

## Bảng dự đoán (owner tự điền)

| Case | Dự đoán lớp chặn | Thực tế | Đúng? |
|---|---|---|---|
| T05-privileged | | | |
| T10-label-spoof | | | |
| T11-big (1Gi) | | | |
| T11-gpu | | | |
| T15-platform-out-of-scope | | | |
| Bước 3: suite có exit 1 không | | | |
