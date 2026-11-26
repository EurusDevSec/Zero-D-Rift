# P6 L2: KEDA và worker batch trên kind — hàng đợi, Job, resume (DRF-76, P6-T2.2 B)

> **TL;DR** · Để làm gì: tự thấy KEDA biến message trong hàng đợi thành Job, worker resume từ checkpoint khi Pod chết, và message hỏng rơi vào DLQ — chạy bằng **RGD thật** `BatchTrainingJob` ·
> Trạng thái: Claude chạy hết lab ngày 25/11 (evidence `docs/evidence/p6/P6-T2.2_KIND_LAB_20261125.md`); **owner chưa chạy** ·
> Kết luận cần tự thấy: KEDA chỉ tạo Job, không tạo máy; message chỉ mất khi worker xoá nó; checkpoint là việc của app; `Ready` của request chỉ nghĩa là "đã gửi" ·
> Liên quan: SPEC-P6 §4 (kịch bản 2, 5, 6, 7), A5, D4, D5, D8, D9, D12; `labs/p6-kind/`, `gitops/platform/rgd/batch-training-job.yaml` ·
> Mục lục: 0 Chuẩn bị · 1 Cổng batch-config · 2 Một message · 3 Đang xử lý · 4 Giết Pod · 5 Xong · 6 DLQ · 7 Chỗ đặt Pod · 8 Quota · 9 Phát hiện 25/11 · 10 Dọn

Không AWS, không tốn tiền. Khoảng 45 phút.

**Luật của lab:** trước mỗi bước, bạn **ghi dự đoán** vào bảng cuối file. Claude không điền hộ.

Ví von: hàng đợi SQS là **cái bảng ghi đơn ở quầy**. KEDA là **quản lý ca**: thấy đơn trên bảng là gọi
một thợ (Job), nhưng không quá số thợ cho phép (`maxReplicaCount: 1`). Karpenter (chỉ có trên EKS) là
**bộ phận thuê thêm bàn** khi thợ tới mà hết bàn. Thợ cầm đơn lên thì đơn bị **úp mặt** một lúc
(visibility timeout), chưa bị xé. Làm xong thợ mới xé. Thợ bỏ dở thì đơn tự lật lại cho người sau. Thợ ghi
**sổ tay tiến độ** (checkpoint) vào kho (S3), nên người sau làm tiếp từ trang đang dở.

Lab dùng RGD thật, qua `labs/p6-kind/lab_rgd.py`. Script chỉ đổi những thứ kind không có, và tự kiểm để chắc
không đổi gì khác:

| Trên EKS | Trên kind | Vì sao vẫn đúng bài |
|---|---|---|
| SQS | ElasticMQ 1.7.1, cổng 9324 | Cùng API SQS. KEDA trỏ tới bằng `awsEndpoint`, worker bằng `SQS_ENDPOINT_URL` |
| S3 + bucket Crossplane | Adobe S3Mock 5.2.3 (bucket tạo sẵn); trong graph, node `bucket` là một ConfigMap cùng tên | Cùng code boto3. ConfigMap vẫn chờ `batch-config` như bucket thật |
| IRSA (KEDA và worker) | Key tĩnh của lab trong Secret `lab-aws` | Lab không chứng minh gì về IAM |
| Node do Karpenter tạo | Worker thứ hai của kind, có sẵn taint và label của pool batch | Thấy chỗ đặt Pod, không thấy máy mới sinh ra |
| Image theo digest trên GHCR | `zdr-batch:lab` build tại chỗ | Lab không bật Kyverno; digest kiểm ở L3 |

Hàng đợi của lab dùng số ngắn: visibility timeout **20 s**, heartbeat 7 s, `maxReceiveCount` 3. Trên EKS là
120 s, 40 s và 3 (D8). Cơ chế giống, chỉ khác số.

**kind không chứng minh** SQS thật, IRSA, Karpenter, EC2, Spot, Kyverno hay NetworkPolicy của VPC CNI. Những thứ
đó để cho window L3 (`P6_L3_WINDOW.md`).

