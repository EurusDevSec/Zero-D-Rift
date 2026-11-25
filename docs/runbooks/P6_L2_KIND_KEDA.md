# P6 L2: KEDA và worker batch trên kind — hàng đợi, Job, resume (DRF-76, P6-T2.2 B)

> **TL;DR** · Để làm gì: tự thấy KEDA biến message trong hàng đợi thành Job, thấy worker resume từ checkpoint khi Pod chết, và thấy message hỏng rơi vào DLQ ·
> Trạng thái: **bản kế hoạch 25/11**. Claude chạy thử khi code của P6-T2.1 và T2.2 xong, sau đó owner mới chạy ·
> Kết luận cần tự thấy: KEDA chỉ tạo Job, không tạo máy; message chỉ biến mất khi worker xoá nó; checkpoint là việc của app ·
> Liên quan: SPEC-P6 §4 (kịch bản 2, 5, 6, 7), D5, D8, D9, D12; `labs/p6-kind/`, `workloads/batch-training/` ·
> Mục lục: 0 Chuẩn bị · 1 Hàng đợi rỗng · 2 Một message · 3 Đang xử lý · 4 Giết Pod · 5 Xong · 6 DLQ · 7 Chỗ đặt Pod · 8 kro giữ ScaledJob · 9 Dọn

Không AWS, không tốn tiền. Khoảng 60 phút.

**Luật của lab:** trước mỗi bước, bạn **ghi dự đoán** vào bảng cuối file. Claude chỉ chép lại, không sửa.

Ví von: hàng đợi SQS là **cái bảng ghi đơn ở quầy**. KEDA là **quản lý ca**: cứ thấy đơn trên bảng
là gọi thêm một thợ (Job), nhưng không quá số thợ cho phép (`maxReplicaCount: 1`). Karpenter (chỉ có trên EKS)
là **bộ phận thuê thêm bàn làm việc** khi thợ tới mà không còn bàn trống. Thợ cầm đơn lên thì đơn bị **úp mặt**
một lúc (visibility timeout), chứ chưa bị xé. Làm xong thợ mới xé đơn. Thợ bỏ dở thì đơn tự lật lại cho người sau.
Thợ ghi **sổ tay tiến độ** (checkpoint) vào kho (S3), nên người sau làm tiếp từ trang đang dở.

Trên kind không có AWS. Lab thay hai thứ (D12):

| Trên EKS | Trên kind | Vì sao vẫn đúng bài |
|---|---|---|
| SQS | ElasticMQ 1.7.1 (`softwaremill/elasticmq-native`), cổng 9324 | Cùng API SQS. KEDA trỏ tới bằng `awsEndpoint`, worker trỏ tới bằng `endpoint_url` |
| S3 | MinIO | Cùng API S3, cùng code boto3 |
| IRSA | Key tĩnh của lab trong Secret `lab-aws` | Lab không chứng minh gì về IAM |
| Node do Karpenter tạo | Worker thứ hai của kind, gắn sẵn taint và label của pool batch | Thấy được chỗ đặt Pod, nhưng không thấy máy mới sinh ra |

**Lab này kiểm:** Pod Security `restricted`, quota và LimitRange của tenant, KEDA, resume từ checkpoint.
**Lab này không bật** Kyverno và NetworkPolicy, và dùng image build tại chỗ theo tag (`zdr-batch:lab`). Nếu bật
policy `zdr-image-digest` ở `Deny`, image này sẽ bị từ chối; vì vậy kiểm image theo digest và đường mạng thật để cho L3.

**kind không chứng minh** SQS thật, IRSA, Karpenter, EC2, Spot, Kyverno hay NetworkPolicy của VPC CNI. Những thứ đó để
cho window L3 (`P6_L3_WINDOW.md`). Karpenter không có provider chạy trên kind mà không phải tự build từ source
(SPEC §11 S5), nên lab này không cài Karpenter.

Hàng đợi trong lab dùng thông số ngắn để không phải chờ lâu: visibility timeout **20 s**, heartbeat 7 s,
`maxReceiveCount` 3. Trên EKS các số này là 120 s, 40 s và 3 (D8). Cơ chế giống nhau, chỉ khác số.

## 0. Chuẩn bị

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
export PATH="/r/_Dev_tools/kind:/r/_Dev_tools/kubectl:$PATH"
kind create cluster --name zdr-p6 --config labs/p6-kind/kind.yaml \
  --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 --wait 180s
K="kubectl --context kind-zdr-p6"
$K get nodes -L zero-drift.io/pool
```

**Phải thấy:** 1 control-plane và 2 worker. Đúng một worker có `zero-drift.io/pool=batch`.

```bash
# Namespace, quota (D9), RBAC, ServiceAccount của tenant. Không có NetworkPolicy (kindnet, xem bảng trên)
$K apply -f gitops/platform/tenants/namespaces.yaml -f gitops/platform/tenants/quota.yaml \
  -f gitops/platform/tenants/rbac.yaml -f gitops/platform/tenants/serviceaccounts.yaml > /dev/null

