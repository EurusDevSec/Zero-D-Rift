# P5 pins: Kyverno và VPC CNI (DRF-64, P5-T1 phần B)

> **TL;DR** · Để làm gì: gõ lại được việc pin Kyverno và kiểm VPC CNI cho NetworkPolicy ·
> Trạng thái: chạy 22/11 (phần 1–3 Claude, phần 4 owner trong phiên MFA) ·
> Kết luận: Kyverno `v1.20.0`, chart `3.10.0`, policy kiểu `ValidatingPolicy` · Liên quan:
> SPEC-P5 §5 P5-T1 B, D6–D8; evidence `docs/evidence/p5/P5-T1_PINS_20261122.md` ·
> Mục lục: 0 Chuẩn bị · 1 Chọn release · 2 Chart và image · 3 Policy API · 4 VPC CNI · 5 Hoàn tác

Mọi lệnh chỉ **đọc**: không tạo, sửa hay xóa tài nguyên AWS hay Kubernetes, không tốn tiền.
Mỗi bước có **gõ**, **phải thấy**, **nếu sai**. Thời gian khoảng 15 phút.

## 0. Chuẩn bị shell

```bash
export OUT="$HOME/zdr-p5-pins"   # ngoài repo
mkdir -p "$OUT/dl"               # file tải về nằm riêng một thư mục
```

Cần: `gh` (đã đăng nhập), `curl`, `helm` v4, `docker` (chỉ dùng `buildx imagetools`, không cần chạy container), `jq`, `python` có PyYAML.

## 1. Chọn release Kyverno

```bash
gh api 'repos/kyverno/kyverno/releases?per_page=8' --jq '.[] | [.tag_name, .published_at[:10], .prerelease] | @tsv'
gh api repos/kyverno/website/contents/src/content/docs/docs/installation/releases.md --jq .content \
  | base64 -d | sed -n '/Patch Support Schedule/,/Other Kubernetes/p'
```

**Phải thấy:** bản ổn định mới nhất `v1.20.0` (12/11/2026). Bảng hỗ trợ ghi
`v1.20` và `Kubernetes Versions Supported: v1.34 - v1.37`, nên có 1.35 của dự án.

**Nếu sai:** có bản `v1.20.x` mới hơn thì dùng bản patch mới nhất của 1.20 và chạy lại mục 2.
Bảng không còn ghi 1.35 thì dừng, báo lại: đó là thay đổi hợp đồng.

Vì sao không dùng `v1.19.x` (bản ghi trong VERSION_MATRIX §2): Kyverno chỉ vá khoảng 3 tháng
cho release đang hỗ trợ, và bảng trên chỉ còn ghi `v1.20`.

## 2. Chart và digest image

```bash
curl -sSf https://kyverno.github.io/kyverno/index.yaml -o "$OUT/index.yaml"
grep -n -A2 'kyverno-3.10.0.tgz' "$OUT/index.yaml"; grep -n 'appVersion: v1.20.0' "$OUT/index.yaml" | head -2
curl -sSfL https://kyverno.github.io/kyverno/kyverno-3.10.0.tgz -o "$OUT/dl/kyverno-3.10.0.tgz"
sha256sum "$OUT/dl/kyverno-3.10.0.tgz"
```

**Phải thấy:** sha256 bằng đúng `digest:` của chart 3.10.0 trong `index.yaml`:
`55961392dc0821eb367323f0e9585c061dd4407ef7ada921bd56ea1642c2a301`.

**Nếu sai:** hai giá trị khác nhau thì không dùng file đó; tải lại, và nếu vẫn lệch thì dừng.

Render với `cleanupController.enabled=false` (D7) để biết image nào thực sự được dùng:

```bash
helm template kyverno "$OUT/dl/kyverno-3.10.0.tgz" -n kyverno --kube-version 1.35.0 \
  --set cleanupController.enabled=false > "$OUT/render.yaml"
grep -E '^\s+image:' "$OUT/render.yaml" | sed 's/^ *image: *//; s/"//g' | sort -u
for img in reg.kyverno.io/kyverno/kyverno reg.kyverno.io/kyverno/kyvernopre \
           reg.kyverno.io/kyverno/background-controller reg.kyverno.io/kyverno/reports-controller \
           reg.kyverno.io/kyverno/kyverno-cli ghcr.io/kyverno/readiness-checker; do
  echo "$img:v1.20.0 $(docker buildx imagetools inspect "$img:v1.20.0" --format '{{json .Manifest}}' | jq -r .digest)"
done | tee "$OUT/digests.txt"
```

