# Zero D-Rift Experiment Plan

```yaml
document_status: APPROVED_CONTRACT
contract_version: 0.1.0
phase: P1
created_at: 2026-09-29
approved_at: 2026-09-29
approved_by: owner
official_collection_started: false
```

## 1. Purpose and evidence boundary

Tài liệu này chốt phương pháp đo trước khi Zero D-Rift thu trial chính thức. Nó
không chứa kết quả runtime và không chứng minh bất kỳ giả thuyết nào đã đạt.

Các nhãn bắt buộc:

| Nhãn | Ý nghĩa |
| --- | --- |
| `TARGET` | Ngưỡng trong đề cương cần kiểm chứng, không phải kết quả. |
| `SYNTHETIC` | Dữ liệu giả chỉ dùng kiểm tra schema/pipeline; luôn bị loại khỏi phân tích chính thức. |
| `OBSERVED` | Dữ liệu lấy từ một run thật với evidence liên kết. |
| `INCLUDED` | Trial hợp lệ theo contract và được đưa vào primary analysis. |
| `EXCLUDED` | Trial được giữ lại nhưng không đưa vào primary analysis vì một reason code định trước. |
| `FAILED` | Trial hợp lệ đã bắt đầu nhưng không đạt acceptance checks; không đồng nghĩa với `EXCLUDED`. |

Negative boundaries:

- Không dùng các số “3–5 ngày”, “12–15 bước” hoặc tỷ lệ lỗi doanh nghiệp nếu
  không có nguồn độc lập; manual baseline là quy trình tham chiếu do owner thực hiện.
- Không thu trial chính thức trước khi mỗi golden path chạy end-to-end trên EKS
  ít nhất một lần và campaign contract được freeze.
- Không sửa timeout, success rule, exclusion rule hoặc workload profile sau khi
  xem kết quả để làm giả thuyết dễ đạt hơn.
- Không xóa failed/excluded trial, hard-code metric vào report hoặc trộn
  `SYNTHETIC` với `OBSERVED`.
- Không lưu account ID, ARN đầy đủ, credential, token, secret, database password
  hoặc tenant data trong manifest/raw dataset.

## 2. Scope and prerequisites

Contract chỉ bao phủ phạm vi ver3:

- một AWS account sandbox, `us-east-1`, một EKS cluster;
- hai tenant mô phỏng và hai golden path `RAGSandbox`, `BatchTrainingJob`;
- configuration remediation của một Security Group PoC;
- recovery trên RDS PoC/clone tách khỏi shared RDS;
- cost comparison cho cùng một batch workload profile;
- security/isolation negative tests hỗ trợ claim, không biến soft tenancy thành
  production-grade hard isolation.

Mỗi campaign chỉ được freeze khi có đủ:

1. clean or explicitly recorded Git state và immutable commit SHA;
2. pinned component/chart/image/provider versions hoặc digest;
3. Region/AZ, instance type, capacity type và workload profile;
4. UTC clock check cho workstation, cluster và evidence collector;
5. pre-run inventory, Budget status, remaining gross envelope và teardown owner;
6. positive end-to-end smoke test cho path tương ứng;
7. approved timeout, success checks, exclusion codes và expected evidence paths;
8. no unresolved secret-redaction finding.

Thiếu precondition làm campaign chưa sẵn sàng; không được bắt đầu `t0` rồi loại
trial sau đó chỉ vì setup chưa hoàn thành.

## 3. Registered hypotheses and supporting measurements

Các ngưỡng là `TARGET` từ đề cương:

| ID | Primary question and decision rule | Minimum official sample |
| --- | --- | ---: |
| H1 | `RAGSandbox` với shared pre-provisioned RDS có successful-trial `p95 <= 300 s` từ Argo CD nhận revision hợp lệ đến app readiness và DB query pass. | 20 RAG trials |
| H2 | `BatchTrainingJob` có successful-trial `p95 <= 900 s` từ Argo CD nhận request hợp lệ đến training process bắt đầu. | 20 batch trials |
| H3 | Mỗi blueprint đạt provisioning success `>= 18/20`; luôn báo `success/total`, không chỉ phần trăm. | 20/blueprint |
| H4 | Security Group được đưa về desired state với remediation `p95 <= 120 s`; cả 20 trial phải có end event hợp lệ để claim PASS. | 20 drift trials |
| H5 | Tổng variable compute cost của KEDA + Karpenter + Spot thấp hơn ít nhất 40% so với On-Demand always-on trong matched workload profile. | >= 5 matched pairs |
| H6 | Recovery thành công ít nhất `4/5`; báo RTO/RPO quan sát được, không đặt mục tiêu hai phút. | 5 recovery trials |