# KEDA 2.21.1, chart đã pin, kiểm sha256 trước khi dùng (P6-T1 pins)
LAB="$HOME/zdr-p6"; mkdir -p "$LAB/chart"
helm repo add kedacore https://kedacore.github.io/charts > /dev/null
helm pull kedacore/keda --version 2.21.1 -d "$LAB/chart"
sha256sum "$LAB/chart/keda-2.21.1.tgz"          # so với docs/evidence/p6/P6-T1_PINS_*.md
helm install keda "$LAB/chart/keda-2.21.1.tgz" -n keda --create-namespace --wait --timeout 5m
$K -n keda get deploy

# Hàng đợi (ElasticMQ) và kho (MinIO) của lab, cùng image worker build tại chỗ
$K apply -f labs/p6-kind/backends.yaml
$K -n zdr-lab wait --for=condition=Available deploy --all --timeout=180s
docker build -t zdr-batch:lab workloads/batch-training
kind load docker-image zdr-batch:lab --name zdr-p6
B=labs/p6-kind/batch.sh        # gói các lệnh hay dùng: send, stats, marks, jobs
```

**Phải thấy:** ba Deployment của KEDA `1/1` (operator, metrics-apiserver, admission-webhooks). Hai Deployment
`elasticmq`, `minio` trong `zdr-lab` `Available`. `$B stats` in ra `visible=0 inflight=0 dlq=0`.

## 1. Hàng đợi rỗng thì có Job không?

Dự đoán trước: queue rỗng, sau 30 giây có bao nhiêu Job trong `tenant-a`?

```bash
$K apply -f labs/p6-kind/scaledjob.yaml
sleep 30; $B jobs; $B stats
$K -n tenant-a get scaledjob batch-lab -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'; echo
```

**Phải thấy:** `jobs=0`, `visible=0`. ScaledJob `Ready=True` (KEDA đọc được queue). Ghi chú: queue rỗng thì không
có thợ nào được gọi. Đây là "scale-to-zero" của phần Pod. Phần máy là việc của Karpenter trên EKS.

## 2. Một message thì ra mấy Job, chạy trên node nào?

Dự đoán trước: 1 message thì có mấy Job, và Pod nằm trên node nào?

```bash
$B send lab-1 300        # requestId=lab-1, 300 step (khoảng 5 phút)
sleep 20; $B jobs
$K -n tenant-a get pods -o wide -l app.kubernetes.io/name=batch-train
$B marks lab-1           # các marker trong MinIO
```

**Phải thấy:** `jobs=1`. Pod nằm trên worker có `zero-drift.io/pool=batch`. `marks` có `TRAINING_STARTED` với
`device=cpu`. `$B stats` ra `visible=0 inflight=1`: đơn đã được cầm lên và đang úp mặt.

## 3. Message đang xử lý thì có Job thứ hai không?

Dự đoán trước: sau 3 lần KEDA poll (30 giây), số Job là bao nhiêu? Vì sao?

```bash
sleep 30; $B jobs; $B stats
```

**Phải thấy:** vẫn `jobs=1`. `scaleOnInFlight` tính cả đơn đang úp mặt, nhưng `maxReplicaCount: 1` chặn thợ thứ hai.
Nếu thấy `jobs=2` thì **dừng lab**: guard D5 hỏng, phải sửa trước window.

## 4. Giết Pod giữa chừng: chạy lại từ đâu?

Dự đoán trước: sau khi xoá Pod, message ở đâu? Job mới bắt đầu từ step 0 hay từ step khác?

```bash
$B marks lab-1 | grep checkpoint | tail -1      # đợi tới khi có ít nhất một checkpoint (mỗi 25 step)
$K -n tenant-a delete pod -l app.kubernetes.io/name=batch-train --wait=false
$B stats; sleep 40; $B stats; $B jobs
$K -n tenant-a logs -l app.kubernetes.io/name=batch-train --tail=5 | grep -E "resumed|TRAINING_STARTED"
```

**Phải thấy:**
- Ngay sau khi xoá Pod: `inflight=1`. Đơn vẫn úp mặt, vì Pod nhận SIGTERM, ghi checkpoint rồi thoát mà không xoá message.
- Sau tối đa 20 giây (visibility timeout của lab), đơn lật lại thành `visible=1`, rồi KEDA tạo Job mới.
- Log của Pod mới có `resumed from step N` với N > 0, đúng bằng checkpoint cuối.

Job cũ ở trạng thái `Failed` vì `backoffLimit: 0` (SPEC P6-T2.2). Đó là ý đồ: chạy lại là việc của hàng đợi, không phải của Job.

## 5. Chạy xong: message và Job ra sao?

Dự đoán trước: khi train xong, `stats` còn gì, và KEDA còn tạo Job nữa không?

```bash
# Chờ đúng Job thay thế (Job mới nhất). Chờ theo label sẽ chờ cả Job cũ đã Failed tới hết timeout.
# Job do KEDA gắn nhãn scaledjob.keda.sh/name; nhãn app.kubernetes.io/name=batch-train chỉ nằm trên Pod
J=$($K -n tenant-a get jobs -l scaledjob.keda.sh/name=batch-lab --sort-by=.metadata.creationTimestamp -o name | tail -1)
echo "$J"
$K -n tenant-a wait --for=condition=complete "$J" --timeout=600s
$B marks lab-1; $B stats; sleep 30; $B jobs
```

**Phải thấy:** `marks` có `SUCCEEDED` và đúng **một** `artifact`. `stats` ra `visible=0 inflight=0`. Không có Job mới.
Job đã xong được giữ lại 1 cái (`successfulJobsHistoryLimit: 1`).

## 6. Message hỏng: có chạy mãi không?

Dự đoán trước: một request luôn thất bại (`fail-always`) sẽ được chạy bao nhiêu lần, rồi message đi đâu?

```bash
$B send lab-bad 50 fail-always
sleep 120; $B stats; $B marks lab-bad
```

**Phải thấy:** `marks` có `RECEIVED-1`, `RECEIVED-2`, `RECEIVED-3` và **không** có `SUCCEEDED`. `stats` ra
`visible=0 inflight=0 dlq=1`. Không đếm số Job `Failed`: `failedJobsHistoryLimit: 1` chỉ giữ lại một Job, nên
đếm Job sẽ ra 1 dù đã chạy 3 lần. Bằng chứng số lần chạy là marker `RECEIVED-<n>`, ghi đúng số lần SQS đã giao message.
Ghi chú: trên EKS, mỗi lần chạy lại có thể là một máy mới. DLQ là cái chặn chi phí khi worker có lỗi.

## 7. Pod không có toleration có lên node batch không?

Dự đoán trước: một Pod bình thường (không có toleration của pool batch) sẽ chạy ở đâu?

```bash
$K -n tenant-a run plain --image=zdr-batch:lab --restart=Never --labels=rag.zero-drift.io/tenant=tenant-a \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"plain","image":"zdr-batch:lab","command":["sleep","30"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"resources":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"memory":"128Mi"}}}]}}'
$K -n tenant-a get pod plain -o wide; $K -n tenant-a delete pod plain --wait=false
```

**Phải thấy:** Pod `plain` **không** nằm trên worker batch. Taint đuổi Pod không có toleration đi chỗ khác
(SPEC kịch bản 7). Trên EKS, cùng taint này giữ node Karpenter chỉ cho batch.

## 8. kro có giữ được một ScaledJob không? (giả định A5)

Dự đoán trước: RGD có một node `ScaledJob` và một Job ở namespace khác. Nó sẽ `Active` hay báo lỗi?

```bash
helm install kro oci://registry.k8s.io/kro/charts/kro --version 0.9.4 -n kro-system --create-namespace \
  --set rbac.mode=aggregation --wait --timeout 5m
