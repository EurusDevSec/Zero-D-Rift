# P5 isolation suite: chạy, đọc kết quả, tự kiểm (DRF-70, P5-T4.1)

> **TL;DR** · Để làm gì: một lệnh thử mọi lớp chặn (RBAC, Pod Security, Kyverno, quota, NetworkPolicy, IAM/DB)
> và ghi `acceptance.json` ·
> Trạng thái: Claude chạy trên kind 24/11 (Kyverno `Deny`): 24 PASS, 0 FAIL, 7 SKIPPED_NEEDS_EKS ·
> Liên quan: `tests/isolation/run.sh`, SPEC-P5 P5-T4.1, THREAT_MODEL §11 ·
> Mục lục: 0 Dựng kind · 1 Chạy · 2 Đọc kết quả · 3 Tự kiểm bộ test · 4 Dọn · 5 Trên EKS

Ví von: mỗi case là một **người thử cửa**. Họ ghi lại cửa nào chặn mình (`deny:pod-security`, `deny:kyverno`…),
không chỉ "bị chặn". Chặn đúng nhưng **sai cửa** cũng là FAIL: lớp mình tưởng đang canh thật ra không canh.

## 0. Dựng kind (không AWS, ~5 phút)

Giống mục 0 của `P5_L2_KIND_KYVERNO.md`, nhưng policy bật thẳng `Deny`:

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
sleep 30
```

**Phải thấy:** `OK`, ba Deployment `condition met`, ba `validatingpolicy … created` (có thể kèm một lần
`connection refused` trước đó, vòng `until` tự thử lại).

## 1. Chạy

```bash
MODE=kind CTX=kind-zdr-p5-iso OUT="$LAB/acceptance.json" bash tests/isolation/run.sh; echo "exit=$?"
```

**Dự đoán trước:** Pod `privileged` bị lớp nào chặn? Pod gắn nhãn `tenant-b` trong `tenant-a`? Pod xin 1Gi?

**Phải thấy:** `total 31, pass 24, fail 0, skipped 7`, `RESULT: PASS`, `exit=0`.

## 2. Đọc kết quả

```bash
jq -r '.cases[] | "\(.result)\t\(.threat)\t\(.id)\t\(.observed)"' "$LAB/acceptance.json" | column -t
jq '.summary' "$LAB/acceptance.json"
```

Cột `observed` cho biết **lớp nào** trả lời: `deny:rbac`, `deny:pod-security`, `deny:kyverno`, `deny:quota`,
`deny:limitrange`. `SKIPPED_NEEDS_EKS` = kind không có VPC CNI, IRSA, RDS, Argo CD; **không bao giờ** tính là PASS.
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

## 4. Dọn

```bash
kind delete cluster --name zdr-p5-iso; rm -rf "$HOME/zdr-p5-iso"; unset K LAB
kind get clusters
```

**Phải thấy:** `No kind clusters found.`

## 5. Trên EKS (window L3, P5-T4.2; cần phê duyệt riêng)

```bash
MODE=eks CTX="$(kubectl config current-context)" RUN_ID=P5-L3-<ngày>-01 OUT=acceptance.json bash tests/isolation/run.sh
```

- Không in `CTX` ra màn hình (có account ID). Suite từ chối chạy nếu `CTX` khác context hiện tại,
  vì `window.sh probe` dùng context hiện tại.
- Ở `eks`, **không case nào được SKIPPED**; thêm các case mạng (Pod Python thật, chờ 20 s cho khoảng hở
  standard mode), T07 (ServiceAccount `zdr-iso-other` ngoài mẫu `rag-*`, phải `AccessDenied`) và probe P4
  (`sandbox` dương tính, `cross` âm tính cho cả hai tenant).
- Suite tự xoá Pod và ServiceAccount nó tạo. Kiểm sau khi chạy:
  `kubectl get pods,sa -A -l app.kubernetes.io/name=zdr-isolation; kubectl -n tenant-a get sa zdr-iso-other`.

## Bảng dự đoán (owner tự điền)

| Case | Dự đoán lớp chặn | Thực tế | Đúng? |
|---|---|---|---|
| T05-privileged | | | |
| T10-label-spoof | | | |
| T11-big (1Gi) | | | |
| T11-gpu | | | |
| T15-platform-out-of-scope | | | |
| Bước 3: suite có exit 1 không | | | |