Supporting measurements không phải giả thuyết độc lập:

| Measurement | Minimum |
| --- | ---: |
| Manual interactions và commands | 5 manual baseline runs/blueprint + IDP logs tương ứng |
| Drift detection time | Cùng 20 H4 trials |
| GPU scale-down time | Cùng 20 batch trials khi GPU path chạy được |
| Isolation/policy pass rate | Mỗi major policy/config commit |
| Teardown inventory | Mọi paid AWS window/campaign |

Một trial có thể phục vụ nhiều metric chỉ khi mapping được khai báo trước trong
manifest. Ví dụ, năm optimized cost arms có thể là subset định trước của 20 H2
trials nếu cùng workload profile và có đầy đủ cost evidence.

## 4. Trial unit and campaign structure

### 4.1. Trial unit

Một trial là một attempt độc lập có `run_id` duy nhất, bắt đầu tại event `t0` đã
định nghĩa và kết thúc bằng success, failure, timeout hoặc safety abort. Cleanup
và inventory của trial trước phải hoàn tất trước `t0` của trial sau, trừ shared
platform resources đã được allowlist.

Smoke/warm-up run luôn có `official=false` và không được retroactively đổi thành
official sau khi thấy kết quả. Official latency trials chạy tuần tự để tránh một
trial tranh capacity với trial khác, trừ khi campaign version khác đăng ký rõ một
concurrency experiment. H1 luôn dùng shared RDS đã pre-provision theo canonical
scope; không được diễn giải duration này là thời gian tạo RDS instance mới.

Run ID format:

```text
zdr-<experiment-id>-<UTC YYYYMMDDThhmmssZ>-<sequence>
```

Ví dụ: `zdr-h1-20261020T010203Z-007`. `run_id` không chứa account, tenant thật,
email hoặc secret.

### 4.2. State classification

- `cold_request`: không còn per-request Kubernetes/AWS resource từ trial trước;
  shared EKS controllers và shared RDS có thể tồn tại theo allowlist.
- `batch_optimized`: queue/event mới, không có GPU node từ trial trước.
- `batch_baseline`: cùng input/profile với optimized arm; On-Demand GPU được
  provision thủ công và giữ qua idle window đã khóa.
- `drift_clean`: Security Group khớp desired state trước mutation.
- `recovery_clean`: recovery DB/clone, snapshot và sentinel checksum đã xác minh;
  shared demo RDS không phải target.

State sai sau preflight nhưng trước `t0` không tạo official trial. State bị sai
sau `t0` do platform/controller là observed failure.

## 5. Reproducible manual baseline

Manual baseline là runbook CLI/Kubernetes/AWS có version control do owner thực
hiện; không đại diện quy trình doanh nghiệp. Dùng AWS Console chỉ khi API/CLI
không cung cấp evidence cần thiết và phải ghi rõ interaction.

### 5.1. Interaction counting rule

Một manual interaction là một hành động human-triggered: chạy một command,
submit form, approve/merge, trả lời prompt, manual retry hoặc sửa cấu hình. Passive
wait không phải interaction. Một script chạy một lần là một interaction nhưng
phải ghi `automated_actions_count`; không được giấu nhiều thao tác tự động bằng
cách gọi chúng là “một bước”. Commands, interactions, wait time, error và remedial
action được ghi riêng.

### 5.2. RAGSandbox manual baseline

Mỗi baseline run dùng cùng acceptance checks với IDP path:

1. xác nhận preflight, identity, Region và clean per-request inventory;
2. tạo namespace, ServiceAccount/RBAC, quota và required policies;
3. tạo/cấu hình S3 scope và least-privilege access cho sandbox;
4. tạo logical database/schema, DB role và secret reference trên shared RDS;
5. deploy application/service và cấu hình identity/secret reference;
6. chờ readiness rồi chạy independent DB-connectivity/query check;
7. ghi interactions, commands, waits, errors, evidence và inventory;
8. teardown per-request resources theo allowlist.