**Phải thấy:** 6 image `v1.20.0` và 6 digest khớp bảng trong evidence. `cleanup-controller`
không xuất hiện vì đã tắt.

**Nếu sai:** digest khác bảng → tag đã bị đẩy lại. Không dùng tag; ghi digest mới vào evidence và báo lại.

## 3. Chọn policy API

```bash
python - "$OUT/render.yaml" <<'PY'
import sys, yaml
for d in yaml.safe_load_all(open(sys.argv[1], encoding="utf-8")):
    if d and d.get("kind") == "CustomResourceDefinition" and d["metadata"]["name"] in (
        "clusterpolicies.kyverno.io", "validatingpolicies.policies.kyverno.io",
        "namespacedvalidatingpolicies.policies.kyverno.io"):
        print(d["metadata"]["name"], [(v["name"], v["served"], v.get("deprecated", False)) for v in d["spec"]["versions"]])
PY
grep -o 'kyverno.io/v1 ClusterPolicy is deprecated[^;]*' "$OUT/render.yaml" | head -1
```

**Phải thấy:** `clusterpolicies.kyverno.io` có `v1` với `deprecated: True`, kèm cảnh báo
"ClusterPolicy is deprecated … migrate to ValidatingPolicy". `validatingpolicies.policies.kyverno.io`
có `v1` served, không deprecated.

**Kết luận:** P5 viết policy bằng `ValidatingPolicy` `policies.kyverno.io/v1` (CEL), không dùng
`ClusterPolicy`.

## 4. VPC CNI (cần phiên MFA của owner)

```bash
export AWS_PROFILE=zdr-bootstrap AWS_REGION=us-east-1
aws sts get-caller-identity --query Arn --output text | sed -E 's/[0-9]{12}/<ACCOUNT>/'
aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version 1.35 \
  --query 'addons[0].addonVersions[].[addonVersion, compatibilities[0].defaultVersion]' --output text \
  > "$OUT/4-vpccni-versions.txt"
grep -nE 'v1\.22\.4-eksbuild\.10|True' "$OUT/4-vpccni-versions.txt"
aws eks describe-addon-configuration --addon-name vpc-cni --addon-version v1.22.4-eksbuild.10 \
  --query configurationSchema --output text > "$OUT/4-vpccni-schema.json"
jq -c '.definitions as $d | {enableNetworkPolicy: $d.VpcCni.properties.enableNetworkPolicy,
  mode: $d.Env.properties.NETWORK_POLICY_ENFORCING_MODE, nodeAgent: ($d.NodeAgent.properties | keys)}' \
  "$OUT/4-vpccni-schema.json" | tee "$OUT/4-vpccni-netpol.txt"
```

Hai bẫy đã gặp ngày 22/11: danh sách dài hơn 8 dòng (đừng dùng `head`), và khóa không nằm ở
`.properties` gốc mà ở `.definitions.VpcCni` (gốc chỉ có `$ref`).

**Phải thấy:**
- Dòng đầu là `arn:aws:sts::<ACCOUNT>:assumed-role/zero-drift-bootstrap/...` (CLI hỏi mã MFA nếu chưa có phiên).
- `grep` in ra dòng `v1.22.4-eksbuild.10` và dòng có `True` (bản mặc định; ngày 22/11 là `v1.22.4-eksbuild.14`).
- `enableNetworkPolicy` là `{"format":"boolean","type":"string"}`, `mode` có enum `standard`, `strict`,
  `nodeAgent` có `enabled` và `enablePolicyEventLogs`.

**Dự đoán (tài liệu AWS, 16/11):** NetworkPolicy cần VPC CNI từ 1.21, nên `v1.22.4` đủ.

**Nếu sai:**
- Lệnh đứng chờ mà không hỏi mã → phiên hết hạn; chạy lại bước 4 của `P2_BOOTSTRAP_ACCESS.md`.
  Đừng dán dòng `Enter MFA code for arn:...` vì nó chứa account ID.
- Không có `v1.22.4-eksbuild.10`, hoặc schema không có `enableNetworkPolicy` → dừng, gửi lại
  file `4-vpccni-*.txt` để sửa SPEC trước khi viết Terraform (P5-T3).

Gửi lại 3 file `4-vpccni-*` (chúng không chứa account ID). Không gửi output của `sts`.

## 5. Hoàn tác

Không có gì để hoàn tác trên AWS. Xóa thư mục tạm khi xong:

```bash
rm -rf "$HOME/zdr-p5-pins"; unset AWS_PROFILE AWS_REGION OUT
```
