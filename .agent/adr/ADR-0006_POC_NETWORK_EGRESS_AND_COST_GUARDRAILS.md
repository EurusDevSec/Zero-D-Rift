---
id: ADR-0006
title: Cost-bounded PoC network egress baseline
status: PROPOSED
date: 2026-09-28
---

# Context

Zero D-Rift có spending envelope 100 USD. NAT Gateway và một tập lớn interface
VPC endpoints tạo fixed hourly cost ngay cả khi workload đã scale về 0. PoC vẫn
cần outbound access để pull image/package và gọi selected AWS APIs, đồng thời RDS
không được public-accessible.

Quyết định chỉ áp dụng cho một-account, một-Region PoC. Nó không phải production
network recommendation.

# Proposed decision

P2 bootstrap mặc định:

1. Không tạo NAT Gateway.
2. System và ephemeral workload nodes chạy trong public subnets, có public IPv4
   để outbound qua Internet Gateway.
3. Node security groups không cho unsolicited inbound từ Internet; administrative
   SSH không nằm trong golden path.
4. RDS nằm trong private DB subnets và `publicly_accessible=false`.
5. Tạo S3 gateway endpoint cho route tables cần S3 artifact/checkpoint vì gateway
   endpoint không có additional endpoint charge.
6. EKS API bật private access; public access chỉ bật khi workstation cần và phải
   giới hạn approved CIDR.
7. Interface endpoints hoặc NAT Gateway chỉ được thêm sau khi dependency inventory,
   security need và exact Region pricing chứng minh baseline không đủ.

Region, subnet CIDR, exact endpoint policy, EKS endpoint CIDR và selected service
dependencies vẫn `UNVERIFIED`. ADR chỉ chuyển sang `ACCEPTED` sau owner review và
acceptance checks bên dưới.

# Why this baseline

- Loại NAT Gateway fixed hourly/data-processing charge khỏi default PoC.
- General outbound giúp bootstrap/controller experiment không cần đoán trước mọi
  image registry và external endpoint.
- S3 checkpoint/artifact path dùng gateway endpoint không có additional charge.
- Giữ RDS private và không mở inbound vào worker nodes.
- Trade-off public IPv4 được đo trực tiếp, thay vì ẩn sau tuyên bố “public subnet
  miễn phí”.

# Alternatives considered

## Private nodes with NAT Gateway

Đơn giản cho general outbound và tránh public IPv4 trên node, nhưng NAT tính theo
available hour và processed GB. Một NAT tạo availability/cross-AZ trade-off; NAT
theo mỗi AZ làm fixed cost tăng. Không chọn làm default trong 100 USD envelope.

## Private nodes with interface endpoints only

Cung cấp private AWS API path nhưng mỗi interface endpoint có ENI-hour/AZ và data
processing charge, không thay general Internet egress và cần inventory chính xác
cho ECR, STS, EC2, SQS, Secrets Manager, CloudWatch cùng dependency khác. Chỉ chọn
khi security requirement và priced comparison biện minh.

## Public AWS service endpoints without S3 gateway endpoint

Ít Terraform resource hơn nhưng bỏ qua một no-additional-charge path cho lượng S3
traffic chính của project. Không chọn.

# Consequences

## Positive

- Chi phí mạng mặc định chủ yếu là public IPv4 và observed data transfer.
- Teardown ít resource fixed-cost hơn và dễ inventory hơn.
- Golden path vẫn có general outbound trong giai đoạn compatibility/integration.

## Risks and controls

- Public IPv4 tăng exposure: không mở inbound, giới hạn SG, không SSH, bắt buộc
  IMDS controls và runtime negative tests.
- Public EKS API nếu cần phải giới hạn CIDR; private access vẫn bật.
- Public IPv4 không miễn phí và phải nằm trong daily inventory.
- Nếu workload cần private-only network, baseline phải được thay qua ADR review,
  không vá ngầm bằng NAT Gateway.
- NetworkPolicy/VPC CNI enforcement và IAM vẫn là lớp độc lập; subnet design không
  tự tạo tenant isolation.

# Evidence

- `docs/finops/COST_PLAN.md`
- `docs/security/THREAT_MODEL.md`
- [AWS VPC pricing](https://aws.amazon.com/vpc/pricing/)
- [AWS NAT Gateway pricing](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html)
- [AWS S3 gateway endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html)
- [AWS PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/)

# Acceptance checks

1. Owner giải thích được vì sao Pod scale-to-zero không loại public IPv4/NAT/
   endpoint fixed cost.
2. Account và Region được chọn; credit và applied quota được xác minh.
3. Terraform plan chứng minh không có NAT Gateway ngoài explicit approved change.
4. Route tables và S3 gateway endpoint policy được review.
5. Node SG không có Internet ingress; EKS public endpoint CIDR được giới hạn.
6. L3 smoke test chứng minh image pull, STS, S3, controller API và DNS paths cần
   thiết hoạt động; failed path được ghi lại.
7. Exact estimate vẫn nằm trong network envelope và teardown inventory liệt kê
   public IPv4, IGW, endpoints, ENI cùng load balancers.

# Revisit conditions

- Security review yêu cầu private-only worker nodes.
- Required dependency không thể truy cập an toàn từ baseline.
- NAT/interface endpoint priced comparison trong selected Region rẻ hơn cho observed traffic.
- Public IPv4 hoặc data-transfer burn-rate đe dọa 10 USD network envelope.
- Scope đổi khỏi one-account/one-Region short-lived PoC.