## 0. Chuẩn bị

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift && export PATH="/r/_Dev_tools/kind:/r/_Dev_tools/kubectl:$PATH"
```

```bash
kind create cluster --name zdr-p6 --config labs/p6-kind/kind.yaml --image kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 --wait 180s
```

```bash
K="kubectl --context kind-zdr-p6"; B=labs/p6-kind/batch.sh; $K get nodes -L zero-drift.io/pool
```

**Phải thấy:** 1 control-plane, 2 worker; đúng một worker có `zero-drift.io/pool=batch`.

Nền tảng tenant đúng như trong Git (namespace, quota D9, RBAC, ServiceAccount `batch-train`, `batch-submit`):

```bash
for f in namespaces quota rbac serviceaccounts; do $K apply -f gitops/platform/tenants/$f.yaml; done
```

KEDA 2.21.1 với đúng các digest trong `gitops/platform/apps/50-keda.yaml` (kiểm sha256 của chart trước):

```bash
LAB="$HOME/zdr-p6"; mkdir -p "$LAB" && curl -fsSL -o "$LAB/keda-2.21.1.tgz" https://kedacore.github.io/charts/keda-2.21.1.tgz && sha256sum "$LAB/keda-2.21.1.tgz"
```

**Phải thấy:** `76b45621e48e18c9872cdc0c46295e4cbac1236fd379d06bca38ef91d8fb883e`.

```bash
python -c "import yaml; print(yaml.safe_dump(yaml.safe_load(open('gitops/platform/apps/50-keda.yaml'))['spec']['source']['helm']['valuesObject']))" > "$LAB/keda-values.yaml"
```

```bash
helm --kube-context kind-zdr-p6 install keda "$LAB/keda-2.21.1.tgz" -n keda --create-namespace -f "$LAB/keda-values.yaml" --wait --timeout 5m
```

```bash
python -c "import yaml; print(yaml.safe_dump(yaml.safe_load(open('gitops/platform/apps/30-kro.yaml'))['spec']['source']['helm']['valuesObject']))" > "$LAB/kro-values.yaml"
```

```bash
helm --kube-context kind-zdr-p6 install kro oci://registry.k8s.io/kro/charts/kro --version 0.9.4 -n kro-system --create-namespace -f "$LAB/kro-values.yaml" --wait --timeout 5m
```

```bash
$K apply -f gitops/platform/kro-rbac/clusterrole-p6.yaml
```

```bash
$K -n keda get deploy -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

**Phải thấy:** ba image KEDA đều có `@sha256:`, đúng ba digest trong app.

Image worker, backend của lab, key lab:

```bash
docker build -t zdr-batch:lab workloads/batch-training && kind load docker-image zdr-batch:lab --name zdr-p6
```

```bash
$K apply -f labs/p6-kind/backends.yaml && $K -n zdr-lab wait --for=condition=Available deploy --all --timeout=240s
```

```bash
bash $B setup && $K apply -f labs/p6-kind/lab-auth.yaml && bash $B stats
```

**Phải thấy:** `visible=0 inflight=0 dlq=0`.

## 1. RGD thật có `Active` không, và cổng `batch-config` có chặn không?

Dự đoán trước: (a) RGD có một ScaledJob trong tenant và một Job ở `zdr-platform`. Nó `Active` hay báo lỗi?
(b) Tạo request **khi chưa có** `batch-config`: kro tạo được những gì?

```bash
python labs/p6-kind/lab_rgd.py | $K apply -f - && sleep 10 && $K get rgd batch-training-job -o jsonpath='{.status.state}{"\n"}'
```

```bash
$K apply -f labs/p6-kind/request-lab-1.yaml && sleep 20 && $K -n tenant-a get cm,scaledjob; $K -n zdr-platform get jobs
```

**Phải thấy:** RGD `Active` (giả định A5 đúng). Request ở `IN_PROGRESS`, **không** có ConfigMap bucket, ScaledJob
hay Job submit: graph đứng ở `platformConfig`. Đây là cổng: không có queue thì không có gì chạy.

```bash
$K apply -f labs/p6-kind/batch-config.yaml && sleep 15 && $K -n tenant-a get batchtrainingjob lab-1 -o jsonpath='{.status.state} submit={.status.submitState} outcome={.status.outcome}{"\n"}'
```

**Phải thấy:** `ACTIVE submit=Submitted outcome=s3://zero-drift-batch-tenant-a-lab-1/runs/lab-1/1/`.
`ACTIVE` chỉ có nghĩa là **đã gửi message** (D4), chưa phải đã train xong.

## 2. Một message thì ra mấy Job, chạy ở đâu?

Dự đoán trước: có mấy Job, Pod nằm trên node nào, `stats` ra gì?

```bash
sleep 15; bash $B jobs lab-1; bash $B stats; $K -n tenant-a get pods -l app.kubernetes.io/name=batch-train -o wide
```

```bash
bash $B marks lab-1; $K -n tenant-a logs -l app.kubernetes.io/name=batch-train --tail=50 | grep TRAINING_STARTED
```

**Phải thấy:** `jobs=1`; Pod trên worker có `zero-drift.io/pool=batch`; `visible=0 inflight=1` (đơn đã úp mặt);
`TRAINING_STARTED` có `"device": "cpu"`, tên node và `run_key` `tenant-a/lab-1/1`.

