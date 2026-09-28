# Zero D-Rift Cost, Quota and Teardown Plan

## 1. Mục đích và phạm vi

Tài liệu này biến spending envelope **100 USD** trong
`docs/de_cuong_tot_nghiep_ver3.md` thành guardrail có thể kiểm tra trước khi P2
tạo tài nguyên AWS. Đây không phải dự báo hóa đơn chính xác và không chứng minh
credit hoặc quota của account hiện tại.

Phạm vi giữ nguyên:

- một AWS account sandbox;
- một AWS Region;
- một EKS cluster chỉ bật trong cửa sổ integration/experiment;
- tối đa hai tenant mô phỏng;
- đúng hai golden path `RAGSandbox` và `BatchTrainingJob`.

P1 không tạo Budget, EKS, EC2, RDS, NAT Gateway, VPC endpoint hoặc bất kỳ tài
nguyên AWS nào.

## 2. Nhãn bằng chứng

| Nhãn | Ý nghĩa |
| --- | --- |
| `DOC_VERIFIED` | Giá, default quota hoặc behavior có nguồn AWS chính thức, được kiểm tra ngày 2026-09-28. |
| `ACCOUNT_VERIFIED` | Giá trị đã đọc từ đúng account và Region mục tiêu bằng API/console, có evidence đã redaction. |
| `PROPOSED` | Thiết kế được đề xuất nhưng chưa được owner chấp thuận hoặc chưa có runtime evidence. |
| `UNVERIFIED` | Chưa có account, Region, price hoặc runtime evidence cần thiết. |

`DOC_VERIFIED` không thay thế `ACCOUNT_VERIFIED`: default quota trên tài liệu
không chứng minh applied quota của account.

## 3. Trạng thái kiểm tra account ngày 2026-09-28

Read-only probe tại workstation:

| Check | Kết quả | Trạng thái |
| --- | --- | --- |
| AWS CLI | Có `aws-cli/2.0.30` | `OBSERVED` |
| AWS identity | `aws sts get-caller-identity` pass; principal type `IAM_USER`; account ID/ARN được redaction | `ACCOUNT_VERIFIED` |
| Configured Region | `us-east-1` | `ACCOUNT_VERIFIED` |
| Credit balance/applicable products/expiry | Installed CLI `2.0.30` không hỗ trợ `billing get-credits`; chưa kiểm tra console/API bằng client mới | `UNVERIFIED` |
| Applied service quotas | Đã đọc EKS, EC2 CPU/GPU, VPC và RDS quota; xem mục 7.3 | `ACCOUNT_VERIFIED` |

Không account ID, ARN, access key hoặc credential nào được ghi vào tài liệu. Không
có tài nguyên AWS, quota request hoặc account setting nào được tạo/thay đổi bởi probe.

Authenticated probe hiện dùng long-lived IAM user key. Evidence quota có giá trị
cho account/Region, nhưng credential này không được dùng làm workload identity và
không đóng security gate cho P2. Trước paid bootstrap, cần review bootstrap principal
và ưu tiên temporary session theo threat model. KodeKloud Playground không được
dùng làm evidence cho credit/quota của account chạy official trial.

## 4. Spending envelope và nguyên tắc kế toán

| Nhóm | Envelope | Guardrail trước runtime |
| --- | ---: | --- |
| EKS control plane | 25 USD | Standard-support cluster; mục tiêu tối đa 200 cluster-hours, 5 USD còn lại làm buffer. |
| System/CPU nodes | 25 USD | Pin allowed instance families/sizes và node count; không để Karpenter quản lý system pool. |
| RDS, storage, snapshot | 15 USD | Một shared RDS trong active window; recovery DB/clone chỉ tồn tại trong trial window. |
| GPU trial | 15 USD | Tối đa một GPU node đồng thời; tính runtime cap từ giá Region trước từng campaign. |
| Network, IPv4, log, data transfer | 10 USD | Không tạo NAT Gateway mặc định; giới hạn log retention và public IPv4 hours. |
| Dự phòng | 10 USD | Chỉ dùng cho sai số billing, failed trial hợp lệ hoặc teardown; không dùng để mở rộng scope. |
| **Tổng** | **100 USD** | Hard project envelope, không phải bảo đảm của AWS Budgets. |

### Quy tắc tính chi phí

1. Theo dõi **gross service cost trước credit** để project không tiêu vượt 100 USD
   chỉ vì invoice sau credit bằng 0.
2. Theo dõi credit balance, applicable products và expiry như một ledger riêng.
3. OpenCost chỉ là allocation view cho Kubernetes. Cost Explorer/Billing hoặc
   Cost and Usage data là nguồn đối soát AWS khi dữ liệu đã cập nhật.
