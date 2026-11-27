# P6 L3 window trên EKS: đơn xin duyệt và luồng chạy (DRF-80, P6-T4.2)

> **TL;DR** · Để làm gì: chạy đường batch thật trên EKS. Message vào SQS, KEDA tạo Job, Karpenter tạo node CPU, worker train
> và checkpoint lên S3, rồi node bị thu hồi. Sau đó thử các ca lỗi, chạy cho tenant thứ hai trên On-Demand, và dọn sạch ·
> Trạng thái: **sẵn sàng chạy khi được duyệt** (25/11): `infra/p6-window/window.sh` và `gitops/tests/batch-suite.sh` đã viết (DRF-79). Chỉ chạy khi PR P6-T2.2, P6-T3, P6-T4.1 đã merge ·
> Chi phí: ước tính ≈ 2,6 USD, trần P6 là 4 USD (D14) ·
> Liên quan: SPEC-P6 §4, §5 P6-T4.2, §9.5, §10, D7, D8, D14; runbook `P5_L3_WINDOW.md` (B, E, 5a), `P4_RAG_SANDBOX.md` (C, D, J) ·
> Mục lục: 1 Đơn · 2 Bạn chọn · 3 Việc trước window · 4 Cổng T−30 · 5 Luồng window · 5b Micro-lab · 5c Kiểm bổ sung §4 · 6 Điều kiện dừng · 7 Chi phí

Mọi kết quả batch trong window này mang nhãn `CPU_SUBSTITUTE_FOR_GPU` (ADR-0009). Đây là smoke run (`official=false`),
không phải trial của H2, H3 hay H5.

Ví von: P4 và P5 xây xong căn hộ và lắp khoá. P6 mở thêm một **xưởng làm theo đơn**. Đơn đến (SQS) thì quản lý ca
(KEDA) gọi thợ (Job). Thợ không có bàn thì bộ phận thuê bàn (Karpenter) thuê một bàn mới (node EC2). Xong việc thì trả bàn.
Điều nguy hiểm nhất của window này: **bàn thuê không nằm trong sổ của Terraform**. Nếu dỡ xưởng (`terraform destroy`)
trước khi trả bàn, bàn vẫn ở đó và vẫn tính tiền. Vì vậy thứ tự dọn ở bước F là bắt buộc.

## 1. Đơn xin duyệt

Không ghi account ID, IP, ARN, queue URL hay tên node vào đây, vào chat hay vào Linear.

```
WINDOW REQUEST — P6 L3
RunId:             P6-L3-YYYYMMDD-01
Bắt đầu:           YYYY-MM-DD HH:MM Asia/Saigon (= HH:MM UTC)        ← bạn chọn
Kết thúc cứng:     bắt đầu + 5 giờ; tag ExpiresAt = giờ này, dạng UTC ...Z
Freeze-new-create: kết thúc cứng − 1,5 giờ (sau giờ này không gửi message mới)
Teardown owner:    HoangLV, có mặt suốt window; không rời máy khi cluster, RDS hoặc node Karpenter còn chạy
Người chạy:        Claude (lệnh AWS, kubectl); owner gõ micro-lab và tự merge PR "tenant-b On-Demand"
Git revision:      main = <điền ở cổng>; không sửa code trong window
Node system:       2 × m6i.large (như P5)
Node batch:        tối đa 1 node Spot + 1 node On-Demand, mỗi node 2 vCPU, chỉ m6i/m5/c6i .large (D1, D7)
Plan:              <N> to add, 0 to change, 0 to destroy; shape sha256 <điền ở cổng>
Ước tính:          ≈ 0,45 USD/giờ stack + ≈ 0,1 USD/giờ mỗi node batch đang chạy → ≈ 2,6 USD cho 5 giờ
Trần P6 (D14):     4 USD gross cho mọi window P6 và mọi lần thử lại
P6 đã tiêu:        0 (mọi lab P6 trước đó chạy trên kind)
Owner duyệt:       "Duyệt window P6-L3-YYYYMMDD-01" (gõ trong chat)
```

Chỉ apply khi đủ cả năm điều kiện: plan khớp shape hash; danh tính đúng; còn dưới trần; window đang mở; bạn đã duyệt đúng RunId.

## 2. Hai điều bạn chọn khi duyệt

**a. Giờ bắt đầu.** Cần 5 giờ liền và bạn ngồi máy suốt.

**b. Có chạy lại regression P5 không.** Mặc định là **không**: guardrail P5 vẫn bật (Kyverno ở `Deny`, NetworkPolicy, quota),
nhưng không chạy lại cả suite P5 82 ca, chỉ chạy B11 (quota) của batch suite. Chạy lại suite P5 tốn thêm khoảng 15 phút,
tức khoảng 0,1 USD. Nên chọn có nếu bạn muốn bằng chứng rằng thêm batch không làm hỏng cô lập.

## 3. Việc trước window (Claude, không AWS, không tốn tiền)

