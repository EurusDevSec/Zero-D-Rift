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
Nghiên cứu và xây dựng nền tảng Internal Developer Platform (IDP) hỗ trợ phát triển ứng dụng AI trên nền tảng AWS.
2. Mục tiêu nghiên cứu
  Thiết kế một nền tảng quản trị hạ tầng tập trung (Control Plane) nhằm thay thế các quy trình cấp phát tài nguyên điện toán đám mây thủ công truyền thống.
  Tối ưu hóa thời gian triển khai môi trường phát triển (Zero-Touch Provisioning), rút ngắn thời gian cung cấp các cụm hạ tầng AI phức tạp từ nhiều ngày xuống còn dưới 5 phút.
  Xây dựng cơ chế quản trị chi phí động (Dynamic FinOps) nhằm triệt tiêu sự lãng phí tài nguyên của các mô hình AI chạy nhàn rỗi thông qua khả năng tự động thu hẹp (Scale-to-zero) và điều phối Node thông minh.
  Đảm bảo an toàn dữ liệu và tính sẵn sàng của hệ thống bằng cơ chế tự động đối soát (Anti-drift) và tự phục hồi dữ liệu từ bản sao lưu gần nhất (Stateful Self-healing) khi có sự cố phá hoại hoặc lỗi cấu hình.
3. Nội dung, phạm vi nghiên cứu
Nội dung nghiên cứu:
Khảo sát mô hình Platform Engineering và các vấn đề thực tiễn (Pain points) trong vận hành hạ tầng AI tại doanh nghiệp (Delivery Bottleneck, Cloud Waste, Configuration Drift).
Thiết kế kiến trúc hệ thống đa người dùng (Multi-Tenancy) và phân quyền bảo mật tối giản thông qua luồng IAM IRSA (IAM Roles for Service Accounts).
Phát triển các mẫu cấp phát tài nguyên tự động (API Blueprints) bằng việc kết hợp Kubernetes, Crossplane và kro.
Tích hợp các giải pháp Autoscaling chuyên sâu cho AI Workloads (KEDA, Karpenter) và công cụ giám sát chi phí (OpenCost).
Thiết lập kịch bản kiểm thử độ bền (Chaos Engineering) để đánh giá khả năng tự phục hồi của cơ sở dữ liệu trên Cloud.
Phạm vi nghiên cứu:
Hệ thống lõi được triển khai trên dịch vụ Amazon EKS (Elastic Kubernetes Service).
Đối tượng hạ tầng AWS quản lý tập trung vào 2 luồng công việc AI chính: Huấn luyện mô hình (Model Training với GPU) và Trình tự tăng cường truy xuất RAG (Vector Database, Object Storage).

4. Phương pháp nghiên cứu / Công nghệ dự kiến sử dụng
Phương pháp nghiên cứu:
Nghiên cứu lý thuyết: Tổng hợp, phân tích các tài liệu chuyên ngành về Cloud Native Architecture, Platform Engineering và mô hình FinOps.
Phương pháp thực nghiệm (Proof of Concept - POC): Trực tiếp xây dựng, cấu hình hệ thống trên môi trường AWS thực tế. Tiến hành các kịch bản kiểm thử hiệu năng cấp phát, mô phỏng thảm họa hệ thống để đánh giá thời gian phản hồi (MTTR) và tính chính xác của luồng phục hồi dữ liệu.
Công nghệ dự kiến sử dụng:
Nền tảng Cloud: Amazon Web Services (EKS, S3, RDS, OpenSearch Serverless, Bedrock).
Control Plane & IDP: Kubernetes, Crossplane, kro (AWS Controllers).
FinOps & Autoscaling: OpenCost, Karpenter (Node Autoscaling), KEDA (Event-driven Pod Autoscaling).
Security & Governance: Kyverno (Policy-as-Code Webhook), ArgoCD (GitOps).

5. Sản phẩm dự kiến
  01 Quyển báo cáo chi tiết về thiết kế và kiến trúc hệ thống nền tảng IDP.
  Bộ mã nguồn cấu hình hạ tầng (Infrastructure as Code - Manifests/Blueprints) được đóng gói và lưu trữ quản lý trên GitHub.
  01 Hệ thống thực nghiệm (POC) hoạt động thực tế trên AWS EKS, đáp ứng và trình diễn thành công 03 kịch bản: Cấp phát tự phục vụ (Self-Service), Thu hồi tài nguyên nhàn rỗi (FinOps), và Tự phục hồi cơ sở dữ liệu khi bị can thiệp trái phép (Stateful Self-healing).
  Tài liệu hướng dẫn triển khai và vận hành hệ thống (Runbook & Architecture Diagram) chuẩn doanh nghiệp.