Baseline start là lúc owner bắt đầu bước 1. End là thời điểm cả readiness và DB
query pass; nếu không pass trong `manual_rag_timeout_seconds`, run là failed.

### 5.3. Batch manual baseline

Mỗi baseline arm dùng input, image, dataset/checkpoint target và acceptance checks
giống optimized arm:

1. xác nhận preflight, queue/event state, S3 target và no pre-existing GPU node;
2. provision một approved On-Demand GPU node/capacity bằng runbook thủ công;
3. xác minh node join, label/taint và workload identity;
4. submit training Job và ghi marker khi process thực sự bắt đầu;
5. xác minh job complete và checkpoint/artifact tồn tại trong S3;
6. giữ On-Demand node trong locked idle window;
7. thu hồi node/capacity rồi xác minh EC2/EBS/public-IP inventory;
8. ghi interactions, commands, waits, errors và evidence.

Không dùng Spot price giả định cho manual arm. Variable compute cost lấy từ
observed On-Demand usage; EKS/RDS/network fixed cost báo riêng.

### 5.4. Baseline safety limits and IDP comparator

- `manual_rag_timeout_seconds = 5400`.
- Manual batch readiness stop = 3600 giây; workload execution stop = 2700 giây;
  locked idle window = 1800 giây; teardown stop = 1800 giây.
- Vượt stop rule sau baseline start là failed baseline run, không tự động exclude.
- IDP interaction log dùng cùng counting rule: tạo/submit PR, review/merge, manual
  approval, retry hoặc repair đều được đếm; controller actions là automated actions.
- Không so “một YAML” với hàng chục AWS API calls bằng cách đếm không đồng nhất;
  báo cả human interactions, command invocations và automated actions.
- Manual-vs-IDP duration/interaction difference là descriptive comparison; Task 6
  không đặt trước một phần trăm cải thiện không có trong giả thuyết ver3 và không
  suy rộng thành số liệu doanh nghiệp.

## 6. Event, timeout and acceptance contract

Tất cả raw timestamps dùng RFC 3339 UTC. Polling interval mặc định là 5 giây và
tạo measurement uncertainty tối đa một poll interval; API/event timestamp được
ưu tiên khi có.

| Experiment | `t0` | End event | Timeout / stop rule | Success rule |
| --- | --- | --- | ---: | --- |
| H1 RAG provisioning | Argo CD first observes target Git revision containing valid request | Later of app readiness pass and independent DB query pass | 900 s | Both checks pass; required child resources ready; no unresolved degraded condition |
| H2 batch readiness | Argo CD first observes target revision/request | Training container emits versioned `TRAINING_STARTED` marker after process begins | 1,800 s | Correct Job/Pod, GPU node and identity; marker arrives before timeout |
| H3 provisioning success | Same `t0` as H1/H2 | All blueprint acceptance checks pass | RAG 900 s; batch full-path 4,500 s | Pass within timeout; otherwise valid failure |
| H4 drift detection | AWS mutation API returns success for injected PoC SG rule | First controller condition/event/log detects divergence | 600 s | Detection evidence references intended managed resource |
| H4 drift remediation | Same successful mutation acknowledgement | AWS describe confirms injected rule absent and valid desired rules retained | 600 s | Remediated without deleting valid rule or entering reconcile loop |
| GPU scale-down | Job completes or queue reaches locked zero event | Workload Pod absent and EC2 GPU instance/Node terminated; use later event | 1,800 s | Both Kubernetes and AWS absence checks pass |
| H5 cost arm | Locked workload request/event begins | Workload completes plus 1,800 s idle window and cost window closes | Workload 2,700 s; teardown 1,800 s | Same profile completes; evidence covers runtime, capacity type, idle and teardown |
| H6 recovery | Controlled incident on recovery DB/clone is acknowledged | App health, reconnect and sentinel checksum all pass | 5,400 s safety stop | Correct recovery target restored; checksum matches; shared RDS unchanged |
| Policy/isolation suite | Versioned suite starts | All expected allow/deny assertions finish | 900 s | Allowed path succeeds and every registered forbidden path is denied |