| # | Việc | Xong khi |
|---|---|---|
| P0 | PR "window: tắt hai request RAG": xoá `tenant-a-docs-qa.yaml`, `tenant-b-docs-qa.yaml` khỏi `gitops/requests/` như P5 (`6c442c7`); `disabled/` chỉ giữ request âm (check.sh luật 8). Trên main hai request này vẫn bật từ P5; P6 không cần sandbox (B1). Chọn regression P5 ở mục 2b thì không merge | **Merge trước window**, trước cổng T−30 |
| P1 | Soạn sẵn PR "window: tắt tenant-a, khoá Spot": chuyển `tenant-a-batch.yaml` xuống `disabled/`, đặt `limits.cpu: "0"` cho `batch-spot`. **Không merge trước window** | PR draft; bạn merge ở bước E1 |
| P1c | Soạn sẵn PR "window: bật tenant-b": chuyển `tenant-b-batch.yaml` từ `disabled/` lên `gitops/requests/`. Tách riêng khỏi P1 để giữa hai PR có bước kiểm | PR draft; bạn merge ở bước E3 |
| P1b | Soạn sẵn PR "window: bật tenant-a": chuyển `tenant-a-batch.yaml` từ `disabled/` lên `gitops/requests/`. Argo chỉ đọc file nằm **ngay** trong `gitops/requests/`, không đọc thư mục con | PR draft; bạn merge ở bước C1 |
| P1d | Soạn sẵn PR "window: tenant-a attempt 2": `runAttempt: 2` (300 step, `normal`) cho B06, B07, B09 | PR draft; bạn merge ở bước D1 |
| P1e | Soạn sẵn PR "window: tenant-a attempt 3 fail-always": `runAttempt: 3`, `failProfile: fail-always` cho B08 | PR draft; bạn merge ở bước D3, **sau** `window.sh purge` |
| P1f | Soạn sẵn PR "window: tắt tenant-b, mở lại Spot": chuyển `tenant-b-batch.yaml` về `disabled/`, trả `batch-spot` về `limits.cpu: "2"`. Không có request batch nào bật nên không node nào được tạo | PR draft; bạn merge ở bước F1 |
| P1g | Sau window: PR "bật lại hai request RAG" (`git revert` P0, như P5 `8692146`), chỉ khi đã `terraform destroy` và inventory CLEAN, để main về đúng trạng thái P5 | Soạn sau F5 |
| P2 | Lab kind `P6_L2_KIND_KEDA.md` đạt, có dự đoán của bạn | Có evidence `P6-T2.2_L2_KIND_KEDA_<date>.md` |
| P3 | Batch suite (`gitops/tests/batch-suite.sh`) đã merge và đã chạy trên kind: các ca cần EKS ghi `SKIPPED_NEEDS_EKS` | Evidence `P6-T4.1_BATCH_SUITE_<date>.md` có kết quả kind |
| P4 | Codex review suite và hai module Terraform | Kết quả ghi nguyên văn vào evidence |
| P5 | Bạn điền **bảng dự đoán** ở mục 5b trước window | Có dự đoán của bạn |

## 4. Cổng T−30 (chỉ đọc, có MFA)

Làm như `P4_RAG_SANDBOX.md` mục C (gồm `P2_L3_WINDOW.md` C), rồi kiểm thêm các mục riêng của P6:

| Kiểm | Phải thấy |
|---|---|
| Danh tính | `assumed-role/zero-drift-bootstrap/<SESSION>`; MFA còn ≥ 40 phút lúc apply |
| Profile | mọi lệnh `terraform` (plan, apply, destroy) và lệnh `aws` của script chạy với `AWS_PROFILE=zdr-tf`. `zdr-tf` lấy phiên MFA của `zdr-bootstrap` qua `credential_process`. Với `AWS_PROFILE=zdr-bootstrap`, Terraform dừng ngay vì không tự hỏi được mã MFA (`AssumeRoleTokenProvider session option not set`). Không đặt profile thì CLI dùng IAM user mặc định: plan đó không hợp lệ, chạy lại (window 26/11) |
| `inventory.sh` | `RESULT: CLEAN`; dòng mới của P6 (instance có tag Karpenter, launch template, Spot request, queue) đều `0` |
| Quota Standard On-Demand | ≥ 6 vCPU (4 system + 2 batch On-Demand). Đọc được 8 ngày 25/11 |
| Quota Standard Spot | ≥ 2 vCPU. Chưa đọc từ 28/09 (lúc đó là 5) |
| Spot service-linked role | `aws iam get-role --role-name AWSServiceRoleForEC2Spot` có hoặc không. Không có thì dừng và hỏi bạn: tạo role này là thay đổi account (A11). Đã tạo 26/11 theo quyết định của bạn và giữ lại có chủ đích, nên từ window sau phải thấy role này có |
| Giá | đọc lại On-Demand `m6i.large`, `m5.large`, `c6i.large` và giá Spot 7 ngày qua; lệch > 20% so với §10 thì tính lại ước tính |
| `run.tfvars` | `run_id`, `expires_at` theo đơn; `enable_rag_platform = true`; `enable_batch_platform = true`; `system_node_desired_size = 2`; **không** đè `vpc_cidr` |
| `bash gitops/check.sh` | PASS, gồm luật P6: tối đa một `BatchTrainingJob` bật; NodePool có `limits` và `expireAfter` |
| `terraform plan` + `plan_assert.sh` (`ADMIN_WINDOW=1 P4_WINDOW=1 P6_WINDOW=1`) | PASS; ghi số resource và shape sha256 vào đơn |
| `rag_iam_check.sh tfplan` và `batch_iam_check.sh tfplan` | PASS |

