# T01 — Walkthrough gõ theo

Bản gõ theo của [LAB.md](LAB.md). Gõ tay từng file (đừng copy-paste cả khối), đọc
phần "Vì sao" ngay dưới mỗi file, rồi chạy mission. Đáp án đối chiếu nằm trong các
khối "Đối chiếu" thu gọn: chỉ mở **sau khi** đã ghi dòng `expect` vào `notes.md`.

Code này đã được chạy thử đủ M1–M7 trên Terraform 1.16.4 ngày 2026-10-30.

## 0. Thư mục chạy

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/playground && mkdir -p "runs/TF-T01-$(date +%Y%m%d)-01/modules/network" "runs/TF-T01-$(date +%Y%m%d)-01/modules/cluster" && cd "runs/TF-T01-$(date +%Y%m%d)-01" && pwd
```

```bash
printf '# TF-T01 notes\n\nrun_id: %s\n\n' "$(basename "$PWD")" > notes.md && cat notes.md
```

Mọi file dưới đây tạo trong thư mục này. `playground/runs/` đã bị Git bỏ qua, nên
state và plan không bao giờ lọt vào repo.

## 1. `versions.tf`

```hcl
terraform {
  required_version = "= 1.16.4"
}
```

Vì sao:

- `=` là ghim **đúng** bản, không phải `>=`. Máy khác cài 1.17 sẽ bị chặn ngay, nên
  ai chạy cũng ra cùng hành vi. Đây là pin đã duyệt ở DRF-3.
- Không có khối `required_providers`: `terraform_data` có sẵn trong Terraform, nên
  `init` không tải gì. Khi lên AWS thật, khối này sẽ ghim `hashicorp/aws = 6.67.0`.

## 2. `variables.tf` — đầu vào và guardrail

```hcl
variable "region" {
  description = "AWS Region for the PoC."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "Zero D-Rift runs only in us-east-1 (credits and quota live there)."
  }
}

variable "cluster_name" {
  description = "EKS cluster name; also prefixes network names."
  type        = string
  default     = "zero-drift"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "cluster_name may contain only lowercase letters, digits and hyphens."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.35"
}

variable "azs" {
  description = "Availability Zones for public and DB subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.azs) == 2
    error_message = "Use exactly 2 AZs: EKS needs at least 2 and the PoC budget allows 2."
  }
}

variable "vpc_cidr" {
  description = "VPC IPv4 CIDR block."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR such as 10.0.0.0/16."
  }
}

variable "enable_nat_gateway" {
  description = "Guardrail only; ADR-0006 forbids a default NAT Gateway."
  type        = bool
  default     = false

  validation {
    condition     = var.enable_nat_gateway == false
    error_message = "NAT Gateway is disabled by ADR-0006 (cost guard)."
  }
}

variable "system_node_ami_type" {
  description = "AMI type of the system node group."
  type        = string
  default     = "AL2023_x86_64_STANDARD"

  validation {
    condition     = startswith(var.system_node_ami_type, "AL2023")
    error_message = "System nodes must use an AL2023 AMI type."
  }
}

variable "system_node_desired_size" {
  description = "Desired number of system nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.system_node_desired_size >= 1 && var.system_node_desired_size <= 3
    error_message = "system_node_desired_size must be between 1 and 3."
  }
}
```

Vì sao:

- `validation` chạy lúc `plan`, **trước** khi có gì được tạo. Sai đầu vào là dừng
  ngay, không tốn đồng nào. Đây là policy-as-code đơn giản nhất.
- `can(...)` biến một hàm có thể lỗi (`regex`, `cidrhost`) thành `true`/`false`, để
  dùng được làm điều kiện.
- `enable_nat_gateway` không được module nào dùng. Nó tồn tại **chỉ để chặn**: ai đó
  lỡ bật NAT (khoảng 32 USD/tháng chưa tính data) sẽ bị chặn ngay ở plan.
- Tên biến giống hệt sẽ dùng trong `infra/terraform/`.

## 3. `main.tf` — nối hai module

```hcl
module "network" {
  source = "./modules/network"

