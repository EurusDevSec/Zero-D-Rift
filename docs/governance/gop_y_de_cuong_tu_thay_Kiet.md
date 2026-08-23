PHIẾU GÓP Ý CHI TIẾT ĐỀ CƯƠNG BÁO CÁO TỐT NGHIỆP
Đề tài số 6 – Sinh viên Lê Văn Hoàng
Ngành Công nghệ thông tin
Sinh viên
Lê Văn Hoàng
MSSV – Lớp
2224802010279 – D22CNTT02
Tên đề tài
Nghiên cứu và xây dựng nền tảng Internal Developer Platform (IDP) hỗ trợ phát triển ứng dụng AI trên nền tảng AWS
Giảng viên hướng dẫn
ThS. Nguyễn Trung Kiệt
Kết luận sơ bộ
Duyệt có điều kiện sau khi thu hẹp phạm vi, làm rõ tiêu chí đo lường và hoàn thiện kế hoạch chi phí thực nghiệm

1. Đánh giá tổng quan
Đây là đề tài có tính mới, độ khó cao và bám sát xu hướng Platform Engineering, Cloud Native, MLOps/AI Platform và FinOps. Nội dung có chiều sâu kỹ thuật tốt, thể hiện sinh viên đã tiếp cận các công nghệ hiện đại như EKS, Kubernetes, Crossplane, KEDA, Karpenter, OpenCost, ArgoCD và Kyverno.
Tuy nhiên, phạm vi hiện tại tương đương một dự án hạ tầng doanh nghiệp hoàn chỉnh hơn là một báo cáo tốt nghiệp cá nhân. Đề cương đang đồng thời đặt ra bốn bài toán lớn: xây dựng IDP, cấp phát tài nguyên AI tự phục vụ, tối ưu chi phí, và tự phục hồi dữ liệu có trạng thái. Nếu không thu hẹp, sinh viên có nguy cơ dành phần lớn thời gian cho cấu hình hạ tầng, xử lý lỗi dịch vụ AWS và chi phí vận hành mà không hoàn thành được các thực nghiệm cốt lõi.
Nhận định: Đề tài có giá trị chuyên môn cao, nhưng chỉ nên được duyệt khi sinh viên chốt một MVP rõ ràng, giới hạn dịch vụ AWS, có ngân sách thử nghiệm và đưa ra bộ chỉ số định lượng có thể đo được.