## 5. Luồng window

```
B Dựng (1 g)        apply → smoke P2 → Argo CD → platform (P4, P5) → KEDA → Karpenter → annotate (IRSA)
                    → zdr-batch: EC2NodeClass Ready, NodePool → hai request batch đều tắt → batch-config → purge, đợi 60 s
C Một run (1 g)     merge PR P1b (bật tenant-a) → B02, B03 → node Spot lên → B04 → B05 node bị thu hồi
                    → B01 (queue rỗng, scaler đã chứng minh chạy: 0 Job mới, 0 node)
D Sự cố (1 g)       B06 xoá Pod → B07 xoá NodeClaim → B08 DLQ → B09–B14 ca âm
E Tenant-b (0,5 g)  merge P1 (tắt tenant-a, Spot 0) → kiểm scaler cũ hết, queue rỗng, limit Spot = 0
                    → merge P1c (bật tenant-b) → run trên On-Demand → micro-lab
F Dọn (0,5 g)       tắt request + cleanup → dừng root và zdr-batch → xoá 2 NodePool → 0 NodeClaim + 0 instance trên AWS
                    (cả hai lệnh đọc được) → EC2NodeClass → app zdr-batch → Karpenter, KEDA → P5 E → P4 J → destroy → inventory
```

**Làm mới MFA:** như `P5_L3_WINDOW.md` mục 5. Chỉ làm mới khi Claude báo **không còn lệnh nào đang chạy**.
Trước một bước dài (một run khoảng 8 phút, `terraform destroy` khoảng 15 phút), làm mới trước nếu phiên còn dưới 30 phút.

**B. Dựng.**

1. Làm `P4_RAG_SANDBOX.md` từ mục D tới khi các app platform `Synced Healthy`. Hai request RAG giữ **tắt** (PR P0 đã merge): P6 không cần sandbox,
   và quota tenant còn chỗ cho cả hai nếu bạn chọn regression P5 ở mục 2b.
   Rồi chạy **riêng** bước `annotate` của P4, dù không chạy `db-init` hay request RAG nào:
   ```bash
   bash infra/p4-window/window.sh annotate
   ```
   **Phải thấy:** 3 dòng `OK`; `status` báo `provider pod has AWS_ROLE_ARN yes`. Bước này gắn IRSA cho provider S3 của Crossplane.
   Thiếu nó thì `Bucket` của BatchTrainingJob không bao giờ `Ready`, graph đứng ở `IN_PROGRESS` và không gửi message nào.
   Trong `P4_RAG_SANDBOX.md`, `annotate` nằm sau bước bật request nên dễ bị bỏ qua: window 26/11 mất khoảng 12 phút vì thiếu bước này.
2. **Không đợi** `zdr-keda` và `zdr-karpenter` Healthy trước khi gắn IRSA. Karpenter v1.15.3 thoát ngay khi lần gọi EC2 lúc khởi động
   thất bại, nên khi chưa có IRSA, Pod của nó restart liên tục và app không bao giờ Healthy (Codex P6 R2). Chỉ đợi Deployment và ServiceAccount
   **tồn tại**:
   ```bash
   kubectl -n keda get deploy/keda-operator sa/keda-operator -o name && kubectl -n karpenter get deploy/karpenter sa/karpenter -o name
   ```
   **Phải thấy:** đủ 4 dòng `deployment.apps/...` và `serviceaccount/...`. Thiếu dòng nào thì đợi Argo tạo, chạy lại lệnh.
   Rồi chạy **ngay** `bash infra/p6-window/window.sh annotate`: gắn IRSA cho `keda-operator`, `karpenter`, `batch-submit`, `batch-train` của hai tenant
   rồi restart KEDA và Karpenter. Thiếu bước này thì Karpenter không gọi được EC2, nên `EC2NodeClass` không bao giờ `Ready` (Codex P6 R1).
   Sau annotate mới đợi `zdr-keda` và `zdr-karpenter` `Synced Healthy`. Pod Karpenter nằm trên node system
   (`kubectl -n karpenter get pods -o wide` cho thấy tên node thuộc node group, không phải node do Karpenter tạo; chỉ ghi "system", không ghi tên node).