## 3. Message đang xử lý thì có Job thứ hai không?

Dự đoán trước: sau 3 lần KEDA poll (30 giây), số Job là bao nhiêu? Vì sao?

```bash
sleep 30; bash $B jobs lab-1; bash $B stats
```

**Phải thấy:** vẫn `jobs=1`. `scaleOnInFlight` tính cả đơn đang úp mặt, còn `maxReplicaCount: 1` chặn thợ thứ hai.
Thấy `jobs=2` trở lên thì **dừng lab**: guard D5 hỏng (xem mục 9).

## 4. Giết Pod giữa chừng: chạy lại từ đâu?

Dự đoán trước: sau khi xoá Pod, message ở đâu? Job mới bắt đầu từ step 0 hay step khác?

```bash
bash $B marks lab-1 | grep ckpt | tail -1
```

```bash
$K -n tenant-a delete pod -l app.kubernetes.io/name=batch-train --wait=false; sleep 3; bash $B stats
```

```bash
sleep 40; bash $B stats; $K -n tenant-a logs -l app.kubernetes.io/name=batch-train --tail=100 | grep -E "RESUMED|TRAINING_STARTED"
```

**Phải thấy:**
- Ngay sau khi xoá: `inflight=1`. Pod nhận SIGTERM, ghi checkpoint rồi thoát, **không** xoá message.
- Tối đa 20 giây sau, đơn lật lại, KEDA tạo Job mới.
- Pod mới in `resumed from step N`, N > 0 (25/11: N = 67, đúng step lúc Pod bị dừng).

Job cũ `Failed` vì `backoffLimit: 0`. Đó là ý đồ: chạy lại là việc của hàng đợi, không phải của Job.

## 5. Chạy xong: message và Job ra sao?

Dự đoán trước: khi train xong, `stats` còn gì? KEDA còn tạo Job nữa không?

Lấy đúng Job thay thế (Job mới nhất). Lệnh **dừng** nếu không lấy được tên Job, trước khi `wait` (§9.3 L1):
chờ theo label sẽ chờ cả Job cũ đã `Failed` tới hết timeout. Job được KEDA gắn nhãn `scaledjob.keda.sh/name`;
nhãn `app.kubernetes.io/name=batch-train` chỉ có trên Pod.

```bash
J="$($K -n tenant-a get jobs -l scaledjob.keda.sh/name=batch-lab-1 --sort-by=.metadata.creationTimestamp -o name | tail -1)"; [[ -n "$J" ]] || echo "STOP: no Job name came back"; echo "$J"
```

```bash
[[ -n "$J" ]] && $K -n tenant-a wait --for=condition=complete "$J" --timeout=600s
```

```bash
bash $B marks lab-1 | grep -v ckpt; bash $B stats; sleep 30; bash $B jobs lab-1
```

**Phải thấy:** `SUCCEEDED`, đúng **một** `artifact/model.json`, `MESSAGE_DELETED`; `visible=0 inflight=0`; sau 30 giây
không có Job mới. `jobs=2` là 1 Job `Failed` (bước 4) và 1 Job `Complete`: mỗi loại giữ lại 1 (history limit 1).

## 6. Message hỏng: có chạy mãi không?

Dự đoán trước: request `fail-always` được chạy bao nhiêu lần, rồi message đi đâu? Có Job nào `Complete` không?

```bash
$K -n tenant-a delete batchtrainingjob lab-1 --wait=true && $K apply -f labs/p6-kind/request-lab-bad.yaml
```

```bash
sleep 120; bash $B stats; bash $B marks lab-bad; $K -n tenant-a get jobs -l scaledjob.keda.sh/name=batch-lab-bad
```

**Phải thấy:** `RECEIVED-1`, `RECEIVED-2`, `RECEIVED-3`, **không** có `SUCCEEDED`; `dlq=1`. Bằng chứng số lần chạy là
marker `RECEIVED-<n>`, không phải số Job (`failedJobsHistoryLimit: 1` chỉ giữ một).

Điều 25/11 thấy thêm: có **một Job `Complete`**. Log của nó là `NO_MESSAGE`. SQS chỉ chuyển message sang DLQ ở
**lần nhận thứ 4**, nên Job thứ 4 không nhận được gì và thoát 0. Một Job `Complete` không phải là kết quả train
(ranh giới 8); trên EKS nó là thêm một Pod ngắn.

## 7. Pod không có toleration có lên node batch không?

Dự đoán trước: Pod bình thường (không có toleration của pool batch) chạy ở đâu?