2. Điểm mạnh của đề cương
Tên đề tài rõ hướng nghiên cứu và công nghệ triển khai.
Bài toán xuất phát từ các pain point thực tế: cấp phát chậm, lãng phí cloud, configuration drift và phục hồi sự cố.
Có sản phẩm POC cụ thể và có khả năng trình diễn tốt trước hội đồng.
Có hướng đánh giá bằng thời gian cấp phát, MTTR và khả năng thu hồi tài nguyên.
Kết hợp được kiến thức cloud, DevOps, Kubernetes, bảo mật, tự động hóa và vận hành hệ thống AI.
Sản phẩm đầu ra gồm mã nguồn IaC, runbook và architecture diagram, phù hợp chuẩn kỹ thuật doanh nghiệp.
3. Các vấn đề cần chỉnh sửa trước khi duyệt
Phạm vi quá rộng: Đề tài đang bao gồm IDP, multi-tenancy, IAM, GitOps, Crossplane, kro, autoscaling, FinOps, chaos engineering và stateful self-healing. Cần chọn một luồng chính và hai luồng hỗ trợ.
Khái niệm “IDP” chưa được định nghĩa theo sản phẩm: Cần mô tả rõ người dùng cuối là developer, ML engineer hay platform engineer; họ thao tác qua giao diện, API hay Git repository; control plane cung cấp những golden paths nào.
Mục tiêu “dưới 5 phút” chưa có baseline: Phải xác định loại tài nguyên nào được cấp phát dưới 5 phút và so sánh với quy trình thủ công nào. Không thể dùng một con số chung cho EKS, RDS, OpenSearch và GPU node.
FinOps chưa có công thức đo: Cần xác định baseline cost, workload profile, thời gian nhàn rỗi, tỷ lệ tiết kiệm và cách tính chi phí trước/sau scale-to-zero.
Self-healing dữ liệu đang mô tả quá mạnh: Kubernetes/GitOps có thể tự phục hồi cấu hình, nhưng phục hồi dữ liệu có trạng thái cần backup, snapshot, PITR và quy trình restore riêng. Cần tách “configuration self-healing” và “data recovery”.
Dịch vụ AWS sử dụng quá nhiều: EKS, S3, RDS, OpenSearch Serverless, Bedrock và GPU node có thể tạo chi phí cao. Cần giới hạn một workload AI chính và một data service chính.
Chưa nêu ngân sách và chiến lược kiểm soát chi phí: Phải có dự toán AWS, tagging, budget alert, thời gian bật/tắt cụm và phương án teardown toàn bộ tài nguyên.
Multi-tenancy và bảo mật chưa đủ cụ thể: Cần xác định tenant là namespace, AWS account hay virtual cluster; cơ chế cô lập dữ liệu, quota và quyền truy cập phải được mô tả rõ.
Thiếu bộ chỉ số đánh giá đầy đủ: Ngoài provisioning time và MTTR, cần có success rate, drift detection time, recovery point, cost saving, resource utilization và policy violation rate.
Chưa có phương án dự phòng demo: POC phụ thuộc Internet, AWS quota, GPU capacity và dịch vụ managed. Cần có video, log, dashboard và kết quả thực nghiệm lưu sẵn.
4. Góp ý chi tiết theo từng mục
4.1. Tên đề tài
Tên hiện tại đúng hướng nhưng còn rộng. Cụm từ “hỗ trợ phát triển ứng dụng AI” có thể khiến hội đồng kỳ vọng đầy đủ MLOps lifecycle. Nên thể hiện đây là nền tảng cấp phát và quản trị hạ tầng cho workload AI.
Tên đề xuất 1: “Nghiên cứu và xây dựng nền tảng Internal Developer Platform hỗ trợ cấp phát và quản trị hạ tầng ứng dụng AI trên AWS”.
Tên đề xuất 2: “Xây dựng nền tảng tự phục vụ hạ tầng AI trên AWS sử dụng Kubernetes, Crossplane và GitOps”.
Tên đề xuất 3 (nếu thu hẹp mạnh): “Xây dựng nền tảng tự động cấp phát và tối ưu chi phí cho workload RAG trên Amazon EKS”.
4.2. Mục tiêu nghiên cứu
Mục tiêu tổng quát đề xuất: Xây dựng POC Internal Developer Platform cho phép người dùng tự phục vụ một số mẫu hạ tầng AI được chuẩn hóa trên AWS, đồng thời hỗ trợ quan sát chi phí, thu hồi tài nguyên nhàn rỗi và tự động khôi phục cấu hình về trạng thái khai báo mong muốn.
Mục tiêu cụ thể nên chỉnh thành:
Thiết kế control plane và mô hình self-service cho tối đa 2 golden paths: môi trường RAG và môi trường huấn luyện thử nghiệm.
Xây dựng blueprint cấp phát tự động bằng Crossplane/kro và quản lý trạng thái bằng GitOps.
Đo thời gian cấp phát, tỷ lệ cấp phát thành công và mức giảm thao tác thủ công so với baseline.
Tích hợp OpenCost và cơ chế scale-down/scale-to-zero để đo mức tiết kiệm chi phí cho workload nhàn rỗi.
Thử nghiệm configuration drift và phục hồi cấu hình; nếu nghiên cứu dữ liệu, chỉ chọn một cơ chế backup/restore cho một dịch vụ cụ thể.
Đánh giá tính khả thi, giới hạn kỹ thuật và chi phí của POC.
4.3. Nội dung và phạm vi nghiên cứu
Phạm vi khuyến nghị:
Một cụm Amazon EKS dùng cho POC, không xây dựng production-grade multi-region.
Tối đa 2 tenant được mô phỏng bằng namespace, quota và RBAC/IRSA.
Hai blueprint: RAG sandbox và batch training sandbox; không triển khai đầy đủ toàn bộ lifecycle MLOps.
Một dịch vụ dữ liệu chính, ưu tiên S3 + vector store hoặc RDS; không nên đồng thời dùng RDS và OpenSearch Serverless nếu không cần thiết.
Self-healing bắt buộc ở mức cấu hình; data recovery chỉ nên là một kịch bản giới hạn và đo được.
Không phát triển giao diện portal phức tạp; có thể dùng GitOps workflow, Backstage tối giản hoặc form/API đơn giản.
4.4. Phương pháp nghiên cứu và công nghệ
Cần thay mô tả công nghệ bằng một kiến trúc đã chốt, tránh liệt kê công nghệ theo xu hướng. Đặc biệt, “kro (AWS Controllers)” đang chưa chính xác về cách diễn đạt; cần làm rõ kro dùng để định nghĩa resource graph, còn AWS resource provisioning do Crossplane provider hoặc ACK đảm nhiệm.
Nên xác định rõ phiên bản Kubernetes, cách tạo EKS, vùng AWS, loại node, chính sách IAM, repository GitOps, công cụ thu thập log/metric và phương án lưu kết quả thực nghiệm.
4.5. Sản phẩm dự kiến
Sản phẩm cần được chuyển từ mô tả chung thành các deliverable có thể nghiệm thu:
Bộ mã nguồn IaC và manifests có cấu trúc, có README và script teardown.
Hai blueprint self-service hoạt động và có input/output rõ ràng.
Dashboard chi phí và utilization trước/sau autoscaling.
Kết quả ít nhất 20 lần đo provisioning cho mỗi blueprint.
Kịch bản drift và recovery có log thời gian phát hiện, thời gian phục hồi và kết quả cuối.
Runbook triển khai, vận hành, xử lý sự cố và kiểm soát chi phí.
Video demo dự phòng và tập dữ liệu kết quả thực nghiệm.
5. Kiến trúc MVP đề xuất
Tầng
Thành phần đề xuất
Vai trò
Developer experience
Git repository, form/API hoặc portal tối giản
Yêu cầu môi trường AI theo mẫu có sẵn
Control plane
ArgoCD + Crossplane + kro
Quản lý desired state và hợp thành tài nguyên
Governance
Kyverno, RBAC, IRSA, ResourceQuota
Kiểm soát chính sách, quyền và giới hạn tenant
Runtime
Amazon EKS + Karpenter/KEDA
Chạy workload AI và điều phối tài nguyên
Observability/FinOps
OpenCost + CloudWatch/Prometheus
Theo dõi chi phí, tài nguyên và thời gian phản hồi
Data
S3 và một data service được chọn
Lưu dữ liệu, artifact hoặc vector/index
Recovery
ArgoCD reconcile + snapshot/backup giới hạn
Phục hồi cấu hình và một kịch bản dữ liệu cụ thể