3. Sau đó: app `zdr-batch` `Synced Healthy`; `kubectl get nodepools` có `batch-spot` (weight 100) và `batch-ondemand` (weight 10);
   `kubectl get ec2nodeclass batch` `Ready=True`. Rồi đặt run ID của đơn window (dùng tiếp cho suite ở C) và chạy batch-config,
   như `window.sh platform-config` ở P4:
   ```bash
   export RUN_ID=P6-L3-YYYYMMDD-NN EXPIRES_AT=YYYY-MM-DDTHH:MM:SSZ
   bash infra/p6-window/window.sh batch-config
   ```
   Lệnh này tạo ConfigMap `batch-config` trong `zdr-platform` từ output Terraform. Annotation và ConfigMap chứa account ID nên không nằm trong Git;
   không in giá trị ra chat.
   Kiểm (chỉ in tên key):
   ```bash
   kubectl -n zdr-platform get cm batch-config -o go-template='{{range $k, $v := .data}}{{$k}} {{end}}' && echo
   ```
   **Phải thấy:** `expiresAt queueName queueUrl region runId`. Thiếu ConfigMap này thì graph đứng ở `waiting for external reference "platformConfig"`
   và không tạo ScaledJob hay Job submit nào: đó là cổng, không phải lỗi.
4. Hai request batch vẫn nằm trong `gitops/requests/disabled/`: `kubectl get batchtrainingjob -A` ra `No resources found`,
   chưa có ScaledJob nào, nên chưa có Job submit nào gửi message.
5. `bash infra/p6-window/window.sh purge`: purge queue và DLQ, rồi đợi **60 giây sau lần purge thành công cuối cùng**.
   `PurgeQueue` trả thành công trước khi SQS xoá xong (việc xoá kéo dài tới 60 giây). Bật request sớm hơn thì purge có thể
   xoá luôn message đầu tiên. Một message cũ sót lại sẽ dựng máy ngay khi có ScaledJob. Đợi đủ 60 giây mới sang C1.

B01 (queue rỗng thì 0 Job, 0 node) **không** chạy ở đây. Lúc này chưa có ScaledJob, nên "0 Job" vẫn đúng kể cả khi scaler
hỏng hoặc thiếu hẳn. B01 chạy ở C6, sau khi scaler đã tạo được một Job thật.

Suite ghi mọi ca vào một file ngoài repo. Đặt biến một lần cho cả window:

```bash
export MODE=eks CTX="$(kubectl config current-context)" OUT="$HOME/zdr-p6/batch-acceptance-$RUN_ID.json"; S="bash gitops/tests/batch-suite.sh"
```

**C. Một run hoàn chỉnh (tenant-a, Spot).**

1. Bạn merge PR P1b (bật tenant-a). Ghi giờ merge: đây là mốc bắt đầu của bảng thời gian smoke.
2. Đợi Argo kéo commit merge về, rồi mới chạy suite. Lệnh này phải in revision đúng bằng commit merge, và `attempt` đúng bằng
   `runAttempt` của PR vừa merge:
   ```bash
   kubectl -n argocd get app zdr-requests -o jsonpath='{.status.sync.revision}{"\n"}'; kubectl -n tenant-a get batchtrainingjob smoke-1 -o jsonpath='attempt={.spec.runAttempt}{"\n"}'
   ```
   Chưa khớp thì đợi 30 giây rồi chạy lại (có thể ép `kubectl -n argocd annotate app zdr-requests argocd.argoproj.io/refresh=hard --overwrite`).
   Chạy suite sớm hơn thì B02 ra `READ_FAILED` (window 26/11). Làm y như vậy sau mỗi PR request ở D1, D3 và E3 (E3: namespace `tenant-b`).
   Khi đã khớp: `$S run tenant-a smoke-1 spot`. Lệnh này chạy B02, B03, B14, B04 và B05 theo thứ tự, tự chờ (tối đa khoảng 45 phút).
   **B02, B03**: 1 Job cho run key này; sau 3 lần poll vẫn 1 Job.
3. Theo dõi: Pod `Pending` → NodeClaim `Launched` → `Registered` → `Initialized` → Pod `Running`.
   Ghi các mốc thời gian vào bảng smoke: sync, message gửi, Job tạo, NodeClaim tạo, instance running, node Ready, image pulled, `TRAINING_STARTED`.
4. **B04**, khi Pod còn đang chạy: suite đọc Pod → `spec.nodeName` → hai nhãn của Node (`karpenter.sh/capacity-type`,
   `node.kubernetes.io/instance-type`) và lưu kèm run key. Worker không tự ghi capacity type: Downward API không cho Pod đọc nhãn Node.
   Sau khi xong: Job của attempt `Complete`; dưới prefix của attempt này có `TRAINING_STARTED` (`device=cpu`), checkpoint,
   `SUCCEEDED`, đúng một artifact và `MESSAGE_DELETED`, tất cả ghi sau marker `submit-started` (ghi **trước** khi gửi message);
   sau một visibility timeout queue `visible=0 inflight=0`. Đủ file mà thiếu `MESSAGE_DELETED` là `FAIL`: message chưa bị xoá
   sẽ quay lại. Phải thấy capacity type `spot`.