Timeout là planned stop rule, không phải result target. H1/H2/H4 vẫn so observed
duration với target ở mục 3. Khi timeout xảy ra sau `t0`, trial là `FAILED_TIMEOUT`
và không được loại khỏi success-rate denominator.

### 6.1. Exact event notes

- Argo CD `Synced=True` chỉ đánh dấu start/reconciliation evidence; không phải
  provisioning success.
- H1 end dùng check độc lập ngoài Pod phase: app health/readiness và DB query.
- H2 end không dùng `Pod=Running`; process phải emit marker sau khi code bắt đầu.
- H4 mutation chỉ thêm rule PoC allowlisted và phải log mutation request/response
  timestamp; không drift resource shared/production.
- H6 RTO = recovery `t0` đến end event. RPO = incident timestamp trừ timestamp
  của record cuối cùng có trong restored snapshot.

## 7. Matched-pair cost contract

Mỗi H5 pair khóa cùng:

- application/image digest, dataset/input size, GPU request và success marker;
- Region; AZ được ghi observed và khác biệt phải được báo cáo;
- GPU family allowlist, storage, checkpoint behavior và workload timeout;
- 1,800-second idle window;
- logging/metric configuration;
- trial ordering được xen kẽ `baseline -> optimized` và `optimized -> baseline`
  khi khả thi để giảm time-of-day/capacity bias.

Primary saving ratio:

```text
(sum(baseline_variable_compute_usd) - sum(optimized_variable_compute_usd))
/ sum(baseline_variable_compute_usd)
```

Decision H5 PASS khi ratio `>= 0.40`, có ít nhất 5 valid pairs và không pair nào
được ghép sau khi đã xem cost. Báo thêm pairwise ratio, median, range, capacity
errors và On-Demand fallback. `billing_pending` không được biến thành zero.

Variable compute chỉ gồm GPU/EC2 runtime và attached compute storage đã định nghĩa.
EKS control plane, system nodes, RDS, snapshots, public IPv4, logging và data
transfer được báo riêng; OpenCost là allocation evidence, AWS Billing/Cost data
là reconciliation source khi đã cập nhật.

## 8. Run manifest and evidence schema

Mỗi run có một immutable manifest JSON. Required logical fields:

| Group | Required fields |
| --- | --- |
| Identity | `schema_version`, `contract_version`, `run_id`, `campaign_id`, `experiment_id`, `hypothesis_ids`, `trial_number` |
| Classification | `data_class`, `official`, `inclusion_status`, `exclusion_reason_code`, `result_status` |
| Source | `commit_sha`, `git_dirty`, component/chart/image/provider versions/digests |
| Environment | account alias only, Region, AZ, cluster alias, tenant alias, Kubernetes/EKS version |
| Workload | blueprint, profile ID, input size/hash, instance type, capacity type, storage, idle window, timeout |
| Time | preflight, `t0`, detected, ready/started/completed, scale-down, recovery, teardown and billing-observed timestamps in UTC |
| Result | duration fields, acceptance-check map, error class/code, retry/remediation count |
| Human work | `manual_interactions`, `commands_count`, `automated_actions_count`, wait seconds |
| Cost | gross variable compute, fixed categories, source, billing status and observed-at timestamp |
| Evidence | relative paths and SHA-256 for events/logs/inventory/checksum/cost data; redaction result |
| Cleanup | retain allowlist, delete inventory, post-teardown inventory and orphan count |

Allowed `result_status` values:

```text
PASS
FAILED_TIMEOUT
FAILED_ACCEPTANCE
FAILED_CAPACITY
FAILED_IDENTITY
FAILED_POLICY
FAILED_CONTROLLER
SAFETY_ABORT
DRY_RUN_SCHEMA_ONLY
```

Unknown cause is recorded as `FAILED_UNKNOWN`, not guessed. Error message is
redacted and limited; full secret-bearing stdout/stderr is never committed.

### 8.1. Evidence layout

```text
experiments/runs/<campaign_id>/<run_id>/
  manifest.json
  events.jsonl
  inventory-before.json
  inventory-after.json
  acceptance.json
  logs-redacted/
  cost/
  hashes.sha256
```