4. Mọi estimate phải ghi Region, timestamp, price source, quantity và hours.
5. Không dùng Spot discount cố định làm kết quả; ghi observed Spot price/cost cho
   từng trial.

## 5. Cost model trước khi tạo resource

### 5.1. Công thức tối thiểu

```text
EKS control-plane cost
= cluster hours x EKS standard-support hourly price

Node cost
= sum(instance runtime x instance price)
 + EBS volume GB-month/request cost
 + public IPv4 hours

RDS cost
= DB instance hours
 + allocated storage
 + backup/snapshot storage
 + data transfer/request cost when applicable

GPU variable cost
= GPU instance runtime x observed On-Demand or Spot price
 + attached storage
 + checkpoint S3 requests/storage

Network cost
= NAT gateway hours + NAT processed GB
 + interface endpoint ENI-hours + processed GB
 + public IPv4 hours
 + cross-AZ/internet data transfer
```

### 5.2. Dated price facts

| Cost fact | Giá/behavior quan sát từ nguồn chính thức | Trạng thái |
| --- | --- | --- |
| EKS standard-support control plane | 0.10 USD/cluster-hour; extended support 0.60 USD/cluster-hour | `DOC_VERIFIED` |
| EKS 25 USD envelope | Lý thuyết tối đa 250 giờ ở 0.10 USD/giờ; plan dùng tối đa 200 giờ để giữ buffer | `DERIVED_FROM_DOC` |
| Public IPv4 | 0.005 USD/address-hour cho in-use và idle public IPv4 | `DOC_VERIFIED` |
| NAT Gateway | Tính theo provisioned hour, processed GB và standard data transfer; partial hour tính tròn | `DOC_VERIFIED`; exact Region price `UNVERIFIED` |
| S3 gateway endpoint | Không có additional endpoint charge | `DOC_VERIFIED` |
| Interface endpoint | Tính theo endpoint ENI-hour ở mỗi AZ và GB processed; giá phụ thuộc Region | `DOC_VERIFIED`; exact Region price `UNVERIFIED` |
| EC2/RDS/GPU/EBS/S3/CloudWatch | Phụ thuộc Region, instance class, storage, request và retention | `UNVERIFIED` đến khi Region/config được chốt |

Ví dụ minh họa, không phải estimate cuối: hai public IPv4 cho node chạy tổng cộng
200 giờ tương đương `2 x 200 x 0.005 = 2 USD`. Số node/hour thực tế phải lấy từ
inventory và billing data.

## 6. Network egress comparison

| Phương án | Fixed/variable cost | Ưu điểm | Rủi ro/giới hạn | Kết luận P1 |
| --- | --- | --- | --- | --- |
| Public node subnets + Internet Gateway | Không có NAT hourly charge; trả public IPv4 và data transfer | Đơn giản, đáp ứng general outbound cho image/package/API trong PoC ngắn | Node có public IP; phải deny unsolicited inbound, enforce IMDS/SG và giới hạn EKS API CIDR | `PROPOSED` cho PoC qua ADR-0006 |
| Private nodes + NAT Gateway | NAT-hour + processed GB + data transfer | General outbound đơn giản, node không cần public IPv4 | Fixed hourly leak lớn so với envelope; một NAT tạo AZ/cross-AZ trade-off, per-AZ NAT tăng cost | Không tạo mặc định |
| Private nodes + interface endpoints | Endpoint ENI-hour/AZ + processed GB cho từng service | Private AWS API path, có thể giảm NAT traffic | Nhiều endpoint tạo nhiều fixed charges; không thay general internet egress; phải inventory chính xác service dependency | Chỉ dùng khi security/traffic evidence biện minh |
| S3 gateway endpoint | Không thêm endpoint charge | S3 không cần NAT/Internet Gateway route; phù hợp checkpoint/artifact | Chỉ S3/DynamoDB gateway services; route/policy phải được test | `PROPOSED` cùng ADR-0006 |

### Proposed P2 baseline — chưa được chấp thuận

- Không tạo NAT Gateway mặc định.
- System và ephemeral workload nodes chạy trong public subnets với public IPv4,
  security group không mở inbound từ Internet.
- RDS nằm trong private DB subnets và không public-accessible.
- Bật S3 gateway endpoint cho route tables cần checkpoint/artifact.
- EKS API bật private access; public access chỉ giữ nếu cần cho workstation và
  phải giới hạn approved CIDR.
- Nếu controller/workload cần private-only posture hoặc dependency không hoạt
  động qua baseline này, price lại NAT/interface endpoint option trước khi đổi.