5. **B05**: sau khi Job xong, đo **scale-down time** từ lúc Job hoàn tất tới lúc Node biến mất khỏi Kubernetes,
   rồi tới lúc instance `terminated` trên AWS (đếm theo tag, không ghi instance ID). `consolidateAfter: 60s` nên kỳ vọng vài phút.
6. **B01** (`$S b01 tenant-a smoke-1`): ScaledJob `Ready` và vừa tạo được Job ở bước 2, tức scaler đọc được queue. Queue `visible=0 inflight=0` qua ít nhất
   3 lần poll. Phải thấy 0 Job mới, 0 NodeClaim, 0 instance có tag Karpenter. Thiếu ScaledJob là `FAIL`, không phải "0".

**D. Sự cố và ca âm.**

1. Bạn merge PR P1d (attempt 2), rồi `$S resume tenant-a smoke-1`. Lệnh này chạy B06, B07 rồi B09.
   **B06**: sau checkpoint đầu, suite xoá Pod. Phải thấy message lật lại sau ≤ 120 giây, Job mới, `resumed from step N` với N > 0.
2. **B07** (cùng lệnh): lặp lại nhưng xoá **NodeClaim** (`kubectl delete nodeclaim <tên>`; chỉ ghi "đã xoá NodeClaim"). Karpenter drain node, Pod nhận SIGTERM và ghi checkpoint,
   rồi Karpenter tạo NodeClaim mới cho Pod tiếp theo. Ghi nhãn "simulated disruption" (D11). Đây không phải Spot interruption thật.
   **B09** (cùng lệnh): khi attempt 2 đang train, suite gửi thêm một message của request `b09-extra`. Phải thấy vẫn 1 Pod, 1 NodeClaim.
   Message thừa này lạ với mọi worker: bị nhả 3 lần rồi vào DLQ. Vì vậy bước 3 purge trước.
3. Khi attempt 2 xong: `bash infra/p6-window/window.sh purge`, rồi bạn merge PR P1e (attempt 3 `fail-always`), rồi `$S dlq tenant-a smoke-1`.
   **B08**: request `fail-always`. Phải thấy marker `RECEIVED-1`, `RECEIVED-2`, `RECEIVED-3` của attempt này,
   message của attempt nằm trong DLQ, không có `SUCCEEDED`, và node bị thu hồi sau đó. Không đếm số Job `Failed`:
   `failedJobsHistoryLimit: 1` chỉ giữ một Job. Nếu Job hỏng **trước** khi nhận message (không có `RECEIVED-1`),
   DLQ không chặn được: đó là điều kiện dừng H5.
4. Khi không còn Pod batch nào đang chạy: `B12_REQUEST=smoke-1 $S negatives` (B10–B13; B14 đã chạy ở C2 khi node batch còn sống).
   Kết thúc: `$S report` phải in `RESULT: PASS`.
   - B09: message thứ hai khi đang chạy, không có node thứ hai.
   - B10: Pod không có toleration không lên node batch.
   - B11: hai lần từ chối riêng cho `pods` và `count/jobs.batch` ở mức D9, mỗi thông báo phải nêu đúng tên quota đó,
     cộng một Pod vượt `requests.cpu`. Lỗi chung chung là `FAIL`.
   - B12: dùng artifact có thật trong bucket của tenant-a (từ run ở C). Trước tiên **cả hai** Pod probe in
     `caller_role_match=true` (STS GetCallerIdentity, chỉ in kết quả so khớp, không in ARN). Rồi Pod probe với
     ServiceAccount `tenant-a/batch-train` đọc được (đối chứng), còn Pod probe với `tenant-b/batch-train` phải nhận đúng
     `AccessDenied` khi get và put cùng key. Hai Pod probe đặt `automountServiceAccountToken: false`.
     Caller không khớp, `NoSuchBucket`, timeout hay mã khác là `FAIL`. ServiceAccount `batch-train` do platform tạo sẵn cho cả hai tenant,
     nên tenant-b có danh tính thật dù request của nó đang tắt.
   - B13: KEDA chỉ đọc được thuộc tính queue; Karpenter không có quyền IAM write.
   - B14: Pod batch không lấy được credential của node qua IMDS.

**E. Tenant-b trên On-Demand.**