Paths are planned conventions; directories are created by later implementation
tasks, not by P1. Raw evidence stays immutable. Redacted/presentation derivatives
live separately and retain a hash/reference to raw input.

## 9. CSV and JSONL analysis contract

Canonical trial data is JSONL, one object per line. CSV is a flattened derivative
for statistics and charts.

### 9.1. Trial CSV header

```csv
schema_version,contract_version,run_id,campaign_id,experiment_id,hypothesis_ids,trial_number,data_class,official,inclusion_status,exclusion_reason_code,result_status,blueprint,profile_id,commit_sha,region,az,instance_type,capacity_type,t0_utc,end_utc,duration_seconds,timeout_seconds,manual_interactions,commands_count,automated_actions_count,variable_compute_usd_gross,fixed_cost_usd_gross,billing_status,error_class,evidence_manifest_sha256
```

### 9.2. Event JSONL shape

```json
{"schema_version":"1.0","run_id":"<id>","event_at_utc":"<RFC3339 UTC>","event_type":"<registered event>","source":"argocd|kubernetes|aws|workload|operator","status":"<value>","evidence_ref":"<relative path>","synthetic":false}
```

### 9.3. Analysis outputs

Reproducible analysis script later generates, without hard-coded results:

- `trial_ledger.csv`: every observed/synthetic/excluded/failed run;
- `summary_by_experiment.csv`: attempted, included, excluded, success/total,
  min, max, p50, p95 and sample standard deviation when meaningful;
- `hypothesis_decisions.json`: target, observed, PASS/FAIL/INCONCLUSIVE and reason;
- latency/scale-down/drift charts with included/excluded counts;
- matched cost-pair table and saving-ratio calculation;
- recovery table containing all five RTO/RPO/checksum outcomes;
- `dataset_freeze.json` with input hashes and analysis version.

## 10. Statistical and decision rules

1. Success rate denominator includes all `INCLUDED` official trials, including
   valid failures and timeouts. Report `x/20` for H3.
2. Latency p50/p95 uses successful included trials and states `n_success`; failed
   or censored trials are reported beside the distribution, never silently dropped.
3. p50 is the ordinary median. p95 uses nearest-rank `x[ceil(0.95*n)]` on sorted
   successful durations. With small `n`, publish all points and label uncertainty.
4. H1/H2 require their latency target; H3 independently evaluates reliability.
   Passing one does not imply passing the other.
5. H4 can be called PASS only when all 20 included trials have a valid remediation
   end event and nearest-rank p95 is at most 120 seconds.
6. H5 uses aggregate sums across pre-matched pairs; fixed platform costs do not
   enter the primary numerator but remain visible in total PoC cost.
7. H6 PASS requires at least 4/5 checksum/reconnect successes. Report every RTO
   and RPO value; p95 with five samples is descriptive, not a strong population claim.
8. Sample standard deviation is reported only for at least two numeric observations.
9. Missing or delayed billing data produces `PENDING`/`INCONCLUSIVE`, never zero.

## 11. Inclusion, failure and exclusion rules

### 11.1. Included failures

Sau `t0`, các trường hợp sau vẫn là official valid failure và ở trong denominator:

- timeout;
- EC2/Spot insufficient capacity hoặc GPU quota failure;
- IAM/IRSA, policy, network, controller, webhook hoặc application error;
- reconcile loop, wrong Ready condition, failed checkpoint hoặc failed teardown;
- operator chạy đúng runbook nhưng system trả lỗi.

### 11.2. Pre-registered exclusion reason codes

Trial vẫn được giữ nhưng có thể `EXCLUDED` khỏi primary analysis chỉ với một code:

| Code | Điều kiện |
| --- | --- |
| `SYNTHETIC_NOT_OFFICIAL` | Dry/schema data có `data_class=SYNTHETIC`. |
| `WARMUP_NOT_OFFICIAL` | Smoke/warm-up run được khai báo trước và có `official=false`. |
| `DUPLICATE_RUN_ID` | Collector tạo duplicate identity trước analysis. |
| `WRONG_ARTIFACT_VERSION` | Evidence chứng minh run dùng artifact khác frozen campaign. |
| `CLOCK_SKEW_OUT_OF_BOUND` | Predefined clock check vượt 2 giây và làm duration không tin cậy. |
| `EVIDENCE_PIPELINE_FAILURE` | Required start/end evidence mất do collector, không phải system under test. |
| `OPERATOR_PROTOCOL_VIOLATION` | Operator không làm theo frozen runbook; deviation có audit record. |
| `SAFETY_ABORT_BEFORE_T0` | Stop vì budget/security trước registered start; không phải trial đã bắt đầu. |

