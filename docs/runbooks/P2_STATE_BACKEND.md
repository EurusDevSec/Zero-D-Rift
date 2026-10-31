# P2 state backend — bucket S3 giữ Terraform state và khóa (DRF-6)

Trạng thái: `APPROVED` 31/10 (D1–D4). **Đã chạy thật 31/10** bước 0–7: bucket đang tồn tại,
đọc lại đủ 8 điểm, thử khóa đạt. Chi tiết: `docs/evidence/p2/DRF6_STATE_BACKEND_20261031.md`.
Làm lại (tập, hoặc dựng bucket mới) vẫn cần owner duyệt riêng sau bước 0.
Nguồn: ADR-0007 "Decision — state backend"; COST_PLAN §7.4 và §11.3.
Cần có trước: DRF-5 (profile `zdr-bootstrap` và `zdr-tf`); xem `P2_BOOTSTRAP_ACCESS.md`.

## Đích đến

```
Terraform (infra/terraform, AWS_PROFILE=zdr-tf)
   └─ backend "s3" + backend.hcl (riêng tư, không vào Git)
        └─ bucket zero-d-rift-tfstate-<8 ký tự ngẫu nhiên>, us-east-1
             ├─ zero-d-rift/p2/terraform.tfstate         ← state
             └─ zero-d-rift/p2/terraform.tfstate.tflock  ← khóa, chỉ có khi đang chạy
Bảo vệ: chặn public (4/4), BucketOwnerEnforced, SSE-S3, versioning, chỉ cho HTTPS
```

Bucket nằm **ngoài** vòng đời EKS: `terraform destroy` cluster không xóa nó. Bucket được
tạo bằng CLI (không phải Terraform), nên không có cảnh "bucket tự giữ state của chính nó".

## Đọc nhanh

- Làm lần đầu: **Chuẩn bị**, rồi bước 0 đến bước 7.
- Kiểm tra bucket còn đúng không: **Kiểm nhanh**.
- Gặp sự cố khóa hoặc state hỏng: **Khôi phục**.
- Muốn tập trước cho quen: **Tập với bucket nháp**. Làm xong phải xóa ngay.
- Xóa bucket thật: **Dọn bucket**. Chỉ được làm sau mốc 03/11 khi có duyệt riêng.

## Quyết định owner chốt khi duyệt (AC-02)

| # | Câu hỏi | Đề xuất | Đánh đổi |
|---|---|---|---|
| D1 | Tên bucket | `zero-d-rift-tfstate-` cộng 8 ký tự hex ngẫu nhiên; tên chỉ lưu trong `backend.hcl` | Tên bucket là duy nhất toàn cầu, nên đuôi ngẫu nhiên tránh trùng. Không gắn account ID vào tên để khỏi lộ |
| D2 | Tag `ExpiresAt` | `2026-11-03T10:00:00Z` (17:00 ngày 03/11 giờ VN), đúng mốc review | Tag chỉ là ghi chú, **không** tự xóa gì. Đến mốc thì xem lại: giữ tiếp (đổi tag) hoặc dọn |
| D3 | Ai gõ lệnh | **Owner tự gõ** (vì cần mã MFA, và để luyện tay); Claude đọc output đã che và review | Chậm hơn để Claude chạy, nhưng khớp mục tiêu tự làm lại được |
| D4 | Bucket policy | Chỉ một câu: từ chối mọi truy cập không qua HTTPS | Không chặn theo IP hay theo role, nên không có rủi ro tự khóa mình. Thu hẹp quyền ghi state theo ADR để sau, cùng việc làm least privilege trước L3 |

Không làm: không DynamoDB (đã có `use_lockfile`), không KMS key riêng, không lifecycle
tự xóa, không `force_destroy`.

## Chi phí (gross exposure)