1. Bạn merge PR P1 (tắt tenant-a, `batch-spot` `limits.cpu: "0"`). Chưa bật tenant-b.
2. Kiểm trước khi bật tenant-b. Cả năm dòng phải đúng; một dòng sai hoặc lệnh lỗi thì chưa sang bước 3:
   ```bash
   cnt(){ local o; o=$("$@") || { echo READ_FAILED; return; }; printf '%s' "$o" | grep -c .; }
   echo "scaledjob_a: $(cnt kubectl -n tenant-a get scaledjob -o name)"
   echo "jobs_a: $(cnt kubectl -n tenant-a get jobs -l scaledjob.keda.sh/name -o name)"
   echo "spot_limit: $(kubectl get nodepool batch-spot -o jsonpath='{.spec.limits.cpu}' || echo READ_FAILED)"
   echo "nodeclaims: $(cnt kubectl get nodeclaims -o name)"
   bash gitops/tests/batch-suite.sh stats   # cần MODE, CTX như trên
   ```
   **Phải thấy:** `scaledjob_a: 0`, `jobs_a: 0`, `spot_limit: 0`, `nodeclaims: 0` và `visible=0 inflight=0`.
   `READ_FAILED` không phải `0`: đọc lại. Lý do: nếu ScaledJob của tenant-a còn sống, worker của nó có thể
   nhận message của tenant-b rồi trả lại, và lần nhận đó vẫn bị đếm vào `maxReceiveCount` (D3). Nếu limit Spot chưa về 0,
   Karpenter có thể dựng node Spot cho run lẽ ra phải chạy On-Demand.
3. Bạn merge PR P1c (bật tenant-b). Karpenter chỉ còn `batch-ondemand`.
4. Run của tenant-b chạy xong: `OUT="$HOME/zdr-p6/batch-acceptance-$RUN_ID-tenant-b.json" $S run tenant-b smoke-1 on-demand`
   (file riêng, để run này không ghi đè B02–B05 của tenant-a). Suite đọc nhãn Node của Pod thật và thấy capacity type `on-demand`. Run này mang nhãn
   `on-demand`, không bao giờ được tính là Spot (biên âm 7).
5. Micro-lab ở mục 5b.

**F. Dọn** (từ giờ freeze, hoặc sớm hơn nếu đã xong). Theo đúng SPEC §9.5:

1. Tắt mọi `BatchTrainingJob` qua PR (bạn merge P1f; tenant-a đã tắt ở E1), chạy `bash infra/p6-window/window.sh cleanup <tenant> smoke-1` cho từng tenant đã bật, đợi ScaledJob và Job về 0.
2. Dừng sync của `zdr-root` **trước**, rồi của `zdr-batch`. Cả hai có `selfHeal`: xoá app con khi root còn chạy thì root tạo lại app đó
   (cái bẫy đã thấy ở P5 mục 5a), và xoá NodePool khi `zdr-batch` còn chạy thì app tạo lại NodePool. App `zdr-batch` giữ cả `EC2NodeClass`,
   nên **không** xoá app ở bước này (cascade sẽ xoá `EC2NodeClass` cùng lúc với NodePool). Chỉ xoá hai NodePool. Controller Karpenter
   vẫn chạy suốt bước này, vì chính nó xoá NodeClaim và instance:
   ```bash
   kubectl -n argocd patch app zdr-root --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
   kubectl -n argocd patch app zdr-batch --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
   kubectl delete nodepool batch-spot batch-ondemand --timeout=600s
   ```
   Đếm bằng lệnh có guard. Lệnh đọc lỗi thì in `READ_FAILED`, không bao giờ in `0`. Bộ lọc gồm mọi trạng thái trừ `terminated`:
   instance `stopped` vẫn tính tiền volume.
   ```bash
   nc=$(kubectl get nodeclaims -o name) && echo "nodeclaims: $(printf '%s' "$nc" | grep -c .)" || echo "nodeclaims: READ_FAILED"
   ni=$(aws ec2 describe-instances --filters Name=tag-key,Values=karpenter.sh/nodepool Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down --query 'length(Reservations[].Instances[])' --output text) && echo "karpenter_instances: $ni" || echo "karpenter_instances: READ_FAILED"
   ```
   Chỉ sang bước 3 khi **cả hai dòng** đều đọc được và đều ra `0`. Có `READ_FAILED` (ví dụ hết MFA) thì làm mới MFA rồi đếm lại.
3. Xoá `EC2NodeClass`, rồi app `zdr-batch` có cascade (còn `ClusterTriggerAuthentication`), rồi app `zdr-karpenter` và `zdr-keda`
   (root đã dừng ở bước 2, nên app không bị tạo lại):
   ```bash
   kubectl delete ec2nodeclass batch --timeout=300s
   kubectl -n argocd patch app zdr-batch --type merge -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}'
   kubectl -n argocd delete app zdr-batch --timeout=300s
   ```
4. Làm `P5_L3_WINDOW.md` E2 (gỡ Kyverno, đếm webhook bằng lệnh có guard), rồi `P4_RAG_SANDBOX.md` J bước 3–4: gỡ các app còn lại, gỡ Argo CD, `terraform destroy`.
   G2 đã xảy ra ở cả hai window (25/11 và 26/11): gỡ app Kyverno xong vẫn còn 8 webhook mồ côi. Xoá theo nhãn như G2 hướng dẫn,
   đếm lại ra `0` rồi mới đi tiếp, và vẫn ghi thành lỗi trong evidence:
   ```bash
   kubectl delete validatingwebhookconfigurations,mutatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno
   ```