Đây là cost-optimized PoC design, không phải production network claim. Region,
CIDR, route table, endpoint policy, EKS endpoint exposure và runtime reachability
vẫn `UNVERIFIED`.

## 7. Credit, Region và quota preflight

### 7.1. Credit applicability

AWS Billing `GetCredits` có thể trả credit amount, applicable product names,
expiry và enabled state. Trước P2 phải lưu evidence đã redaction cho:

- remaining amount;
- expiration date;
- applicable products cho EKS, EC2, RDS, VPC/network và service liên quan;
- credit-sharing behavior nếu account thuộc AWS Organizations;
- service charge không được credit cover.

Nếu API/console không chứng minh một service được cover, coi service đó là
out-of-pocket và vẫn tính vào 100 USD envelope.

### 7.2. Selected Region và remaining price gate

Owner đã cấu hình và read-only probe đã xác nhận `us-east-1` ngày 2026-09-28.
Region này được chọn cho PoC vì EKS endpoint và GPU families cần thiết có mặt,
official pricing/examples dễ đối chiếu và project không ưu tiên end-user latency.

Selection vẫn phải được review lại nếu credit, price hoặc GPU capacity không phù
hợp. Exact EC2/RDS/GPU price sheet còn `UNVERIFIED`. Các yếu tố giữ làm evidence:

1. EKS/Kubernetes 1.35 và selected services khả dụng.
2. GPU family candidate có mặt và account có quota.
3. On-Demand/Spot price cùng Spot capacity signal.
4. RDS PostgreSQL class/version và snapshot/restore support.
5. Credit applicability.
6. Latency không quan trọng hơn cost/reproducibility trong PoC một Region.

### 7.3. Applied quota checks

| Service/quota | Applied value in `us-east-1` | Project requirement | Account state |
| --- | ---: | ---: | --- |
| EKS clusters per Region | 100, adjustable | 1 | `ACCOUNT_VERIFIED` |
| Managed node groups per cluster | 30, adjustable | System pool only if chosen | `ACCOUNT_VERIFIED` |
| VPCs per Region | 5, adjustable | 1 | `ACCOUNT_VERIFIED` |
| EC2 Running On-Demand G and VT vCPUs | **0**, adjustable | Tối thiểu 4 vCPU cho một `g4dn.xlarge` candidate | `BLOCKED_BY_QUOTA` |
| EC2 All G and VT Spot vCPUs | **0**, adjustable | Tối thiểu 4 vCPU cho một `g4dn.xlarge` candidate | `BLOCKED_BY_QUOTA` |
| Standard On-Demand vCPUs | 5, adjustable | System nodes + bounded CPU workload pool | `ACCOUNT_VERIFIED`; sizing review needed |
| Standard Spot vCPUs | 5, adjustable | Bounded CPU Spot experiment if used | `ACCOUNT_VERIFIED` |
| RDS DB instances | 40, adjustable | Shared RDS + tối đa một recovery target đồng thời | `ACCOUNT_VERIFIED` |
| Manual RDS DB snapshots | 100, adjustable | Chỉ snapshot có allowlist/expiry | `ACCOUNT_VERIFIED` |
| NAT gateways per Availability Zone | 5, adjustable | 0 theo proposed ADR-0006 | `ACCOUNT_VERIFIED` |
| Network interfaces per Region | 5000, adjustable | Bounded by one cluster/two tenants | `ACCOUNT_VERIFIED` |
| IAM roles/OIDC providers | Default docs phải kiểm tra cùng applied quota | Bootstrap/controller/workload roles tối thiểu | `UNVERIFIED` |
| Security group rules, load balancers, public IPv4 | Account/Region dependent | Bounded by one cluster and two tenants | `UNVERIFIED` |

Kết luận quota hiện tại: P2 EKS bootstrap không bị chặn bởi EKS/VPC/RDS count,
nhưng P6 GPU bị chặn cho đến khi G/VT quota được tăng hoặc GPU path được điều chỉnh
theo roadmap. Task 5 không tự gửi quota-increase request.

Read-only command family sau khi có temporary session và approved Region:

```powershell
$projectRegion = '<approved-region>'
aws sts get-caller-identity
aws service-quotas list-service-quotas --service-code eks --region $projectRegion
aws service-quotas list-service-quotas --service-code ec2 --region $projectRegion
aws service-quotas list-service-quotas --service-code vpc --region $projectRegion
aws service-quotas list-service-quotas --service-code rds --region $projectRegion
aws service-quotas list-service-quotas --service-code elasticloadbalancing --region $projectRegion
```