Giá niêm yết S3 Standard ở us-east-1 (cần kiểm lại tại aws.amazon.com/s3/pricing trước
khi duyệt): lưu trữ 0.023 USD/GB-tháng; PUT/LIST 0.005 USD/1000 request; GET 0.0004 USD/1000.

| Khoản | Ước tính |
|---|---|
| Lưu state (vài KB, kể cả các bản cũ nhờ versioning) | ~0.00 USD |
| Request: một lần plan/apply khoảng 10–20 request; 100 lần ~2000 request | ~0.01 USD |
| Tổng tới mốc 03/11 | **< 0.05 USD**, nằm trong trần P2 5 USD (mục backend ≤ 0.70) |

Chủ vòng đời (lifecycle owner): HoangLV, cũng là người giữ quyền khôi phục.
Review mỗi 7 ngày; mốc review hoặc dọn là 03/11/2026.

## Chuẩn bị — mỗi lần mở terminal mới

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
```

Lệnh dưới làm mới phiên. Nó sẽ hỏi mã MFA nếu phiên đã hết hạn; dòng hỏi MFA có
account ID nên không dán dòng đó vào đâu. Kết quả đúng là `.../assumed-role/zero-drift-bootstrap/...`:

```bash
aws sts get-caller-identity --profile zdr-bootstrap --query Arn --output text | sed -E 's/[0-9]{12}/<ACCOUNT>/'
```

```bash
export AWS_PROFILE=zdr-tf
```

```bash
export AWS_REGION=us-east-1
```

Từ sau bước 1 (khi đã có `backend.hcl`), lấy lại tên bucket bằng lệnh dưới:

```bash
BUCKET=$(grep bucket infra/terraform/backend.hcl | cut -d'"' -f2)
```

Lưu ý:
- Nếu phiên đã hết hạn mà chưa chạy lệnh `zdr-bootstrap`, lệnh dùng `zdr-tf` sẽ đứng im (DRF-5 bước 5). Khi đó bấm Ctrl+C và làm mới phiên.
- Không dán tên bucket vào Git hay Linear. Khi ghi lại thì viết `<BUCKET>`.

## Bước 0 — Kiểm trước khi xin duyệt (AC-02)

1. Danh tính: lệnh `zdr-bootstrap` ở phần Chuẩn bị phải ra `assumed-role/zero-drift-bootstrap`.
2. Phiên còn ít nhất 30 phút. Lệnh dưới in giờ hết hạn (UTC); giờ VN = UTC + 7:

```bash
jq -r '.Credentials.Expiration' ~/.aws/cli/cache/*.json
```

3. Số bucket hiện có. Quota mặc định là 10 000, nên chỉ cần thấy con số nhỏ:

```bash
aws s3api list-buckets --query 'length(Buckets)'
```

4. Chi phí: trên console, vào **Billing → Bills**, xem tổng tháng 10 và mục S3. Không gọi
   Cost Explorer API, vì API này tính phí theo request.
5. Budget `zero-d-rift-project` vẫn còn: **Billing → Budgets**.

Ghi 5 kết quả này (đã che) vào evidence, rồi xin duyệt: "Duyệt DRF-6 tạo bucket".

## Bước 1 — Đặt tên và ghi `backend.hcl` (lưu tên trước khi tạo)

```bash
BUCKET=zero-d-rift-tfstate-$(openssl rand -hex 4)
```

```bash
cp infra/terraform/backend.hcl.example infra/terraform/backend.hcl
```

```bash
sed -i "s/<private-dedicated-state-bucket>/$BUCKET/" infra/terraform/backend.hcl
```

Kiểm: dòng `bucket` không còn chữ `<private`, và Git phải bỏ qua file
(lệnh `check-ignore` in ra dòng `.gitignore:22:backend.hcl ...`):

```bash
grep bucket infra/terraform/backend.hcl
```

```bash
git check-ignore -v infra/terraform/backend.hcl
```

## Bước 2 — Tạo bucket

Ở us-east-1 thì **không** cần `--create-bucket-configuration`.

```bash
aws s3api create-bucket --bucket "$BUCKET"
```

Kết quả đúng là in `"Location": "/zero-d-rift-tfstate-..."`. Nếu báo `BucketAlreadyExists`
thì tên đã có người dùng: xóa `backend.hcl` rồi làm lại bước 1.

## Bước 3 — Bật 5 lớp bảo vệ

Bucket mới đã có sẵn vài lớp mặc định, nhưng vẫn đặt rõ từng lớp để khi đọc lại biết chắc.

1. Chặn public cả 4 cách:

```bash
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

2. Tắt ACL, bucket sở hữu mọi object:

```bash
aws s3api put-bucket-ownership-controls --bucket "$BUCKET" --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
```

3. Mã hóa SSE-S3:

```bash
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

4. Versioning (giữ các bản state cũ để khôi phục):

```bash
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
```

5. Gắn tag (D2):

```bash
aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging 'TagSet=[{Key=Project,Value=Zero-D-Rift},{Key=Owner,Value=HoangLV},{Key=Environment,Value=PoC},{Key=ManagedBy,Value=manual},{Key=RunId,Value=DRF-6},{Key=Retain,Value=true},{Key=RetainReason,Value=terraform-state-backend},{Key=ExpiresAt,Value=2026-11-03T10:00:00Z}]'
```

Các lệnh `put-...` đúng thì **không in gì**. Có in ra là có lỗi.

## Bước 4 — Policy chỉ cho HTTPS (D4)

Cùng mẹo Windows như DRF-5: `cd` về thư mục chứa file rồi gọi đường dẫn tương đối.

```bash
sed "s/<BUCKET>/$BUCKET/g" infra/iam/tfstate-bucket-policy.json.example > ~/zdr-bucket-policy.json
```

```bash
cd ~
```

```bash
aws s3api put-bucket-policy --bucket "$BUCKET" --policy file://zdr-bucket-policy.json
```

```bash
rm zdr-bucket-policy.json
```

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
```

Không thử gọi bằng `http://` để chứng minh policy: làm vậy sẽ gửi session token qua đường
không mã hóa. Đọc lại policy ở bước 5 là đủ.

## Bước 5 — Đọc lại toàn bộ (AC-03)

Mỗi lệnh có kết quả mong đợi đi kèm. Chụp hoặc dán output vào evidence, nhớ thay tên bucket bằng `<BUCKET>`.

Vùng phải là `None`, nghĩa là us-east-1:

```bash
aws s3api get-bucket-location --bucket "$BUCKET" --query LocationConstraint --output text
```

Phải ra `True True True True`:

```bash
aws s3api get-public-access-block --bucket "$BUCKET" --query PublicAccessBlockConfiguration --output text
```

Phải ra `BucketOwnerEnforced`:

```bash
aws s3api get-bucket-ownership-controls --bucket "$BUCKET" --query 'OwnershipControls.Rules[0].ObjectOwnership' --output text
```

Phải ra `AES256`:

```bash
aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text
```

Phải ra `Enabled`:

```bash
aws s3api get-bucket-versioning --bucket "$BUCKET" --query Status --output text
```

Phải ra `False` (bucket không public):

```bash
aws s3api get-bucket-policy-status --bucket "$BUCKET" --query PolicyStatus.IsPublic --output text
```

Phải ra `DenyNonTlsAccess`:

```bash
aws s3api get-bucket-policy --bucket "$BUCKET" --query Policy --output text | jq -r '.Statement[].Sid'
```

Phải đủ 8 tag ở bước 3:

```bash
aws s3api get-bucket-tagging --bucket "$BUCKET" --query 'TagSet[].[Key,Value]' --output text
```

## Bước 6 — Nối Terraform với backend

```bash
cd infra/terraform
```

```bash
cp run.tfvars.example run.tfvars
```

```bash
sed -i "s/P2-RUN-YYYYMMDD-NN/DRF6-LOCKTEST-01/" run.tfvars
```

Lệnh init dưới, lần đầu nối backend, in `Successfully configured the backend "s3"!`; các lần
sau chỉ in `Terraform has been successfully initialized!`. Nếu báo lỗi
`NoSuchBucket` hoặc `AccessDenied`, kiểm lại `backend.hcl` và phiên `zdr-tf`.

```bash
terraform init -backend-config=backend.hcl -lockfile=readonly
```

Lúc này S3 vẫn chưa có object nào, vì chưa có lần ghi state nào:

```bash
aws s3 ls "s3://$BUCKET/" --recursive
```

## Bước 7 — Thử khóa với 2 terminal (AC-03)

Mục đích: chứng minh rằng khi một người đang giữ state thì người thứ hai bị chặn, và khóa
được nhả sạch sau đó. Bài thử không tạo resource nào và không ghi state.

**Terminal 1** (đứng ở `infra/terraform`, đã làm phần Chuẩn bị). Chạy lệnh dưới rồi
**dừng** ở dòng `Enter a value:`. **Không** gõ `yes`.

```bash
terraform apply -var-file=run.tfvars
```

**Terminal 2.** Làm phần Chuẩn bị (gồm cả lấy biến `BUCKET`), rồi chạy lệnh dưới.
Kết quả phải thấy file `terraform.tfstate.tflock`:

```bash
aws s3 ls "s3://$BUCKET/zero-d-rift/p2/"
```

```bash
cd infra/terraform
```

Lệnh dưới phải báo `Error acquiring the state lock` kèm ID khóa và `Who`, với exit code khác 0.
Dòng `PreconditionFailed` (412) là bình thường: S3 từ chối ghi `.tflock` vì file đã có:

```bash
terraform plan -var-file=run.tfvars -lock-timeout=5s
```

**Terminal 1.** Gõ `no`. Kết quả đúng là `Apply cancelled.` rồi `Releasing state lock`.
Exit code là 1, đây là bình thường với apply bị hủy.

**Terminal 2.** Lệnh dưới phải ra rỗng: không còn khóa, cũng không có state:

```bash
aws s3 ls "s3://$BUCKET/zero-d-rift/p2/"
```

Plan giờ chạy được, nghĩa là khóa đã nhả:

```bash
terraform plan -var-file=run.tfvars -lock-timeout=5s
```

Versioning giữ lại vài bản cũ của file `.tflock`, mỗi bản vài byte. Điều này bình thường,
và sẽ được xóa cùng bucket ở bước Dọn bucket.

Về lại thư mục gốc của repo:

```bash
cd ../..
```

## Kiểm nhanh — bucket còn đúng không

Làm phần Chuẩn bị, rồi chạy lại 8 lệnh ở bước 5. Thêm lệnh dưới, phải ra **rỗng**
(nếu còn `.tflock` thì có người đang chạy, hoặc khóa bị kẹt: xem phần Khôi phục):

```bash
aws s3 ls "s3://$BUCKET/zero-d-rift/p2/" | grep tflock
```

## Khôi phục (đọc trước, chưa chạy vì chưa có state)

**Khóa bị kẹt** (có `.tflock` nhưng không ai đang chạy Terraform):
1. Kiểm các terminal khác. Không có process `terraform` nào đang chạy thì mới tính tiếp.
2. Lấy `ID` từ thông báo lỗi `Error acquiring the state lock`.
3. Xin duyệt, rồi chạy lệnh dưới ở `infra/terraform`. Không tự xóa file `.tflock` bằng `aws s3 rm`.

```bash
terraform force-unlock <LOCK_ID>
```

**State hỏng hoặc ghi nhầm** (khôi phục một bản cũ, không xóa bản hiện tại):

```bash
KEY=zero-d-rift/p2/terraform.tfstate
```

```bash
aws s3api list-object-versions --bucket "$BUCKET" --prefix "$KEY" --query 'Versions[].[Key,VersionId,LastModified,Size,IsLatest]' --output table
```

Chọn `VersionId` đúng (theo giờ chạy thành công gần nhất trong evidence), rồi chép bản đó
thành bản hiện tại. Bản đang hỏng vẫn còn trong lịch sử, nên vẫn quay lại được:

```bash
aws s3api copy-object --bucket "$BUCKET" --key "$KEY" --copy-source "$BUCKET/$KEY?versionId=<VERSION_ID>"
```

Sau đó chạy `terraform plan` ở `infra/terraform` và đọc kỹ trước khi apply bất cứ thứ gì.
Không sửa state bằng tay; không dùng `terraform state push -force`.

## Tập với bucket nháp (tùy chọn, ~0 USD)

Chạy bước 2 → 5 với một tên nháp. **Không** ghi `backend.hcl` (bỏ qua bước 1), không làm
bước 6 và 7, rồi dọn ngay bằng mục Dọn bucket. Đặt tên nháp:

```bash
BUCKET=zdr-practice-$(openssl rand -hex 4)
```

Kiểm đã xóa: lệnh `aws s3api head-bucket --bucket "$BUCKET"` phải báo lỗi `404`.

## Dọn bucket (chỉ khi có duyệt riêng)

Với bucket thật, chỉ được làm khi đủ 3 điều kiện: đã qua mốc review 03/11, đã kiểm kê
không còn resource mồ côi (`terraform state list` rỗng, cộng inventory theo COST_PLAN §11.1),
và owner duyệt riêng việc dọn. Thao tác này **xóa vĩnh viễn**, nên owner tự gõ.

1. Với bucket thật, lưu bản state ra chỗ riêng tư ngoài repo. Bỏ qua bước này nếu chưa có state:

```bash
mkdir -p ~/zdr-private
```

```bash
aws s3 cp "s3://$BUCKET/zero-d-rift/p2/terraform.tfstate" ~/zdr-private/tfstate-$(date +%Y%m%d).json
```

2. Liệt kê mọi bản và delete marker ra file, rồi xem trước. Nếu file chỉ có chữ `None`,
   tức là không có gì để xóa:

```bash
aws s3api list-object-versions --bucket "$BUCKET" --query '[Versions,DeleteMarkers][][].[Key,VersionId]' --output text > ~/zdr-versions.txt
```

```bash
cat ~/zdr-versions.txt
```

3. Xóa từng bản. Xóa có kèm `--version-id` là xóa hẳn, không để lại marker:

```bash
while read KEY VID; do aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$VID"; done < ~/zdr-versions.txt
```

4. Không còn upload dở. Kết quả phải rỗng, không có `Uploads`:

```bash
aws s3api list-multipart-uploads --bucket "$BUCKET"
```

5. Xóa bucket và file tạm:

```bash
aws s3api delete-bucket --bucket "$BUCKET"
```

```bash
rm ~/zdr-versions.txt
```

6. Kiểm: lệnh dưới phải báo lỗi `404`/`Not Found`:

```bash
aws s3api head-bucket --bucket "$BUCKET"
```

7. Chỉ với bucket thật: xóa `infra/terraform/backend.hcl`, rồi trong `infra/terraform`
   chạy `terraform init -backend=false -lockfile=readonly` để về chế độ local.

## Rủi ro còn mở

- Role `zero-drift-bootstrap` đang có `AdministratorAccess` (DRF-5 D1), nên chưa có quyền
  ghi state tối thiểu như ADR-0007 mô tả (ListBucket theo prefix, Get/Put state, Get/Put/Delete
  `.tflock`, không Delete state). Phải làm trước L3.
- Chưa có role khôi phục tách riêng; hiện cùng một người (HoangLV) giữ cả hai vai.
- State thật sẽ chứa thông tin nhạy cảm: không bao giờ dán state hoặc output `terraform show` vào Git hay Linear.