5. `inventory.sh` phải ra `RESULT: CLEAN`, gồm các dòng P6 bằng 0. Inventory trễ vào ngày hôm sau (P6-T4.3).

### 5b. Micro-lab: bạn tự gõ, theo một NodeClaim từ lúc sinh tới lúc mất

Gõ ở bước E4, khi run của tenant-b đang chạy. Điền cột dự đoán **trước** window. Chỉ đọc tên NodeClaim trên màn hình,
không dán tên node hay instance ID vào chat.

| # | Lệnh | Hỏi | Dự đoán của bạn | Phải thấy |
|---|---|---|---|---|
| M1 | `kubectl get nodeclaims -w` (Ctrl+C khi thấy `True` ở cột READY) | NodeClaim đi qua những trạng thái nào? | | `Launched` → `Registered` → `Initialized`/READY `True` |
| M2 | `kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type,zero-drift.io/pool` | Node mới là Spot hay On-Demand, loại máy nào? | | `on-demand`, một trong `m6i/m5/c6i.large`, pool `batch` |
| M3 | `kubectl describe nodeclaim <tên> \| grep -A3 Taints` | Vì sao Pod thường không lên được node này? | | taint `zero-drift.io/batch=true:NoSchedule` |
| M4 | `kubectl -n tenant-b get pods -o wide -l app.kubernetes.io/name=batch-train` | Pod training nằm trên node nào? | | đúng node ở M2 |
| M5 | `kubectl get nodeclaims -w` sau khi Job xong (đợi tối đa 5 phút) | Ai xoá node, và sau bao lâu? | | Karpenter xoá vì node rỗng (`WhenEmpty`), sau `consolidateAfter: 60s` và thời gian drain |

### 5c. Kiểm bổ sung cho SPEC §4 (Claude chạy, chỉ đọc)

Suite không chấm sáu dòng dưới đây của SPEC §4, nhưng audit T4.3 cần bằng chứng L3 cho từng dòng (SPEC §8).
Mọi lệnh chỉ in khoá, số đếm hoặc trạng thái, không in ID, ARN hay tên node. Lệnh đọc lỗi thì in `READ_FAILED`, không bao giờ in `0`.
Đặt một lần:

```bash
b=zero-drift-batch-tenant-a-smoke-1; p=runs/smoke-1
```

**K1** · ở C3, khi node batch đã `Ready` · §4 "every Karpenter node carries the project tags and the batch taint":

```bash
kubectl get nodes -l karpenter.sh/nodepool -o jsonpath='{range .items[*]}{.spec.taints[*].key}:{.spec.taints[*].effect}{"\n"}{end}' || echo READ_FAILED
aws ec2 describe-instances --filters Name=tag-key,Values=karpenter.sh/nodepool Name=instance-state-name,Values=running --query 'Reservations[].Instances[].Tags[?Key==`Project`||Key==`Owner`||Key==`Environment`||Key==`ManagedBy`].Key' --output text || echo READ_FAILED
```

**Phải thấy:** `zero-drift.io/batch:NoSchedule`; đủ 4 khoá `Project Owner Environment ManagedBy` (từ `EC2NodeClass` `batch`).

**K2** · ở C4, sau B04 · §4 "TRAINING_STARTED with device=cpu, the run attempt and its node name":

```bash
aws s3 cp "s3://$b/$p/1/TRAINING_STARTED" - 2>/dev/null | jq -c '{device, attempt: (.run_key | split("/")[-1]), node_set: ((.node // "") != "")}' || echo READ_FAILED
```

**Phải thấy:** `{"device":"cpu","attempt":"1","node_set":true}`. B04 chỉ kiểm marker có mặt, không đọc nội dung.

**K3** · ở D1, khi attempt 2 đã xong · §4 "exactly one final artifact exists" sau resume:

```bash
o=$(aws s3api list-objects-v2 --bucket "$b" --prefix "$p/2/artifact/" --query 'length(Contents[])' --output text) && echo "artifacts_attempt2=$o" || echo READ_FAILED
```

**Phải thấy:** `artifacts_attempt2=1`. Không dùng `--query KeyCount`: lệnh đó in `None` (window 26/11), có lẽ vì CLI gộp các trang kết quả và bỏ trường này.
Prefix rỗng thì `length(Contents[])` cũng in `None`: đó là `0`, không phải `1`.

**K4** · ở D3, 15 phút sau B08 · §4 "no batch node keeps running":

```bash
nc=$(kubectl get nodeclaims -o name) && echo "nodeclaims: $(printf '%s' "$nc" | grep -c .)" || echo "nodeclaims: READ_FAILED"
```

**Phải thấy:** `nodeclaims: 0`.

**K5** · ở C1, ngay sau khi merge P1b, lặp mỗi 10 giây tới `ACTIVE` · §4 "Ready only after the bucket is Ready and the message is sent":