```bash
$K -n tenant-a run plain --image=zdr-batch:lab --image-pull-policy=Never --restart=Never --labels=rag.zero-drift.io/tenant=tenant-a --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"plain","image":"zdr-batch:lab","imagePullPolicy":"Never","command":["sleep","20"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"resources":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"memory":"128Mi"}}}]}}'
```

```bash
sleep 5; $K -n tenant-a get pod plain -o wide; $K -n tenant-a delete pod plain --wait=false
```

**Phải thấy:** `plain` **không** nằm trên worker batch. Taint đẩy Pod không có toleration đi chỗ khác.

## 8. Quota D9 chặn bằng tên tài nguyên nào?

Dự đoán trước: Pod xin `cpu: 1` thì sao? Job thứ 7 trong `tenant-a` thì sao?

```bash
$K -n tenant-a run big --image=zdr-batch:lab --image-pull-policy=Never --restart=Never --labels=rag.zero-drift.io/tenant=tenant-a --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"big","image":"zdr-batch:lab","imagePullPolicy":"Never","command":["sleep","5"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"resources":{"requests":{"cpu":"1","memory":"64Mi"},"limits":{"memory":"128Mi"}}}]}}'
```

**Phải thấy:** `forbidden: exceeded quota: tenant-quota, requested: requests.cpu=1, … limited: requests.cpu=900m`.

Job tạm dừng (`suspend: true`, không tạo Pod), tạo tới khi bị chặn:

```bash
for i in 1 2 3 4 5 6 7; do printf 'apiVersion: batch/v1\nkind: Job\nmetadata: {name: q%s, namespace: tenant-a}\nspec:\n  suspend: true\n  template:\n    spec:\n      restartPolicy: Never\n      containers: [{name: c, image: zdr-batch:lab}]\n' $i | $K apply -f - 2>&1 | grep -E 'created|forbidden' && true; done
```

```bash
$K -n tenant-a delete jobs q1 q2 q3 q4 q5 q6 q7 --ignore-not-found
```

**Phải thấy:** Job bị chặn với `exceeded quota: tenant-quota, requested: count/jobs.batch=1, used: count/jobs.batch=6`.
(Số Job tạo được trước đó tuỳ số Job của bước 6 còn giữ lại.) Cảnh báo PodSecurity khi tạo Job tạm dừng là bình
thường: Job không có Pod nào.

## 9. Phát hiện 25/11: kro xoá Job của KEDA

Lần chạy đầu ngày 25/11, bước 2 ra `jobs=0` dù Pod đang chạy, rồi cứ 10 giây KEDA lại tạo một Job mới; các Job
mới bị quota chặn (`requests.cpu`). Nguyên nhân, đọc từ nhãn của Job và mã KEDA `scale_jobs.go` v2.21.1:

1. KEDA **chép mọi nhãn** của ScaledJob sang Job nó tạo, kể cả `applyset.kubernetes.io/part-of` và `kro.run/owned` của kro.
2. Graph cũng có một Job (submit), nên applyset của request ghi `contains-group-kinds: …Job.batch…` cho namespace `tenant-a`.
3. kro thấy Job của KEDA mang nhãn applyset của mình mà không có trong graph, nên **prune** nó. Pod mất chủ nhưng vẫn chạy.
4. KEDA không còn thấy Job nào, nên tạo Job mới mỗi lần poll. Quota D9 là thứ chặn vòng lặp này.

Cách sửa (đã ở trong Git): ScaledJob có annotation `scaledjob.keda.sh/job-excluded-labels` liệt kê nhãn applyset và
nhãn `kro.run/*`, nên KEDA không chép chúng. `gitops/check.sh` rule 20 giữ annotation này.

Tự thử (không bắt buộc): xoá annotation trong output của `lab_rgd.py` trước khi apply, chạy lại bước 1–2, rồi đếm
Job mỗi 10 giây.

## 10. Dọn

```bash
kind delete cluster --name zdr-p6
```

**Phải thấy:** `Deleted nodes`; `docker ps -a` không còn container `zdr-p6`. Thư mục `$HOME/zdr-p6` chỉ có chart
đã tải, bạn tự xoá được.

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

- Đổi `maxReplicaCount` thành 2 trong output của `lab_rgd.py`, gửi 2 request liên tiếp. Có mấy Job? Vì sao trên EKS điều này có thể sinh thêm một máy?
- Đặt `HEARTBEAT_SECONDS` = 25 (lớn hơn visibility 20 s): worker có chịu chạy không? (`train_config` từ chối heartbeat ≥ visibility.)

## Undo

Mọi thứ nằm trong cluster kind `zdr-p6`; bước 10 xoá tất cả.
