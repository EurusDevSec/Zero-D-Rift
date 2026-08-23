TRƯỜNG ĐẠI HỌC THỦ DẦU MỘT
CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM
VIỆN CÔNG NGHỆ SỐ
Độc lập- Tự do- Hạnh phúc

TP.HCM, ngày     tháng       năm 202…

ĐỀ CƯƠNG ĐỀ TÀI BÁO CÁO TỐT NGHIỆP

1. Thông tin sinh viên

- Họ và tên: Lê Văn Hoàng
- Mã số sinh viên: 2224802010279
- Lớp: D22CNTT02
- Khóa: 2022-2027
- Số điện thoại: 0399354603
- Giảng viên hướng dẫn: Nguyễn Trung Kiệt

2. Tên đề tài đăng ký
Nghiên cứu và xây dựng nền tảng Internal Developer Platform hỗ trợ cấp phát và quản trị hạ tầng ứng dụng AI trên AWS.

3. Mục tiêu nghiên cứu
  Thiết kế một nền tảng quản trị hạ tầng tập trung (Control Plane / Internal Developer Platform - IDP) nhằm thay thế các quy trình cấp phát tài nguyên điện toán đám mây thủ công truyền thống.
  Tối ưu hóa thời gian triển khai môi trường phát triển (Zero-Touch Provisioning), rút ngắn thời gian cung cấp các cụm hạ tầng AI phức tạp từ vài ngày (3–5 ngày) xuống còn dưới 5 phút thông qua quy trình tự phục vụ GitOps (Git-based Declarative YAML).
  Xây dựng cơ chế quản trị chi phí động (Dynamic FinOps) nhằm triệt tiêu sự lãng phí tài nguyên của các mô hình AI chạy nhàn rỗi thông qua khả năng tự động thu hẹp (Scale-to-zero) với KEDA và điều phối máy GPU Spot tiết kiệm 70% chi phí với Karpenter.
  Đảm bảo an toàn dữ liệu và tính sẵn sàng của hệ thống bằng 2 cơ chế độc lập: Tự động vá lỗi bảo mật (SecOps Auto-Remediation đè lại Security Group rò rỉ dưới 60s qua Crossplane Reconciliation Loop) và Tự phục hồi dữ liệu từ bản sao lưu gần nhất (Stateful Data Recovery từ RDS Automated Snapshot & Dynamic Secrets Injection dưới 2 phút).

4. Nội dung, phạm vi nghiên cứu
Nội dung nghiên cứu:
Khảo sát mô hình Platform Engineering và các vấn đề thực tiễn (Pain points) trong vận hành hạ tầng AI tại doanh nghiệp (Delivery Bottleneck, Cloud Waste, Shadow IT & Configuration Drift, GPU Hoarding).
Thiết kế kiến trúc hệ thống đa người dùng (Multi-Tenancy) và phân quyền bảo mật tối giản thông qua luồng IAM IRSA (IAM Roles for Service Accounts) gắn động theo từng Namespace.
Phát triển các mẫu cấp phát tài nguyên tự động (02 Golden Path API Blueprints) bằng việc kết hợp Kubernetes, Crossplane và kro.
Tích hợp các giải pháp Autoscaling chuyên sâu cho AI Workloads (KEDA, Karpenter Spot Orchestration) và công cụ giám sát chi phí (OpenCost).
Thiết lập kịch bản kiểm thử độ bền & bảo mật (Chaos & SecOps Engineering) để đánh giá khả năng tự khôi phục cấu hình bảo mật và phục hồi cơ sở dữ liệu trên Cloud.

Phạm vi nghiên cứu:
Hệ thống lõi được triển khai trên 01 cụm Amazon EKS (Elastic Kubernetes Service) cho PoC.
Đối tượng người dùng cuối (Dev AI / ML Engineers) thao tác tự phục vụ 100% qua GitOps Workflow (commit declarative YAML manifest vào Git Repository).
Khoanh vùng 02 Golden Paths (Blueprint) chính: RAG Sandbox Blueprint (Amazon EKS App Pod + AWS S3 Bucket + AWS RDS PostgreSQL với extension pgvector, loại bỏ OpenSearch Serverless) và Batch Training Sandbox Blueprint (EKS GPU Node điều phối động bởi Karpenter Spot Orchestration + KEDA Scale-to-Zero).
Cô lập tối đa 02 Tenants được mô phỏng bằng Kubernetes Namespace, ResourceQuota, NetworkPolicies và IAM IRSA.

5. Phương pháp nghiên cứu / Công nghệ dự kiến sử dụng
Phương pháp nghiên cứu:
Nghiên cứu lý thuyết: Tổng hợp, phân tích các tài liệu chuyên ngành về Cloud Native Architecture, Platform Engineering và mô hình FinOps.
Phương pháp thực nghiệm (Proof of Concept - PoC): Trực tiếp xây dựng, cấu hình hệ thống trên môi trường AWS thực tế; phát triển 80% thời gian trên môi trường Kubernetes cục bộ (k3d/kind) để tiết kiệm chi phí; chỉ khởi tạo Amazon EKS thực tế trong đợt thử nghiệm đo lường 20 lần để thu thập bộ chỉ số định lượng.

Công nghệ dự kiến sử dụng:
Nền tảng Cloud: Amazon Web Services (EKS, S3, RDS pgvector, Bedrock, Spot Instances).
Control Plane Core: Kubernetes (v1.30+), ArgoCD (GitOps).
Resource Graph Engine: kro (AWS Controllers) — Định nghĩa đồ thị tài nguyên thành Custom Resource Definition (CRD).
Infrastructure Provisioning Engine: Crossplane & Crossplane Provider-AWS — Trực tiếp thựcthi API call khởi tạo và đối soát 24/7 trên AWS Cloud.
FinOps & Autoscaling: OpenCost, Karpenter (Spot Orchestration), KEDA (Event-driven Pod Scale-to-Zero).
Security & Governance: Kyverno (Policy-as-Code Webhook), AWS IAM IRSA (Pod-level Zero-Trust), AWS Secrets Manager, ExternalDNS.

6. Sản phẩm dự kiến
  01 Quyển báo cáo chi tiết về thiết kế, kiến trúc và kết quả thực nghiệm hệ thống nền tảng IDP.
  Bộ mã nguồn cấu hình hạ tầng (Infrastructure as Code - Manifests/Blueprints, Kyverno Policies) được đóng gói và lưu trữ quản lý trên GitHub kèm file README.md và Script Teardown 1-click.
  01 Hệ thống thực nghiệm (PoC) hoạt động thực tế trên AWS EKS, đáp ứng và trình diễn thành công 03 kịch bản: Cấp phát tự phục vụ (Self-Service), Kỷ luật Bảo mật & Tự chữa lành Phá hoại kép (SecOps & Stateful Healing), và Thu hồi tài nguyên nhàn rỗi (FinOps Auto-Recycling).
  Bộ dữ liệu số liệu thực nghiệm đo lường 20 lần cấp phát (Provisioning Time <5m, MTTR <2m, Drift Remediation <60s, Cost Saving Ratio 60-70%).
  Bộ sản phẩm dự phòng (Fallback Package): 01 Video Live Demo quay sẵn (Full HD) và Tập dữ liệu Log & Dashboard lưu trữ offline.
  Tài liệu hướng dẫn triển khai và vận hành hệ thống (Runbook & Architecture Diagram) chuẩn doanh nghiệp.
