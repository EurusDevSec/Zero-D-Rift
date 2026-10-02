---
id: ADR-0007
title: P2 bootstrap identity, EKS access and Terraform state contract
status: ACCEPTED
date: 2026-10-02
accepted_date: 2026-10-02
owner_approval: APPROVED_DECISIONS_ONLY
authority: NO_AWS_APPLY_OR_ACCOUNT_MUTATION
---

# Context and authority

Quyết định này giải quyết hai subtask trong SPEC-P2 Task 1.
Nó kế thừa [ADR-0003](ADR-0003_BOOTSTRAP_PLATFORM_BOUNDARY.md),
[ADR-0006](ADR-0006_POC_NETWORK_EGRESS_AND_COST_GUARDRAILS.md) và
[SPEC-P2](../specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md); không mở rộng phase.
Owner đã duyệt identity/access và state contract của ADR này ngày 2026-10-02,
sau Phase1 technical review. Approval chốt quyết định, không cấp quyền tạo backend,
sửa IAM, nâng CLI, request quota, apply, tạo AWS resource, commit hoặc push.

Bản ghi IAM_USER trong COST_PLAN là quan sát cũ, không chứng minh identity,
MFA, federation, backend hoặc quyền hiện tại. Fresh read-only diagnostics nằm ở
[preflight evidence](../../docs/evidence/p2/P2_T1_PREFLIGHT_20261002.md);
current caller chưa xác minh được vì Codex execution environment không resolve
credential chain; Phase1 đã quan sát standard .aws config-file access bị từ chối.
Không kết luận account/máy owner không có credentials từ observations này.
Exact IAM policy và physical backend configuration phải review trước triển khai.

# Decision — identity and access

## Session method

Ưu tiên federation/Identity Center có MFA nếu account đã có cấu hình phù hợp.
Không mặc định bật Identity Center, Organizations hoặc tạo account mới.
Nếu chưa có federation, approved bootstrap exception: existing IAM user có MFA
chỉ dùng làm source để AssumeRole vào dedicated bootstrap role; Terraform và
backend dùng temporary STS session, không dùng IAM-user key trực tiếp.

Ngoại lệ này vẫn có rủi ro source key dài hạn; owner đã duyệt conditional route,
nhưng MFA/trust và quyền source phải verified trước L3. Không tạo thêm access key
theo decision approval này; Terraform không dùng trực tiếp long-lived key.
Mục tiêu session 1 giờ, với tested renewal route trước L3. Với federation, renew
qua reviewed SSO/provider credential chain; với IAM-user MFA AssumeRole, dùng
reviewed CLI role profile/source và re-authenticate MFA khi cache/session hết hạn.
Backend và provider phải dùng cùng intended account/role chain. Không mặc định
credentials export thủ công có auto-refresh: chúng hết hạn và phải thay cả access
key, secret và token trong approved private process rồi kiểm tra lại identity.
Không bắt đầu apply nếu chưa đủ credential lifetime/renewal cho create và teardown;
giữ independent cleanup login hoạt động, không coi expiry là tự xóa resources.
[AWS CLI role profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html).
MFA federation kiểm soát tại IdP/Identity Center; không áp máy móc điều kiện
`aws:MultiFactorAuthPresent` của IAM-user AssumeRole cho mọi federation flow.