6. Bộ chỉ số đánh giá đề xuất
Nhóm
Chỉ số
Cách đo
Mục tiêu tham khảo
Provisioning
Provisioning time
Từ lúc gửi yêu cầu đến khi môi trường ready
Đặt theo từng blueprint, không dùng một ngưỡng chung
Reliability
Provisioning success rate
Số lần cấp phát thành công / tổng số lần
≥ 90–95% trong môi trường POC
Automation
Manual steps reduced
So sánh số bước thủ công trước và sau IDP
Giảm rõ rệt và có bảng đối chiếu
FinOps
Cost saving ratio
(Chi phí baseline – chi phí tối ưu) / baseline
Đo trong workload mô phỏng cố định
Utilization
Node/Pod utilization
CPU, memory, GPU nếu có
So sánh trước/sau autoscaling
Drift
Detection and reconciliation time
Thời gian từ thay đổi trái phép đến restored state
Báo cáo trung bình và độ lệch chuẩn
Recovery
MTTR/RTO
Thời gian khôi phục dịch vụ
Đo cho từng kịch bản
Data
RPO hoặc mức mất dữ liệu
Khoảng dữ liệu có thể mất khi restore
Chỉ dùng nếu thật sự thực hiện backup/restore
Governance
Policy violation detection
Số vi phạm bị chặn/phát hiện
Theo bộ policy định nghĩa trước