Evidence không được chứa access key hoặc full account ID. Quota-increase request
là external account mutation và cần owner approval riêng; Task 5 không gửi request.

## 8. Budget, billing và stop rules

### 8.1. Budget design

P2 tạo một fixed project cost budget 100 USD hoặc custom-period equivalent nếu
account hỗ trợ đúng project window. Alerts bắt buộc:

| Threshold | Loại | Hành động |
| ---: | --- | --- |
| 50 USD / 50% | Actual | Thông báo; kiểm tra category burn-rate và orphan inventory. |
| 75 USD / 75% | Actual | Dừng optional/failed reruns; review remaining mandatory trials và teardown reserve. |
| 90 USD / 90% | Actual | Freeze tạo paid resource mới; chỉ cho teardown hoặc một run được owner duyệt. |
| Forecast >= 90% | Forecast | Chỉ dùng khi AWS có đủ historical data; không dựa vào forecast trong account mới. |
| 100 USD | Manual hard stop | Emergency inventory + teardown; không dùng Budget như hard real-time circuit breaker. |

AWS Budgets dùng billing data cập nhật ít nhất hằng ngày; forecast có thể cần
khoảng năm tuần usage history. Vì vậy alerts không thay inventory/TTL/teardown.

Không áp một deny-all Budget Action có thể chặn `Delete*`, inventory hoặc evidence
export. Nếu dùng Budget Action, policy phải được review để vẫn cho phép read và
safe teardown.

### 8.2. Daily control loop

Trong mỗi active AWS window:

1. Đầu ngày: kiểm tra remaining credit, gross spend, Budget alerts và active resources.
2. Trước create: ghi estimate, planned duration, owner, RunId và teardown time.
3. Trong run: quan sát EKS/node/RDS/GPU/NAT/endpoint/public-IP inventory.
4. Kết thúc run: export evidence, teardown và chạy inventory lại.
5. Ngày kế tiếp: đối soát delayed billing; cập nhật category ledger, không sửa raw trial.

## 9. GPU và autoscaling cost guardrails

- Account quota cho cả G/VT On-Demand và G/VT Spot phải được đọc trước P6; default
  có thể bằng 0.
- Chỉ một GPU node đồng thời trong PoC.
- GPU NodePool allowlist selected family/size/AZ; không dùng wildcard mọi GPU family.
- Karpenter NodePool đặt `limits.nodes: 1`, `limits.nvidia.com/gpu: 1` và CPU/memory
  limit tương ứng selected instance.
- Karpenter limit checking là eventually consistent; account EC2 quota và admission
  guardrail vẫn là lớp chặn bổ sung.
- Spot fallback sang On-Demand phải bounded, không tự mở rộng số node.
- Trước campaign, runtime cap:

```text
maximum GPU runtime
= remaining GPU envelope / selected effective hourly price
```

- Job phải checkpoint vào S3 trước Spot trial. Failed/interrupted trial vẫn giữ
  evidence và vẫn tính cost.

## 10. Tagging và TTL contract

Tag bắt buộc khi resource hỗ trợ tag:

| Tag | Ví dụ/ý nghĩa |
| --- | --- |
| `Project` | `Zero-D-Rift` |
| `Owner` | `HoangLV` |
| `Environment` | `PoC` |
| `ExpiresAt` | UTC RFC3339 timestamp |
| `RunId` | ID liên kết experiment/run manifest |
| `ManagedBy` | `Terraform`, `Crossplane`, `Karpenter` hoặc approved owner |
| `Retain` | `true` chỉ khi có allowlist entry |
| `RetainReason` | Lý do ngắn, không chứa secret/private data |

`ExpiresAt` chỉ là metadata, không tự xóa tài nguyên. Cleanup automation phải parse,
inventory và xin approval theo lifecycle owner. Resource không hỗ trợ tag phải có
entry trong inventory manifest.

## 11. Inventory và teardown contract

### 11.1. Inventory tối thiểu trước và sau teardown

- EKS cluster, node groups, add-ons và access configuration.
- EC2 On-Demand/Spot instances, Karpenter NodeClaims/Nodes và launch templates.
- EBS volumes/snapshots, ENIs, security groups và Elastic/Public IPv4.
- VPC, subnet, route table, Internet Gateway, NAT Gateway và VPC endpoints.
- Load balancers, target groups và listeners.
- RDS instances/clusters, recovery target, automated/manual snapshots, subnet và
  parameter groups.