  name     = var.cluster_name
  region   = var.region
  vpc_cidr = var.vpc_cidr
  azs      = var.azs
}

module "cluster" {
  source = "./modules/cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.network.vpc_id            # tham chiếu -> cạnh phụ thuộc
  subnet_ids         = module.network.public_subnet_ids # tham chiếu -> cạnh phụ thuộc
  node_ami_type      = var.system_node_ami_type
  node_desired_size  = var.system_node_desired_size
}
```

Vì sao:

- Hai dòng có comment là **toàn bộ** lý do Terraform biết phải dựng network trước
  cluster. Không có `depends_on` nào, thứ tự file cũng không quan trọng.
- Module chỉ nói chuyện với nhau qua `output` -> `variable`. Sau này thay ruột
  `network` bằng AWS thật mà không phải sửa `cluster`.

## 4. `outputs.tf`

```hcl
output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "cluster_version" {
  value = module.cluster.cluster_version
}

output "oidc_provider_id" {
  value = module.cluster.oidc_provider_id
}
```

Vì sao: output là "cửa sổ" để nhìn vào state mà không mở file state. Chỉ xuất giá
trị không nhạy cảm.

## 5. `modules/network/variables.tf`

```hcl
variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}
```

Vì sao: module không có `default` và không tự validate. Root chịu trách nhiệm
guardrail, module chỉ khai báo nó cần gì.

## 6. `modules/network/main.tf`

```hcl
resource "terraform_data" "vpc" {
  input = {                     # đổi input -> update tại chỗ (~)
    name   = "${var.name}-vpc"
    region = var.region
  }
  triggers_replace = var.vpc_cidr # đổi CIDR -> xóa đi tạo lại (-/+), giống AWS
}

resource "terraform_data" "public_subnets" {
  for_each = { for index, az in var.azs : az => cidrsubnet(var.vpc_cidr, 4, index) }

  input = {
    name = "${var.name}-public-${each.key}"
  }
  triggers_replace = [terraform_data.vpc.id, each.key, each.value]
}

resource "terraform_data" "db_subnets" {
  for_each = { for index, az in var.azs : az => cidrsubnet(var.vpc_cidr, 4, index + 8) }

  input = {
    name = "${var.name}-db-${each.key}"
  }
  triggers_replace = [terraform_data.vpc.id, each.key, each.value]
}

resource "terraform_data" "s3_gateway_endpoint" {
  input = {
    name    = "${var.name}-s3-endpoint"
    service = "com.amazonaws.${var.region}.s3"
  }
  triggers_replace = terraform_data.vpc.id
}
```

Vì sao:

- `for_each` trên một map `AZ => CIDR` tạo ra `public_subnets["us-east-1a"]` và
  `["us-east-1b"]`. Địa chỉ trong state gắn theo **tên AZ**, không theo số thứ tự,
  nên thêm hoặc bớt một AZ không làm xáo trộn subnet còn lại. Đây là lý do dự án
  dùng `for_each` thay vì `count`.
- `cidrsubnet("10.0.0.0/16", 4, i)` cắt ra các `/20`: public lấy số 0 và 1
  (`10.0.0.0/20`, `10.0.16.0/20`), DB lấy số 8 và 9 (`10.0.128.0/20`,
  `10.0.144.0/20`). Không cần tự tính tay.
- `triggers_replace` của subnet chứa `vpc.id`: VPC bị tạo lại thì có id mới, kéo
  theo subnet phải tạo lại, đúng như AWS (subnet không chuyển VPC được).
- `region` nằm trong `input` của VPC chỉ để làm nhãn. Lên AWS, Region do provider
  quyết định.

## 7. `modules/network/outputs.tf`

```hcl
output "vpc_id" {
  value = terraform_data.vpc.id
}

output "public_subnet_ids" {
  value = [for subnet in terraform_data.public_subnets : subnet.id]
}

