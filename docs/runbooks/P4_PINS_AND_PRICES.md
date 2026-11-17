# P4 pins và giá — lệnh AWS CLI chỉ đọc (DRF-40 phần B)

Runbook để **tự gõ lại** trong Git Bash. Mọi lệnh chỉ **đọc**: không tạo, không sửa,
không xóa tài nguyên AWS nào, không tốn tiền (`describe-*`, `pricing` và `sts` miễn phí).

- Spec: `.agent/specs/SPEC-P4_RAG_SANDBOX.md` §5 (P4-T1 phần B) và D2 ở §9.1.
- Kết quả lần chạy đầu: `docs/evidence/p4/P4-T1_PINS_PRICES_20261117.md`.
- Cần: phiên MFA profile `zdr-bootstrap` (runbook `P2_BOOTSTRAP_ACCESS.md` bước 4), `jq`.
- Thời gian: khoảng 10 phút.

Mỗi bước có **gõ**, **phải thấy**, **nếu sai**. Output lưu ở `$OUT` (ngoài repo).

## 0. Chuẩn bị shell

```bash
export AWS_PROFILE=zdr-bootstrap
export AWS_REGION=us-east-1
export OUT="$HOME/zdr-p4-pins"
mkdir -p "$OUT"
aws sts get-caller-identity --query Arn --output text | sed -E 's/[0-9]{12}/<ACCOUNT>/'
```

**Phải thấy:** `arn:aws:sts::<ACCOUNT>:assumed-role/zero-drift-bootstrap/...` (CLI hỏi mã MFA nếu chưa có phiên).

**Nếu sai:** lệnh đứng chờ không hỏi mã → phiên hết hạn; chạy lại bước 4 của
`P2_BOOTSTRAP_ACCESS.md`. Đừng dán dòng `Enter MFA code for arn:...` (có account ID).

## 1. Bản PostgreSQL 17 có ở `us-east-1`

```bash
aws rds describe-db-engine-versions --engine postgres \
  --query "DBEngineVersions[?starts_with(EngineVersion,'17.')].[EngineVersion,Status,DBParameterGroupFamily]" \
  --output text | tee "$OUT/1-pg17-versions.txt"
aws rds describe-db-engine-versions --engine postgres --engine-version 17 --default-only \
  --query 'DBEngineVersions[].EngineVersion' --output text | tee "$OUT/1-pg17-default.txt"
```

**Phải thấy:** danh sách `17.x  available  postgres17`. Dự đoán từ tài liệu AWS ngày 17/11:
bản mới nhất là **17.11** (có thể có `17.10-R2`). Dòng thứ hai là bản mặc định của major 17.

**Nếu sai:** lệnh thứ hai báo lỗi version → bỏ qua, chỉ cần lệnh thứ nhất.

Đặt biến cho các bước sau bằng bản mới nhất bạn thấy:

```bash
export V=17.11   # sửa nếu bước 1 cho số khác
```

## 2. `db.t4g.micro` đặt được với bản đó

```bash
aws rds describe-orderable-db-instance-options --engine postgres --engine-version "$V" \
  --db-instance-class db.t4g.micro \
  --query "OrderableDBInstanceOptions[].[DBInstanceClass,StorageType,MultiAZCapable,length(AvailabilityZones)]" \
  --output text | tee "$OUT/2-orderable.txt"
```

**Phải thấy:** ít nhất một dòng `db.t4g.micro  gp3  ...  <số AZ>`.

**Nếu sai:** output rỗng → bản `$V` không có `t4g.micro`; thử bản thấp hơn ở bước 1 và báo
lại (D2 có phương án lớp to hơn, nhưng cần owner quyết).

## 3. Mặc định `rds.force_ssl` và CA mặc định

```bash
aws rds describe-engine-default-parameters --db-parameter-group-family postgres17 \
  --query "EngineDefaults.Parameters[?ParameterName=='rds.force_ssl'].[ParameterName,ParameterValue,IsModifiable]" \
  --output text | tee "$OUT/3-force-ssl.txt"
aws rds describe-certificates --query 'DefaultCertificateForNewLaunches' --output text | tee "$OUT/3-default-ca.txt"
```