[AWS IAM best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
khuyến nghị temporary credentials và MFA.
[AssumeRole permissions](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_control-access_assumerole.html)
giải thích caller permissions và role trust là hai phần cần review.

## Access matrix — approved design, runtime unverified

Tên bên dưới là logical role, chưa phải resource được tạo hay ARN trong Git.

| Role / human owner | AWS boundary | EKS boundary | Activation |
| --- | --- | --- | --- |
| Bootstrap operator / HoangLV | Reviewed P2 create/read/update/delete, scoped PassRole và state read/write/lock | Explicit STANDARD access entry; AmazonEKSClusterAdminPolicy trên duy nhất cluster PoC | Chỉ approved bootstrap/maintenance window; gỡ association và verify lại sau window |
| Daily observer / HoangLV | Selected Describe/List cho inventory; không IAM write, EKS access write hoặc state access | AmazonEKSViewPolicy; bổ sung RBAC chỉ get/list/watch Nodes nếu cần smoke/inventory | Temporary session; không cluster-admin |
| Break-glass / HoangLV, recovery custodian | Reviewed EKS access repair cho cluster PoC; quyền state recovery riêng chỉ khi incident yêu cầu | Entry role ổn định; không permanent admin association; cấp admin chỉ trong approved window | Đường đăng nhập MFA độc lập với bootstrap session/profile phải verified trước L3; có incident record |
| EKS service and managed system node roles / Terraform lifecycle | Chỉ AWS service/node permissions đã review | Managed-node access do EKS quản lý | Không dùng làm human, tenant hoặc controller identity |

Chọn `authentication_mode = "API"`, tắt creator-admin helper
`enable_cluster_creator_admin_permissions = false`. Explicit entries dùng stable
IAM role ARN, không dùng STS session ARN. Không thêm duplicate managed-node entry.
Role bị xóa rồi tạo lại có thể cần tái tạo access entry dù ARN giống trước.
Access entries có eventual consistency: wait/retry có giới hạn sau create/update,
verify entry/association rồi kiểm tra quyền hiệu lực trước dependent workflow.
Không dùng immediate 403 làm bằng chứng final IAM/RBAC denial.
[Create access entries](https://docs.aws.amazon.com/eks/latest/userguide/creating-access-entries.html).

Access policy chỉ cấp Kubernetes permissions, không cấp AWS IAM permissions.
AmazonEKSViewPolicy không phải read-all: không cấp đọc Secrets hoặc Nodes theo
bảng hiện tại. Bổ sung Nodes bằng group + ClusterRole/Binding với đúng ba read
verbs, tạo/gỡ trong bootstrap contract; không thay bằng AmazonEKSAdminViewPolicy
vì policy đó đọc cả Secrets.
[Access policy permission tables](https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html).

Không đưa controller/workload IAM vào P2. Quyền IAM bootstrap phải map từ exact
plan: project role path/tag, PassRole destination, service-linked-role necessity,
action/resource exceptions. Không mặc định AdministratorAccess hoặc tự cho phép
operator sửa trust/permissions boundary của chính nó. Chính sách đủ để teardown
phải được kiểm chứng; matrix này chưa phải deployable least-privilege policy.

Bootstrap operator là trusted administrative actor: quyền CreateAccessEntry và
AssociateAccessPolicy có thể cấp lại Kubernetes admin trên cluster đích, kể cả
sau khi gỡ association của chính role. Không tuyên bố role này không self-escalate
ở EKS. Approved PoC boundary giữ actor này trong approved window, scope đúng cluster ARN
và supported project tags/conditions; audit cả grants/re-grants. Exact policy phải
review ARN/action support, không chỉ dựa tag. Disable normal assumption/grant
authority sau window qua reviewed account-owner procedure, đồng thời giữ cleanup/
inventory/disassociate permissions cho recovery custodian. Daily observer không
có EKS access-management permissions. Tách dedicated access custodian là alternative
nếu reviewer yêu cầu stronger separation; chưa tạo thêm role ở Task 1.

## Foundation ownership and break-glass

Operator role và backend là management anchors: phải tồn tại trước EKS root.
Account owner chịu trách nhiệm khởi tạo chúng trong một task được cấp phép riêng.
Không để EKS destroy tự xóa identity đang thực hiện destroy hoặc bucket chứa state.
Một resource chỉ có một lifecycle owner; foundation không do Crossplane quản lý.

HoangLV đã được owner chỉ định; trước L3 phải verified independent MFA recovery login, role trust,
recovery permissions và thứ tự: system nodes -> EKS -> OIDC/service IAM/network;
operator/backend chỉ cleanup sau khi inventory và state đã an toàn.
EKS access repair có thể dùng AWS EKS API khi Kubernetes RBAC khóa operator,
nhưng không chữa được mất AWS login, SCP/IAM denial hoặc endpoint connectivity.
[AWS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html).
Root MFA/account recovery chỉ là human last-resort; không dùng root cho Terraform.

EKS association không có automatic TTL. Mỗi elevation record phải có incident/run
ID, role alias, policy, scope, granted-at, cleanup deadline UTC, primary cleanup
owner và independent tested MFA recovery identity/login path. Approved primary
cleanup owner và recovery custodian đều là HoangLV/chủ đồ án trong single-owner PoC,
với recovery identity được kiểm soát riêng và còn usable khi bootstrap session
hết hạn. Người backup thứ hai là SHOULD nếu có, không là MUST trừ owner chọn.
Independent recovery login chưa verified là blocker; thiếu người thứ hai không
phải blocker. Không tự giả định recovery role/login đã tồn tại hoặc có quyền.
Cleanup deadline: cuối approved window, hoặc sớm hơn khi incident kết thúc.
Cleanup đã được include trong later approved execution task sẽ disassociate đúng
policy/entry/cluster, wait bounded consistency, list lại association và verify
negative admin operation bằng intended role; không dùng --as hay chỉ can-i --list.
Recovery login làm cleanup nếu bootstrap session hết hạn. Nếu identity/grant repair
phải thực hiện ngoài window, cần explicit incident approval; không mặc định được
tạo mới resource. Terraform desired state phải ghi grant disabled sau window để
lần apply sau không vô tình re-grant; reconcile emergency change trước next apply.

# Decision — state backend

Task 2 local `terraform_data` lab dùng local state với synthetic data và cleanup.
Trước AWS root/L3, approved baseline là dedicated S3 backend tại us-east-1,
tạo bằng reviewed AWS CLI procedure trong separate foundation task được duyệt
riêng. HoangLV/chủ đồ án là primary lifecycle owner và recovery custodian;
independent usable MFA recovery identity/login phải verified trước L3, không bắt
buộc human owner thứ hai. Creation procedure/inventory và redacted
control checks là foundation record; cách CLI này không tạo foundation Terraform
state, nên không có vòng bucket-tự-chứa-state. Task 1 không chạy procedure đó.
Existing bucket chỉ là alternative cần owner xác minh dedicated ownership/prefix
và toàn bộ controls trước khi thay baseline. Nếu sau này đổi sang Terraform để
tạo foundation, phải review local encrypted state location/backup/migration và
separate lifecycle trước build; chưa được tự dùng cách đó.

| Control | Approved decision; implementation unverified |
| --- | --- |
| Address | Default workspace, một fixed state key `zero-d-rift/p2/terraform.tfstate`; physical bucket/profile ở private local configuration |
| Encryption | Explicit SSE-S3 bucket default và `encrypt = true`; TLS required; không thêm customer-managed KMS key mặc định |
| Storage protection | Versioning, all S3 Block Public Access settings, bucket-owner-enforced ownership; review trước sử dụng |
| Locking | `use_lockfile = true`; không thêm DynamoDB table |
| Writer permissions | ListBucket đúng prefix; GetObject/PutObject đúng state object; GetObject/PutObject/DeleteObject đúng `.tflock`; không DeleteObject trên state |
| Recovery permissions | Custodian riêng có ListBucketVersions/GetObjectVersion và reviewed restore write; không cho observer đọc raw state |
| Retention | Bucket ngoài EKS destroy; review mỗi 7 ngày; approved review/cleanup checkpoint 03/11/2026, chỉ xóa sau orphan inventory và explicit cleanup approval; không đặt automatic deletion hoặc unapproved exact giờ |
| Deletion | Không `force_destroy` hay blind version expiration; chỉ cleanup foundation sau safe state capture, orphan audit và owner approval |

[S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
documented locking, permissions và partial configuration.
[SSE-S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingServerSideEncryption.html)
là server-side encryption, không phải permission boundary thay cho IAM.
Backend vẫn có S3 request/storage cost; P2 gross cap 5 USD đã approved trong
COST_PLAN §7.4, nhưng exact estimate/actual spend chưa verified.
S3 gateway endpoint của VPC không mặc định giới hạn workstation/backend vào VPC;
bucket policy phải giữ đường operator/recovery đã review, tránh tự lockout.
Retain reason: protect bootstrap state/recovery until final orphan audit and dataset
freeze. Tại checkpoint 03/11, chỉ delete sau complete project inventory, encrypted private
state capture và explicit cleanup approval; gồm mọi object version/delete marker,
lock/multipart leftovers theo reviewed inventory. Nếu còn orphan hoặc dependency
thì không xóa state: record failure, cost và xin owner quyết định retention tiếp.
Deadline metadata không tự expire/delete bucket; no silent permanent retention.

## Recovery and secret-output rules

1. Dừng writers; xác minh process/session và lock owner. Không tự force-unlock.
   Chỉ xử lý stale lock khi có evidence, đúng lock ID và explicit recovery approval.
   [Terraform locking](https://developer.hashicorp.com/terraform/language/state/locking).
2. Custodian chọn version từ evidence; giữ current version làm rollback.
   Restore bằng copy version thành current object mới, giữ version history.
   Kiểm tra lineage, serial và correspondence với inventory/last successful run;
   không sửa state bằng tay, không force state push.
   [S3 restore versions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/RestoringPreviousVersions.html).
3. Fresh non-apply refresh/plan phải được review trước tiếp tục infrastructure write.
   Plan đọc AWS nhưng có thể tạo/release backend lock hoặc local plan artifact;
   không gọi nó là operation không có write side effect. Không dùng refresh-only
   apply hoặc terraform refresh ở Task 1. Backend locking authority được cấp riêng.
   Old state không tự chứng minh AWS inventory đúng; recovery phải giữ orphan evidence.
4. State, backup, saved plan, plan JSON, sensitive tfvars, kubeconfig và
   `.terraform/` ở private storage ngoài Git/evidence, có access control và
   encryption-at-rest trước dùng real data. Chỉ sanitized derivatives vào repo.
   Raw Terraform state luôn được coi là sensitive, kể cả khi không thấy secret.
5. Không ghi credentials vào backend configuration; dùng reviewed temporary
   profile/environment. Local backend metadata và saved plans vẫn sensitive-capable.
6. `sensitive = true` chỉ che display; giá trị vẫn có thể nằm trong state/plan.
   Tránh secret inputs/outputs không cần thiết; không chạy bulk JSON export để
   tạo evidence. [Terraform sensitive data](https://developer.hashicorp.com/terraform/language/manage-sensitive-data).
   COST_PLAN §11.3 đã được reconcile: không chủ ý đưa credential/secret vào
   configuration/output; raw state luôn được coi là sensitive và không vào Git/evidence.

# Alternatives and consequences

- Direct IAM-user execution: ít bước nhưng giữ long-lived execution credentials;
  không chọn làm baseline. MFA AssumeRole là ngoại lệ có review, không xóa source-key risk.
- Enabling a new federation system: có thể tốt dài hạn nhưng chưa có account
  readiness/cost/scope evidence; không tự mở rộng P2 để làm việc này.
- Local-only AWS state: ít cloud setup nhưng recovery/coordination phụ thuộc máy;
  chỉ chọn cho local synthetic lab, không baseline AWS execution.
- S3 + DynamoDB hoặc customer KMS: thêm lifecycle/permissions/cost, không chọn
  mặc định; revisit nếu explicit requirement trong approved scope đòi hỏi.
- Backend anchors được retain có kiểm soát, không được coi là “teardown complete”
  nếu thiếu allowlist hoặc expiry; versioning không thay thế verified recovery.

# Accepted decisions and remaining verification

Design review cần kiểm tra matrix, explicit trusted-admin boundary, no circular bootstrap,
backend retain/cleanup và source interpretation. Chưa có runtime evidence.
Owner đã duyệt conditional session route, access/state design và HoangLV ownership.
Trước implementation/L3: xác minh actual route/MFA/trust, independent recovery login,
private storage và physical backend controls; exact foundation/IAM procedure phải
review và được cấp execution authority riêng. Decision approval không thay những check này.
Trước L3: exact IAM policy, redacted identity/trust/MFA observations, endpoint path,
backend controls/retention, priced plan trong approved cap/candidate window và L3 approval riêng.

Future verification phải gồm: bootstrap/observer/recovery positive and negative
checks; observer không đọc Secrets/state hoặc mutate; Nodes read tối thiểu;
independent access repair; concurrent writer lock rejection; controlled version
recovery; teardown giữ anchors đến orphan audit rồi cleanup đúng approval.
Không chạy các verification có AWS write trong Task 1 hiện tại.

Owner teach-back chưa thực hiện: giải thích trust khác service permission,
AWS IAM khác EKS access, vì sao expiry không teardown, vì sao sensitive state vẫn
cần bảo vệ và vì sao backend/operator không được tự xóa trong EKS destroy.