output "db_subnet_ids" {
  value = [for subnet in terraform_data.db_subnets : subnet.id]
}
```

Vì sao: `for` biến map các subnet thành list id, đúng kiểu mà EKS cần (`subnet_ids`).
`db_subnet_ids` để dành cho RDS ở phase sau; EKS không dùng nó.

## 8. `modules/cluster/variables.tf`

```hcl
variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "node_ami_type" {
  type = string
}

variable "node_desired_size" {
  type = number
}
```

## 9. `modules/cluster/main.tf`

```hcl
resource "terraform_data" "eks" {
  input = {
    version    = var.kubernetes_version # upgrade version -> update tại chỗ
    subnet_ids = var.subnet_ids
  }
  triggers_replace = [var.cluster_name, var.vpc_id] # đổi tên hoặc VPC -> cluster mới
}

resource "terraform_data" "oidc_provider" {
  triggers_replace = terraform_data.eks.id # cluster mới -> issuer mới -> OIDC mới
}

resource "terraform_data" "system_nodes" {
  input = {
    desired_size = var.node_desired_size
    version      = terraform_data.eks.output.version # đọc từ EKS, không đọc thẳng từ biến
  }
  triggers_replace = [terraform_data.eks.id, var.node_ami_type]
}
```

Vì sao:

- Đây là bảng ánh xạ trong LAB.md viết thành code. Mỗi giá trị nằm ở `input` hay
  `triggers_replace` tùy AWS cho sửa tại chỗ hay bắt tạo mới.
- `oidc_provider` không có `input`: nó chỉ có lý do tồn tại khi cluster tồn tại.
- `system_nodes` lấy version từ `eks.output` chứ không từ `var.kubernetes_version`.
  Như vậy node luôn đi **sau** control plane khi upgrade, đúng thứ tự EKS yêu cầu
  (control plane trước, node sau).
- `.output` của `terraform_data` chính là `input` sau khi apply. Khi `input` đổi,
  `.output` trở thành "known after apply" cho tới lúc apply xong.

## 10. `modules/cluster/outputs.tf`

```hcl
output "cluster_version" {
  value = terraform_data.eks.output.version
}

output "oidc_provider_id" {
  value = terraform_data.oidc_provider.id
}
```

## 11. `noop-check.sh` (bash, M2)

```bash
#!/usr/bin/env bash
# Print NOOP and exit 0 only when the Terraform plan has no changes.
# Usage: ./noop-check.sh [extra plan args, e.g. -var kubernetes_version=1.36]
set -euo pipefail

rc=0
terraform plan -detailed-exitcode -input=false "$@" > /dev/null || rc=$?

case "$rc" in
    0) echo "NOOP" ;;
    2) echo "DRIFT" ;;
    *) echo "ERROR (terraform exit $rc)" ;;