$K apply -f labs/p6-kind/rgd-spike.yaml
sleep 15; $K get rgd batch-spike -o jsonpath='{.status.state}'; echo
$K apply -f labs/p6-kind/rgd-spike-instance.yaml
sleep 20
$K -n tenant-a get scaledjob -l kro.run/instance-name=spike-1
$K -n zdr-platform get job -l kro.run/instance-name=spike-1
```

**Phải thấy:** RGD `Active`. Instance tạo được một ScaledJob trong `tenant-a` và một Job trong `zdr-platform`.
Nếu RGD báo lỗi thì đây là phát hiện thật: ghi nguyên văn lỗi, và SPEC D4 phải đổi trước khi viết RGD thật.

## 9. Dọn

```bash
kind delete cluster --name zdr-p6
```

**Phải thấy:** `Deleted nodes`. Không còn container nào của `zdr-p6` trong `docker ps -a`.

## Bảng dự đoán (owner ghi trước mỗi bước)

| Bước | Dự đoán của bạn | Kết quả thật | Khớp? |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
| 6 | | | |
| 7 | | | |
| 8 | | | |

## Tự thử (không bắt buộc)

- Đổi `maxReplicaCount` thành 2 rồi gửi 2 message. Có mấy Job? Vì sao trên EKS điều này có thể sinh thêm một máy?
- Tắt heartbeat (`HEARTBEAT_SECONDS=0`) với 300 step. Chuyện gì xảy ra sau 20 giây? Có bao nhiêu thợ cùng làm một đơn?

## Undo

Mọi thứ nằm trong cluster kind `zdr-p6`. Bước 9 xoá tất cả. Thư mục `$HOME/zdr-p6` chỉ chứa chart đã tải,
bạn tự xoá được bằng `rm -rf "$HOME/zdr-p6"`.