7. Kịch bản thực nghiệm bắt buộc
Cấp phát RAG sandbox từ một yêu cầu self-service; ghi lại toàn bộ thời gian và trạng thái tài nguyên.
Cấp phát training sandbox dạng batch; workload kết thúc thì pod/node được thu hồi theo chính sách.
So sánh chi phí giữa cấu hình luôn bật và cấu hình có autoscaling/scale-to-zero trên cùng workload.
Can thiệp trái phép vào manifest hoặc tài nguyên Kubernetes để đo thời gian phát hiện và reconcile.
Xóa hoặc làm hỏng một thành phần có trạng thái trong phạm vi đã chọn, sau đó thực hiện restore theo runbook.
Kiểm tra tenant isolation bằng namespace, quota, RBAC và IRSA.
Kiểm tra policy-as-code: chặn image không hợp lệ, resource không có limit hoặc tài nguyên thiếu tag/label.
Thực hiện teardown và xác nhận không còn tài nguyên phát sinh chi phí ngoài ý muốn.
8. Kế hoạch thực hiện 14 tuần
Tuần
Nội dung
Kết quả cần đạt
1–2
Chốt phạm vi, baseline, ngân sách, kiến trúc và account/quota AWS
Đề cương chỉnh sửa, architecture diagram, cost plan
3
Khởi tạo EKS, repository GitOps, logging và tagging
Cụm nền tảng hoạt động, script teardown
4–5
Cài ArgoCD, Crossplane/kro và xây blueprint 1
RAG sandbox cấp phát được
6
Xây blueprint 2 và tenant isolation
Training sandbox, RBAC/quota
7–8
Tích hợp Karpenter/KEDA và OpenCost
Autoscaling và dashboard chi phí
9
Tích hợp Kyverno và bộ policy
Kịch bản governance hoạt động
10
Thiết kế drift/reconcile và backup/restore giới hạn
Hai kịch bản recovery hoàn chỉnh
11–12
Chạy thực nghiệm lặp lại và thu số liệu
Dataset kết quả, log, biểu đồ
13
Hoàn thiện báo cáo, runbook và video demo
Bản báo cáo gần hoàn chỉnh
14
Kiểm thử tổng thể, chuẩn bị slide và phản biện
Demo ổn định, phương án dự phòng

9. Câu hỏi phản biện sinh viên cần chuẩn bị
IDP của đề tài khác gì so với một bộ script Terraform hoặc Kubernetes manifests?
Người dùng cuối của nền tảng là ai và thao tác self-service bằng cách nào?
Vì sao chọn Crossplane và kro; vai trò của từng công cụ là gì?
Mốc dưới 5 phút áp dụng cho tài nguyên nào, đo từ thời điểm nào đến thời điểm nào?
Scale-to-zero được áp dụng ở pod, node hay dịch vụ dữ liệu; giới hạn là gì?
Làm thế nào chứng minh hệ thống tiết kiệm chi phí thay vì chỉ giảm tài nguyên?
Configuration self-healing khác data self-healing như thế nào?
Kịch bản phục hồi dữ liệu bảo đảm RPO/RTO ra sao?
Multi-tenancy được cô lập bằng cơ chế nào và đã kiểm thử rò rỉ quyền chưa?
Nếu AWS quota, GPU capacity hoặc dịch vụ managed gặp lỗi, demo dự phòng là gì?
Chi phí dự kiến của toàn bộ POC và biện pháp tránh phát sinh ngoài kiểm soát?
Đóng góp riêng của sinh viên nằm ở kiến trúc, blueprint, workflow hay kết quả đánh giá?
10. Yêu cầu chỉnh sửa trước khi giảng viên duyệt
Chọn một trong các tên đề tài đề xuất hoặc viết lại theo hướng thu hẹp.
Chốt tối đa 2 golden paths và một cơ chế recovery dữ liệu giới hạn.
Bổ sung sơ đồ kiến trúc và mô tả rõ luồng self-service.
Làm rõ baseline thủ công và bộ chỉ số đo lường.
Bổ sung ngân sách AWS, tagging, budget alert và teardown plan.
Phân biệt configuration drift recovery và data backup/restore.
Mô tả multi-tenancy, IAM/IRSA, quota và policy-as-code cụ thể.
Bổ sung danh sách kịch bản thực nghiệm và số lần đo.
Chuẩn bị phương án demo dự phòng bằng video, log và dashboard đã lưu.
Rà soát thuật ngữ kỹ thuật và cách dùng kro, Crossplane, ACK, GitOps cho chính xác.
11. Kết luận của giảng viên hướng dẫn
Đề tài có chiều sâu kỹ thuật tốt, phù hợp với sinh viên có năng lực Cloud/DevOps và có khả năng tạo ra sản phẩm nổi bật. Tuy nhiên, khối lượng hiện tại quá lớn, chi phí cao và phụ thuộc nhiều dịch vụ AWS. Giảng viên đề xuất duyệt có điều kiện, yêu cầu sinh viên thu hẹp thành một POC IDP với tối đa hai blueprint, một bài toán FinOps định lượng và một kịch bản recovery được giới hạn rõ ràng.
Mức đánh giá đề xuất: Duyệt có điều kiện sau khi chỉnh sửa đề cương và trình bày được kiến trúc, ngân sách, baseline, bộ chỉ số và kế hoạch thực nghiệm.