esac
exit "$rc"
```

```bash
chmod +x noop-check.sh
```

Vì sao:

- `-detailed-exitcode`: 0 = không đổi, 1 = lỗi, 2 = có thay đổi.
- `set -e` sẽ giết script ngay khi plan trả 2. `|| rc=$?` bắt mã thoát lại: vế phải
  của `||` chỉ chạy khi lệnh trái thất bại, và cả dòng được coi là thành công.
- `> /dev/null` giấu output thường; lỗi vẫn ra stderr nên vẫn đọc được.
- `"$@"` chuyển nguyên mọi tham số (ví dụ `-var ...`) sang `terraform plan`.

## Chạy các mission

Trước mỗi `apply`/`destroy`: ghi `M<n> expect: ...` vào `notes.md`. Sau đó ghi
`M<n> actual: ...`. Ghi ngắn, kiểu `9 create; vpc trước, rồi subnet...`.

Lệnh liệt kê hành động theo từng địa chỉ (dùng ở M3, M4, M6):

```bash
plan_actions() { terraform show -json tfplan | jq -r '.resource_changes[] | select(.change.actions != ["no-op"]) | "\(.change.actions | join(",")) \(.address)"'; }
```

Hàm bash này chỉ sống trong terminal hiện tại; mở terminal mới thì gõ lại.

### M1 — Build, graph, apply

```bash
terraform init && terraform fmt -check -recursive && terraform validate
```

```bash
terraform graph | dot -Tsvg > graph-before.svg 2>/dev/null && start graph-before.svg
```

(`2>/dev/null` giấu cảnh báo font vô hại của Graphviz; `start` mở file bằng trình
xem mặc định của Windows.)

```bash
terraform plan -out=tfplan
```

```bash
terraform apply tfplan
```

```bash
terraform state list && terraform state show 'module.cluster.terraform_data.eks' && terraform output
```

<details>
<summary>Đối chiếu M1</summary>

- `init` không tải provider nào; nó chỉ tạo `.terraform/modules/` để ghi nhận hai
  module local.
- `Plan: 9 to add`: 1 VPC + 2 public subnet + 2 DB subnet + 1 S3 endpoint + EKS +
  OIDC + nodes.
- Graph có 6 cạnh: 3 tài nguyên network trỏ về `vpc`; `eks` trỏ về
  `public_subnets`; `oidc_provider` và `system_nodes` trỏ về `eks`. Không có cạnh
  thẳng `eks -> vpc` vì đã có đường đi qua subnet (Terraform rút gọn cạnh thừa).
- Thứ tự tạo: `vpc` trước; S3 endpoint và 4 subnet chạy song song; rồi `eks`;
  cuối cùng `oidc_provider` và `system_nodes` song song.
- `state show` có trường `id` (UUID) không hề có trong code: đó là thứ state nhớ hộ
  bạn. Trên AWS đó sẽ là `vpc-...`, `subnet-...`, ARN cluster.

</details>

### M2 — Idempotency

```bash
./noop-check.sh; echo "exit=$?"
```

<details>
<summary>Đối chiếu M2</summary>

`NOOP`, `exit=0`. Code, state và "hạ tầng" khớp nhau, nên apply lần nữa không làm gì.

</details>

### M3 — Upgrade EKS 1.35 -> 1.36

Sửa `default = "1.35"` thành `"1.36"` trong `variables.tf`. Upgrade thật cũng đi
qua sửa code và review, không phải gõ `-var` tay.

```bash
terraform plan -out=tfplan && plan_actions
```

```bash
terraform apply tfplan && ./noop-check.sh
```

<details>
<summary>Đối chiếu M3</summary>

- `update module.cluster.terraform_data.eks` và
  `update module.cluster.terraform_data.system_nodes`. Không có `delete,create` nào.
- `system_nodes` bị update dù bạn không đụng vào nó: nó đọc `eks.output.version`,
  giá trị này "known after apply" nên Terraform phải cập nhật nó sau `eks`. Đúng thứ
  tự upgrade EKS: control plane trước, node sau.
- `oidc_provider` không đổi: id của cluster giữ nguyên.
- Sau apply: `NOOP`.

</details>

### M4 — Đổi tên cluster: blast radius

```bash
terraform plan -var cluster_name=zero-drift-v2 -out=tfplan && plan_actions
```

Đếm số `delete,create` trước khi apply. Rồi apply và nhìn thứ tự:

```bash
terraform apply tfplan
```

Quay về tên cũ: chỉ cần plan và apply **không** có `-var`, vì `-var` không được lưu
lại ở đâu cả.

```bash
terraform apply && ./noop-check.sh
```

<details>
<summary>Đối chiếu M4</summary>

- 3 `delete,create`: `eks`, `oidc_provider`, `system_nodes`.
- 6 `update`: VPC, 4 subnet, S3 endpoint, chỉ vì tên (tag) đổi. Không có cái nào bị
  tạo lại.
- Thứ tự apply: xóa `oidc_provider` và `system_nodes`, rồi xóa `eks`; sửa network;
  rồi tạo `eks` mới, sau đó `oidc_provider` và `system_nodes`. Mặc định Terraform
  **xóa trước, tạo sau**.
- Trên AWS: cluster cũ và mọi workload mất, OIDC issuer mới làm hỏng mọi IAM trust
  policy của IRSA, khoảng 20 phút trở lên mới dựng lại. Plan đã cảnh báo bằng
  ký hiệu `-/+` và dòng `# ... must be replaced`.