- S3 buckets, object versions, multipart uploads và lifecycle state.
- SQS queues, Secrets Manager metadata và KMS keys/aliases created by the project.
- CloudWatch log groups/retention, alarms, dashboards và CloudTrail references.
- IAM roles/policies/OIDC provider thuộc project boundary.
- Crossplane managed resources/finalizers và external-resource annotations.

Inventory phải ghi timestamp, Region, sanitized resource identifier, owner,
`ExpiresAt`, retain/delete decision và observed state. Không lưu secret value.

### 11.2. Teardown order

1. Freeze new request: ngừng merge/apply và xác nhận approved Git revision.
2. Capture run evidence và pre-teardown inventory.
3. Xóa golden-path request khỏi desired state hoặc suspend đúng cơ chế đã duyệt;
   chờ Argo/kro/Crossplane finalizer và status ổn định.
4. Xác nhận Crossplane deletion/management policy cho từng external resource;
   không xóa controller trước khi biết resource nào sẽ orphan.
5. Hoàn tất/stop Jobs; xác minh checkpoint; thu hồi Karpenter NodeClaims/GPU nodes.
6. Xóa recovery RDS/clone, temporary S3/SQS/ELB/EBS/log resources theo owner matrix.
7. Terraform destroy bootstrap resource theo dependency order nếu window kết thúc.
8. Chạy post-teardown inventory ngay, rồi lặp lại sau khi billing/inventory API cập nhật.
9. Ghi orphan hoặc failed deletion như failure evidence; không xóa khỏi record.

### 11.3. Retain allowlist

Chỉ giữ AWS resource khi có `Retain=true`, owner approval, reason và expiry:

| Có thể retain có điều kiện | Điều kiện |
| --- | --- |
| Terraform remote-state backend | Ownership/state protection được P2 chốt; không chứa plaintext secret. |
| Designated evidence/checkpoint S3 bucket/prefix | Lifecycle/expiry, encryption và publish/redaction rule đã duyệt. |
| Shared RDS | Chỉ trong active RAG campaign; daily cost check và expiry rõ ràng. |
| Một verified RDS recovery snapshot | Chỉ trong recovery campaign; checksum/evidence linked và expiry rõ ràng. |
| CloudWatch log evidence | Retention days bounded; export trước khi delete nếu cần. |

Mặc định delete sau window:

- EKS control plane và system/workload nodes;
- Karpenter GPU/Spot/On-Demand capacity;
- NAT Gateway, public IPv4/EIP, interface endpoints và load balancer;
- recovery DB/clone và snapshot không nằm trong allowlist;
- temporary S3 bucket/object/version/multipart upload và SQS queue;
- orphaned EBS, ENI, security group, log group và controller external resource.

## 12. Task 5 gates

### Documentation gate — complete

- [x] 100 USD envelope có category guardrail và stop rules.
- [x] Official price/quota behavior có source và check date.
- [x] NAT/public subnet/VPC endpoint alternatives được so sánh.
- [x] Budget thresholds, daily check, TTL tags và GPU limits được định nghĩa.
- [x] Inventory, teardown order và retain/delete allowlists được định nghĩa.

### Account/owner gate — open

- [ ] Owner chấp thuận hoặc từ chối ADR-0006.
- [x] Chọn AWS account và Region mục tiêu (`us-east-1`) và xác nhận bằng STS đã redaction.
- [ ] Xác minh credit amount, applicable products và expiry.
- [x] Capture applied quota cho EKS, EC2 standard/GPU, VPC và RDS; GPU G/VT
      On-Demand/Spot đều bằng 0. ELB detail giữ cho pre-P2 priced inventory nếu dùng.
- [ ] Tạo priced estimate cho exact node/RDS/GPU/network configuration trước P2.

Không được gọi Task 5 `ACCOUNT_VERIFIED` hoặc bắt đầu paid L3 work khi gate này còn mở.

## 13. Official references checked 2026-09-28

- AWS, [Amazon EKS pricing](https://aws.amazon.com/eks/pricing/)
- AWS, [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/)
- AWS, [Pricing for NAT gateways](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html)
- AWS, [Gateway endpoints for Amazon S3](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html)
- AWS, [AWS PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/)
- AWS, [Best practices for AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-best-practices.html)
- AWS, [Billing GetCredits API](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_billing_GetCredits.html)
- AWS, [Service Quotas list-service-quotas](https://docs.aws.amazon.com/cli/latest/reference/service-quotas/list-service-quotas.html)
- AWS, [Amazon EKS endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/eks.html)
- AWS, [Amazon EC2 instance type quotas](https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-instance-quotas.html)
- AWS, [Amazon RDS quotas](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Limits.html)
- Karpenter, [NodePool limits](https://karpenter.sh/docs/concepts/nodepools/)
