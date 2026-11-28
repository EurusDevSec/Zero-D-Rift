# P7 L2 — Prometheus + OpenCost trên kind (chạy lại được)

Mục đích: tự chạy lại phép thử P7-T2.1 trên máy, không đụng AWS. Kết quả gốc:
[P7-T2.1 evidence](../evidence/p7/P7-T2.1_L2_KIND_OPENCOST_20261128.md).

So sánh dễ nhớ: Prometheus là **đồng hồ điện** (ghi mỗi Pod dùng/giữ bao nhiêu CPU, RAM theo thời gian);
OpenCost là **người tính hoá đơn trong nhà** (lấy số đồng hồ × đơn giá, chia theo namespace). Hoá đơn thật vẫn là
AWS Billing (D4, D5).

**kind không chứng minh:** giá AWS, node thật, Spot, Karpenter, egress tới price list. Phần đó ở window 29/11.

## 0. Chuẩn bị (Docker Desktop phải đang chạy)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift && export PATH="/r/_Dev_tools/kind:$PATH" && docker info --format '{{.ServerVersion}}'
```

```bash
kind create cluster --name zdr-p7 --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 --wait 180s
```

```bash
K="kubectl --context kind-zdr-p7"; LAB="$HOME/zdr-p7"; mkdir -p "$LAB"; $K get nodes
```

**Phải thấy:** 1 node `Ready`, `v1.35.8`.

## 1. Tải chart và kiểm sha256 (chuỗi cung ứng)

```bash
curl -fsSL -o "$LAB/prometheus-30.0.1.tgz" https://github.com/prometheus-community/helm-charts/releases/download/prometheus-30.0.1/prometheus-30.0.1.tgz && curl -fsSL -o "$LAB/opencost-2.5.35.tgz" https://github.com/opencost/opencost-helm-chart/releases/download/opencost-2.5.35/opencost-2.5.35.tgz && sha256sum "$LAB"/*.tgz
```

**Phải thấy:**
`35c5ec2294ab22a2a1fcb14018b45d83cae8e96bf19bff86b9a669335a2836db` (opencost) và
`4f18a8da33a2b2daff2b62c1600a23dea5578deca67c0007638aced5cc55ecb6` (prometheus). Khác → **dừng**, không cài
(đây đúng là lý do bản 31.0.0 bị loại).

## 2. Lấy values y hệt Argo app trong Git rồi cài

```bash
for a in 60-prometheus 62-opencost; do python -c "import yaml; print(yaml.safe_dump(yaml.safe_load(open('gitops/platform/apps/$a.yaml'))['spec']['source']['helm']['valuesObject']))" > "$LAB/$a-values.yaml"; done
```

```bash
helm --kube-context kind-zdr-p7 install prometheus "$LAB/prometheus-30.0.1.tgz" -n prometheus-system --create-namespace -f "$LAB/60-prometheus-values.yaml" --wait --timeout 6m
```

```bash
helm --kube-context kind-zdr-p7 install opencost "$LAB/opencost-2.5.35.tgz" -n opencost --create-namespace -f "$LAB/62-opencost-values.yaml" --wait --timeout 6m
```

```bash
$K get pods -n prometheus-system; $K get pods -n opencost
```

**Phải thấy:** tất cả `Running`, `RESTARTS 0`; không có alertmanager, pushgateway.

## 3. Kiểm chứng

Image chạy đúng digest đã pin:

```bash
for ns in prometheus-system opencost; do $K get pods -n $ns -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.imageID}{"\n"}{end}{end}'; done
```

Không PV, không danh tính AWS:

```bash
$K get pvc -A; $K get sa -n opencost opencost -o jsonpath='{.metadata.annotations}{"\n"}'
```

**Phải thấy:** `No resources found`; chỉ có annotation `meta.helm.sh/*`.

Hàm hỏi Prometheus qua API server (không cần port-forward):

```bash
P=/api/v1/namespaces/prometheus-system/services/prometheus-server:80/proxy; pq(){ $K get --raw "$P/api/v1/query?query=$(python -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$1")"; echo; }
```

```bash
pq 'up{job="opencost"}'; pq 'sum(node_total_hourly_cost)'; pq 'sum by (namespace) (container_cpu_allocation)'
```

**Phải thấy:** `up` = 1; giá node khoảng 0.149 (giá mặc định của OpenCost, **không phải giá AWS**);
`prometheus-system` ≈ 0.125 core (= tổng requests).

**Đoán trước rồi chạy (active recall):** CPU thật mà `prometheus-system` dùng lớn hơn hay nhỏ hơn 0.125?

```bash
pq 'sum(rate(container_cpu_usage_seconds_total{namespace="prometheus-system",container!=""}[5m]))'
```

Bài học: OpenCost tính max(request, dùng thật) → giữ chỗ mà không dùng vẫn mất tiền.

Bảng phân bổ chi phí theo namespace:

```bash
$K get --raw "/api/v1/namespaces/opencost/services/opencost:9003/proxy/allocation/compute?window=10m&aggregate=namespace&accumulate=true" | python -m json.tool | grep -E '"name"|totalCost' | head -20
```

Kiểm tĩnh (không cần cluster):

```bash
bash gitops/check.sh | tail -5
```

## 4. Dọn (undo)

```bash
kind delete cluster --name zdr-p7 && kind get clusters
```

**Phải thấy:** không còn `zdr-p7`. Thư mục `$HOME/zdr-p7` chỉ chứa chart và values; bạn tự xoá nếu muốn.