</details>

### M5 — Guardrail

```bash
terraform plan -var enable_nat_gateway=true; echo "exit=$?"
```

```bash
terraform plan -var region=ap-southeast-1; echo "exit=$?"
```

```bash
terraform plan -var 'azs=["us-east-1a"]'; echo "exit=$?"
```

```bash
./noop-check.sh
```

<details>
<summary>Đối chiếu M5</summary>

Cả ba đều `exit=1` kèm đúng `error_message` bạn viết, và không có gì bị đụng tới.
`noop-check.sh` vẫn ra `NOOP`.

</details>

### M6 — Cắt tham chiếu

Trong `main.tf`, thay hai dòng có comment bằng giá trị hard-code:

```hcl
  vpc_id             = "vpc-fake"
  subnet_ids         = ["subnet-fake-a", "subnet-fake-b"]
```

```bash
terraform graph | dot -Tsvg > graph-broken.svg 2>/dev/null && start graph-broken.svg
```

```bash
terraform plan -out=tfplan && plan_actions
```

Không apply. Trả hai dòng về như cũ, rồi:

```bash
./noop-check.sh
```

<details>
<summary>Đối chiếu M6</summary>

- Graph mất cạnh `eks -> public_subnets`: cụm `cluster` tách rời khỏi `network`.
  Terraform giờ được phép tạo EKS **song song** với VPC. Trên AWS, EKS sẽ lỗi vì
  subnet chưa tồn tại (hoặc là id giả). Khi destroy, nó có thể xóa VPC trong lúc
  cluster còn bám vào và bị treo.
- Plan: 3 `delete,create` (`eks`, `oidc_provider`, `system_nodes`), vì giá trị
  `vpc_id` trong `triggers_replace` đã đổi.
- Bài học: nối resource bằng tham chiếu, không copy id.
- Sau khi khôi phục: `NOOP`.

</details>

### M7 — Destroy và chứng minh đã sạch

```bash
terraform plan -destroy -out=destroy.tfplan
```

```bash
terraform apply destroy.tfplan
```

```bash
terraform state list | wc -l && jq '.resources | length' terraform.tfstate
```

<details>
<summary>Đối chiếu M7</summary>

- 9 `destroy`, theo thứ tự ngược của graph: `oidc_provider` và `system_nodes` trước
  `eks`; `eks` trước `public_subnets`; mọi thứ trước `vpc`. DB subnet và S3 endpoint
  không phụ thuộc EKS nên có thể bị xóa xen kẽ, song song với phần cluster.
- Hai lệnh đếm đều ra `0`. File `terraform.tfstate` vẫn còn nhưng trống: "state
  trống" khác với "không có file state".

</details>

Bonus 3 phút (nên làm): lặp lại M6 khi state đang trống. Hard-code hai dòng, chạy
`terraform apply`, nhìn `eks` được tạo **trước** các subnet. Rồi `terraform destroy`,
khôi phục hai dòng.

## Explain-back và bàn giao

Viết vào `notes.md` bằng lời của bạn, 1–2 câu mỗi ý:

1. State giữ gì mà file `.tf` không có?
2. Thay đổi nào ở M3/M4 sẽ làm mất cluster EKS thật, và plan cảnh báo bằng gì?
3. `NOOP` chứng minh được gì, và **không** chứng minh được gì về AWS?

Gửi reviewer: `terraform version`, `notes.md`, `graph-before.svg`,
`graph-broken.svg`, `noop-check.sh`, output của `plan_actions` ở M3/M4, dòng lỗi M5
và hai số đếm M7. Không gửi `terraform.tfstate`, `tfplan`, `destroy.tfplan`.

Review xong và được chấp nhận thì mới xóa thư mục chạy:

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/playground && rm -rf "runs/TF-T01-$(date +%Y%m%d)-01"
```