**Phải thấy:** `rds.force_ssl  1  True` (từ PostgreSQL 15 mặc định là bật). Dòng hai là tên CA
mặc định cho instance mới, dự đoán `rds-ca-rsa2048-g1`.

## 4. Checksum CA bundle của RDS (tải 1 file PEM công khai, ~40 KB)

```bash
curl -fsSL -o "$OUT/us-east-1-bundle.pem" https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem
sha256sum "$OUT/us-east-1-bundle.pem" | tee "$OUT/4-ca-sha256.txt"
grep -c 'BEGIN CERTIFICATE' "$OUT/us-east-1-bundle.pem" | tee "$OUT/4-ca-count.txt"
```

**Phải thấy:** một chuỗi sha256 và số chứng chỉ (vài cái). File này không có bí mật.

## 5. Giá từ Price List API

Hàm nhỏ để in `usagetype  đơn vị  USD  mô tả` từ JSON của Price List:

```bash
price() { jq -r '.PriceList[] | fromjson | .product.attributes.usagetype as $u
  | .terms.OnDemand[].priceDimensions[] | [$u, .unit, .pricePerUnit.USD, .description] | @tsv'; }
```

RDS instance-hour:

```bash
aws pricing get-products --region us-east-1 --service-code AmazonRDS --output json --filters \
  Type=TERM_MATCH,Field=regionCode,Value=us-east-1 \
  Type=TERM_MATCH,Field=instanceType,Value=db.t4g.micro \
  Type=TERM_MATCH,Field=databaseEngine,Value=PostgreSQL \
  Type=TERM_MATCH,Field=deploymentOption,Value=Single-AZ \
  | price | tee "$OUT/5-rds-instance.tsv"
```

**Phải thấy:** dòng `...InstanceUsage:db.t4g.micro  Hrs  0.016...` (COST_PLAN §5.2 ghi 0.016).

RDS gp3 GB-month:

```bash
aws pricing get-products --region us-east-1 --service-code AmazonRDS --output json --filters \
  Type=TERM_MATCH,Field=regionCode,Value=us-east-1 \
  Type=TERM_MATCH,Field=productFamily,Value="Database Storage" \
  Type=TERM_MATCH,Field=databaseEngine,Value=PostgreSQL \
  Type=TERM_MATCH,Field=deploymentOption,Value=Single-AZ \
  | price | grep -i gp3 | tee "$OUT/5-rds-gp3.tsv"
```

**Phải thấy:** dòng `GB-Mo  0.115...` cho gp3 storage (COST_PLAN ghi 0.115).

Secrets Manager:

```bash
aws pricing get-products --region us-east-1 --service-code AWSSecretsManager --output json --filters \
  Type=TERM_MATCH,Field=regionCode,Value=us-east-1 \
  | price | tee "$OUT/5-secrets.tsv"
```

**Phải thấy:** khoảng `0.40` USD mỗi secret-tháng và `0.05` USD mỗi 10 000 API call.

**Nếu sai:** output rỗng → bỏ `| price ...`, chạy lại với `--max-items 1` để xem tên field
thật rồi báo lại.

## 6. Gửi kết quả

```bash
for f in "$OUT"/*.txt "$OUT"/*.tsv; do echo "== $(basename "$f")"; cat "$f"; done
```

Dán toàn bộ output vào chat. Không có account ID trong các file này (đã che ở bước 0).

## 7. Phần không cần AWS (Claude đã làm, gõ lại được)

```bash
docker buildx imagetools inspect python:3.13-slim | sed -n 1,3p
docker buildx imagetools inspect pgvector/pgvector:0.8.2-pg17 | sed -n 1,3p
docker buildx imagetools inspect pgvector/pgvector:0.8.2-pg17 --format '{{json .Image}}' \
  | jq -r '."linux/amd64".config.Env[]' | grep PG_VERSION
```

**Phải thấy:** `Digest: sha256:...` khớp bảng trong file evidence; `PG_VERSION=17.10-...`.

## Dọn và undo

```bash
rm -rf "$OUT"
unset AWS_PROFILE AWS_REGION OUT V
```

Không có tài nguyên AWS nào để dọn: runbook này không tạo gì.