```bash
kubectl -n tenant-a get batchtrainingjob smoke-1 -o jsonpath='{.status.state} submit={.status.submitState}{"\n"}' || echo READ_FAILED
```

**Phải thấy:** chưa `ACTIVE` khi chưa có `submit=Submitted`; ghi giờ đổi trạng thái vào bảng smoke.

**K6** · ở F1, sau `window.sh cleanup` từng tenant · §4 "its bucket and leftover messages are gone" (tenant-b: đổi `b`):

```bash
if aws s3api head-bucket --bucket "$b" >/dev/null 2>&1; then echo bucket=present; elif aws s3api head-bucket --bucket "$b" 2>&1 | grep -q '(404)'; then echo bucket=gone; else echo bucket=READ_FAILED; fi
bash gitops/tests/batch-suite.sh stats
```

**Phải thấy:** `bucket=gone`; `visible=0 inflight=0`. Dòng §4 "volume is gone" không có lệnh riêng: `inventory.sh` ở F5 đếm volume.

## 6. Điều kiện dừng

Áp dụng S1–S7 của P2, P1–P5 của P3, R1–R9 của P4 và G1–G6 của P5. P6 thêm các điều kiện sau:

| # | Tình huống | Làm gì |
|---|---|---|
| H1 | Node batch sống quá 15 phút mà không có Pod batch nào | Xoá NodeClaim đó. Ghi thành lỗi (consolidation hỏng). Không gửi message mới cho tới khi rõ nguyên nhân |
| H2 | Hai node batch cùng một pool, hoặc quá hai node batch tổng cộng | Dừng gửi message. Đặt cả hai pool `limits.cpu: "0"` qua Argo. Ghi lại, dọn |
| H3 | Pod `Pending` 20 phút mà không có node (`FAILED_CAPACITY`) | Ghi nguyên văn sự kiện của NodeClaim. **Không** nới allowlist trong window. Có thể thử pool On-Demand một lần nếu bạn đồng ý |
| H4 | NodeClaim không biến mất 15 phút sau khi bị xoá | Ghi lại. Xem instance trên AWS. Chỉ terminate tay khi bạn đồng ý, và ghi thành lỗi |
| H5 | Job mới cứ được tạo liên tục cho cùng một request: message không bao giờ bị xoá, hoặc Job hỏng **trước** khi nhận message (kéo image lỗi, crash lúc khởi động; không có `RECEIVED-1`). Ngưỡng: Job thứ 4 cho cùng run key | Purge queue, tắt request. Nếu đã có `RECEIVED-3` thì DLQ đáng lẽ đã chặn: ghi thành lỗi. Nếu chưa có `RECEIVED-1` thì DLQ không thể chặn: ghi lớp hỏng (image, Pod Security, Kyverno) |
| H6 | Instance có tag Karpenter (mọi trạng thái trừ `terminated`) còn trên AWS ở bước F2 sau 15 phút, hoặc lệnh đếm cứ ra `READ_FAILED` | **Không chạy `terraform destroy`.** Ghi lại. Terminate tay theo tag khi bạn đồng ý, rồi đếm lại cho tới khi đọc được `0` |
| H7 | Gross ước tính của window chạm trần 4 USD | Dọn ngay |
| H8 | Apply dừng giữa chừng (S2), plan thử lại chỉ còn vài resource | `plan_assert.sh` chỉ kiểm được **plan đầy đủ**: trên plan thử lại nó FAIL ở "IAM scope" vì các role đã tạo không còn trong plan, và shape hash không thể khớp. Hai dòng đó không phải bằng chứng plan sai, nhưng cũng không còn là cổng. Thay vào đó: mọi resource trong plan thử lại phải có trong plan đầy đủ đã duyệt (cùng địa chỉ, cùng type), `0 to change, 0 to destroy`. Ghi lệch cổng vào evidence, hỏi bạn trước khi apply. S2 chỉ cho thử lại một lần |

## 7. Chi phí

| Khoản | USD/giờ | Nguồn |
|---|---|---|
| Stack P5 (EKS, 2 node system, RDS, IPv4, EBS) | ≈ 0,45 | `P5_L3_WINDOW.md` §7, ước tính |
| Node batch `m6i.large` On-Demand + gp3 20 Gi + IPv4 | ≈ 0,10 | COST_PLAN §5.2 (28/09), đọc lại ở cổng |
| Node batch trên Spot | chưa đọc; giả định ≈ 0,05 | đọc giá Spot ở cổng |
| SQS, EventBridge, S3 | < 0,01 cho cả window | vài nghìn request |
| **Tổng** | 5 giờ × 0,45 + khoảng 2 giờ-node batch ≈ **2,5–2,6 USD** | dưới trần 4 USD |

Đối chiếu: Bills gross tháng 11 trước window P5 là 0,73 USD. Window P5 ước tính khoảng 1,36 USD. Bills gross của P6 chỉ đọc
được sau window (P6-T4.3).