AWS capacity, application failure hoặc adverse result sau `t0` không phải exclusion.
Một excluded official attempt được thay bằng trial mới để đạt required included
sample, nhưng ledger phải công bố attempted/included/excluded và reason.

Exclusion do owner/reviewer phê duyệt trước primary analysis. Nếu phát hiện reason
mới sau collection, không sửa v1 âm thầm: tạo contract/dataset version mới, ghi
amendment và chạy lại toàn bộ analysis, đồng thời giữ v1.

## 12. Retention, freeze and change control

### 12.1. Trial retention

- Failed/excluded trial, event, inventory và error class được giữ như successful run.
- Raw evidence read-only/immutable sau capture; mọi redaction tạo derivative mới.
- `hashes.sha256` bao phủ manifest và raw files; secret scan chạy trước publish.
- AWS billing data có thể đến muộn; append evidence bằng versioned file và timestamp,
  không sửa observed event timestamps.
- Retain/delete AWS resource tuân `docs/finops/COST_PLAN.md`, không giữ resource
  tính phí chỉ để giữ evidence khi file export đã đủ.

### 12.2. Campaign freeze

Trước official trial đầu tiên, tạo freeze record gồm:

- contract version và commit SHA;
- experiment/profile/config/timeout/exclusion definitions;
- planned run IDs/count/order và matched-pair mapping;
- component/image/provider digests;
- expected evidence paths và analysis-script version;
- owner approval timestamp.

Sau trial đầu tiên, thay đổi material tạo campaign version mới. Không trộn trial
giữa versions trong primary analysis; comparative/sensitivity analysis phải ghi rõ.

### 12.3. Dataset freeze

Sau khi đủ sample và delayed billing evidence:

1. khóa ledger, inclusion/exclusion decision và hashes;
2. tạo `dataset_freeze.json` với file list, SHA-256, timestamp và commit;
3. chạy secret scan và reproducible analysis từ raw input;
4. lưu output, tool/runtime version và exit status;
5. chỉ sau đó mới viết hypothesis result vào report.

## 13. Synthetic dry manifest

File `docs/experiments/examples/SYNTHETIC_RUN_MANIFEST.json` kiểm tra field names
và JSON parsing. Nó bắt buộc có:

```text
data_class=SYNTHETIC
official=false
inclusion_status=EXCLUDED
exclusion_reason_code=SYNTHETIC_NOT_OFFICIAL
result_status=DRY_RUN_SCHEMA_ONLY
```

Mọi analysis script phải reject synthetic row khỏi official numerator,
denominator và percentile computation.

## 14. Task 6 review gates

### Functional gate

- [x] Registered H1–H6 target/sample boundaries match ver3.
- [x] Manual RAG/batch baselines and interaction counting are reproducible.
- [x] Start/end events, timeouts and success/failure rules are explicit.
- [x] Failed trials are retained; exclusions use pre-registered reason codes.
- [x] Run manifest, CSV/JSONL and analysis output contracts are defined.
- [x] Dataset freeze/change-control rules precede official collection.
- [x] One manifest is clearly `SYNTHETIC` and excluded from official metrics.

### Owner/learning gate

- [x] Owner explains why timeout/system failure after `t0` is not an exclusion.
- [x] Owner explains why baseline and exclusion rules must be frozen before results.
- [x] Owner approves contract v0.1.0 or requests a change before freeze.

Owner teach-back on 2026-09-29 correctly distinguished a real system outcome
after `t0` from an invalid measurement and explained why changing timeout,
success or exclusion rules after seeing results would bias the dataset.

Task 6 functional and learning gates are complete. Contract v0.1.0 is approved.
Approval is not a campaign freeze: no official trial may start until a campaign
freeze record exists and the later implementation preconditions are satisfied.
