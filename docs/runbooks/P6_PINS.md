# P6 pins: đọc lại digest, quyền IAM và policy Karpenter (DRF-73, P6-T1)

> **TL;DR** · Để làm gì: đọc lại các pin của P6 khi cần kiểm tra hoặc khi có bản mới ·
> Trạng thái: chạy lần đầu 25/11, kết quả ở `docs/evidence/p6/P6-T1_PINS_20261125.md` ·
> §1–§5 không AWS; §6 đọc giá AWS (chỉ đọc, cần MFA) · Không cài gì, không tốn tiền · Khoảng 10 phút ·
> Liên quan: SPEC-P6 P6-T1, §11; VERSION_MATRIX §10

Ví von: trước khi mua phụ tùng, bạn ghi **số seri** (digest) của đúng món mình kiểm. Tên hàng (tag)
có thể bị dán sang món khác; số seri thì không.

Mọi lệnh chỉ **đọc**: đọc index của Helm, manifest của image (không kéo layer), và mã nguồn trên GitHub.

## 0. Chuẩn bị

```bash
W="$HOME/zdr-p6-pins"; mkdir -p "$W"; cd "$W"
```

## 1. KEDA: chart và image

```bash
curl -fsSL https://kedacore.github.io/charts/index.yaml | grep -A12 "version: 2.21.1$" | grep -E "digest|appVersion"
```

```bash
curl -fsSLO https://kedacore.github.io/charts/keda-2.21.1.tgz && sha256sum keda-2.21.1.tgz
```

**Phải thấy:** hai giá trị sha256 giống nhau, đều là `76b45621…91d8fb883e`.

```bash
for i in keda keda-metrics-apiserver keda-admission-webhooks; do echo "$i $(docker buildx imagetools inspect ghcr.io/kedacore/$i:2.21.1 --format '{{json .Manifest.Digest}}')"; done
```

**Phải thấy:** ba digest giống bảng §1 của evidence.

## 2. Karpenter: chart và image controller

```bash
helm pull oci://public.ecr.aws/karpenter/karpenter --version 1.15.3 -d . | grep Digest
```

```bash
helm template karpenter ./karpenter-1.15.3.tgz -n karpenter --set settings.clusterName=x | grep "image:"
```

**Phải thấy:** chart `sha256:7fadb557…`; image controller đã có sẵn `@sha256:37ae6d13…` trong chart.

## 3. Image cho lab và image nền của worker

```bash
for r in docker.io/softwaremill/elasticmq-native:1.7.1 docker.io/library/python:3.12-slim docker.io/adobe/s3mock:5.2.3; do echo "$r $(docker buildx imagetools inspect $r --format '{{json .Manifest.Digest}}')"; done
```

Tag `python:3.12-slim` thay đổi theo thời gian, nên digest có thể khác lần trước. Đó là lý do pin bằng digest.
S3Mock thay MinIO (MinIO đã ngừng phát hành image), quyết định D12 ngày 25/11.

## 4. KEDA cần quyền SQS nào

```bash
gh api "repos/kedacore/keda/contents/pkg/scalers/aws_sqs_queue_scaler.go?ref=v2.21.1" --jq .content | base64 -d | grep -n "GetQueueAttributes\|ReceiveMessage\|ListQueues"
```

**Phải thấy:** chỉ có `GetQueueAttributes`. Vậy role của KEDA chỉ cần `sqs:GetQueueAttributes` trên đúng một queue.

## 5. Policy controller của Karpenter

```bash
gh api "repos/aws/karpenter-provider-aws/contents/website/content/en/docs/getting-started/getting-started-with-karpenter/cloudformation.yaml?ref=v1.15.3" --jq .content | base64 -d | grep -n '"Sid"\|"iam:'
```

**Phải thấy:** các `Sid` có chữ `InstanceProfile` mang quyền IAM ghi (`Create`, `Tag`, `AddRole`, `RemoveRole`, `Delete`).
P6 bỏ năm quyền này (D6), vì Terraform tạo sẵn instance profile.

## 6. Giá máy (AWS, chỉ đọc, cần MFA)

Ví von: xem bảng giá niêm yết (On-Demand) và lịch sử giá chợ phiên 7 ngày (Spot). Xem không mất tiền.
Chạy MFA trước: `rm -f ~/.aws/cli/cache/*.json && zdr-bootstrap`.

```bash
export AWS_PROFILE=zdr-tf AWS_REGION=us-east-1
```

```bash
for t in m6i.large m5.large c6i.large; do echo "$t $(aws pricing get-products --region us-east-1 --service-code AmazonEC2 --filters Type=TERM_MATCH,Field=instanceType,Value=$t Type=TERM_MATCH,Field=location,Value='US East (N. Virginia)' Type=TERM_MATCH,Field=operatingSystem,Value=Linux Type=TERM_MATCH,Field=tenancy,Value=Shared Type=TERM_MATCH,Field=preInstalledSw,Value=NA Type=TERM_MATCH,Field=capacitystatus,Value=Used --query 'PriceList[0]' --output text | python -c "import sys,json; d=json.load(sys.stdin); print([p['pricePerUnit']['USD'] for x in d['terms']['OnDemand'].values() for p in x['priceDimensions'].values()][0])")"; done
```

**Phải thấy:** mỗi loại một giá USD/giờ. 25/11: `0.096`, `0.096`, `0.085`.

```bash
aws ec2 describe-spot-price-history --instance-types m6i.large m5.large c6i.large --product-descriptions Linux/UNIX --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)" --query 'SpotPriceHistory[].[InstanceType,SpotPrice]' --output text | sort -k1,1 -k2n | awk '{v[$1]=v[$1]" "$2} END {for (t in v) {n=split(v[t],a," "); print t, "n="n, "min="a[1], "median="a[int((n+1)/2)], "max="a[n]}}'
```

**Phải thấy:** mỗi loại có số điểm `n`, giá thấp nhất, trung vị (median) và cao nhất, khoảng một phần ba giá
On-Demand. Khi `n` chẵn, trung vị ở đây có thể lệch 0.0001 so với evidence (lấy phần tử giữa khác nhau).
Lệnh không in account hay ARN.

## Undo

```bash
cd ~ && rm -rf "$HOME/zdr-p6-pins"
```
