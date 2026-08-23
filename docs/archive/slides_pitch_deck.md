# PITCH DECK SLIDE OUTLINE — ZERO D-RIFT
## Nghiên cứu và xây dựng nền tảng Internal Developer Platform hỗ trợ cấp phát và quản trị hạ tầng ứng dụng AI trên AWS
**Báo cáo Đồ án Tốt nghiệp — Viện Công nghệ Số, Trường Đại học Thủ Dầu Một**

---

### SLIDE 1: TIÊU ĐỀ (TITLE & HOOK)

#### 🖼️ [Nội dung hiển thị trên Slide]
```text
ĐỀ TÀI: NGHIÊN CỨU VÀ XÂY DỰNG NỀN TẢNG INTERNAL DEVELOPER PLATFORM 
HỖ TRỢ CẤP PHÁT VÀ QUẢN TRỊ HẠ TẦNG ỨNG DỤNG AI TRÊN AWS

Thương hiệu / Codename: ZERO D-RIFT (Control Plane & FinOps Engine)

Sinh viên thực hiện: Lê Văn Hoàng (MSSV: 2224802010279) — Lớp D22CNTT02
Giảng viên hướng dẫn: ThS. Nguyễn Trung Kiệt
```

#### 🎙️ [Lời thoại thuyết trình - Speaker Pitch Script]
> "Kính chào Thầy/Cô trong Hội đồng. Hôm nay em xin trình bày đồ án tốt nghiệp với đề tài: **'Nghiên cứu và xây dựng nền tảng Internal Developer Platform hỗ trợ cấp phát và quản trị hạ tầng ứng dụng AI trên AWS'** - Tên thương mại là **Zero D-Rift**. Đồ án này không mang đến một ứng dụng AI đơn thuần, mà mang đến giải pháp giải quyết **3 nỗi đau vận hành lớn nhất** của các doanh nghiệp AI: Dev AI không phải chờ đợi hạ tầng, không làm rò rỉ lỗ hổng bảo mật, và không 'đốt' tiền Cloud vô nghĩa."

---

### SLIDE 2: BÀI TOÁN THỰC TẾ DOANH NGHIỆP (THE PAIN POINTS)

#### 🖼️ [Nội dung hiển thị trên Slide]
```text
3 CUỘC KHỦNG HOẢNG VẬN HÀNH HẠ TẦNG AI

1. 🛑 Nút thắt Tốc độ (Delivery Bottleneck): 
   Dev AI mất 3 - 5 ngày chờ Ops cấp phát cụm máy GPU/RAG qua Jira Ticket.

2. 💸 Lãng phí Cloud (GPU Hoarding): 
   Cấp GPU đắt đỏ (g4dn/p3) nhưng bỏ quên không tắt ban đêm, tốn hàng ngàn USD/tháng.

3. 🔓 Lỗ hổng Tự phát (Shadow IT & Drift): 
   Dev lén mở port Public (0.0.0.0/0) trên Console để test code. Terraform tĩnh "mù tịt" sau khi apply.
```

#### 🎙️ [Lời thoại thuyết trình - Speaker Pitch Script]
> "Chi phí trả cho kỹ sư AI rất đắt, nhưng họ lại phải mất 3 đến 5 ngày ngồi chờ cấp hạ tầng. Nguy hiểm hơn, để lách quy trình chậm chạp, nhiều Dev lén vào AWS Console mở toang luồng mạng. Các công cụ Infrastructure-as-Code truyền thống như Terraform chạy xong là 'mù tịt', biến hệ thống thành con mồi cho Hacker."

---

### SLIDE 3: TẠI SAO LẠI LÀ GIẢI PHÁP NÀY? (THE PARADIGM SHIFT)

#### 🖼️ [Nội dung hiển thị trên Slide]
```text
THAY ĐỔI TƯ DUY: TỪ PIPELINE TĨNH SANG CONTROL PLANE ĐỘNG

❌ KHÔNG PHẢI Web Admin Panel (ClickOps): 
   Chỉ gọi API 1 chiều, không quản trị được vòng đời thực tế.

❌ KHÔNG PHẢI Terraform (IaC Tĩnh): 
   Chỉ kiểm tra trạng thái duy nhất tại thời điểm gõ lệnh `apply`.

✅ GIẢI PHÁP: KUBERNETES CONTROL PLANE (Declarative Engine)
   • Tuyên ngôn trạng thái mong muốn (Declarative State).
   • Vòng lặp đối soát liên tục 24/7 (Continuous Reconciliation Loop).
```

#### 🎙️ [Lời thoại thuyết trình - Speaker Pitch Script]
> "Hệ thống Zero D-Rift của em hoạt động như một 'thực thể sống'. Khác với Terraform chỉ chạy đúng một lần rồi dừng, Control Plane của em chạy vòng lặp đối soát 24/7 trên AWS. Nếu ai đó cố tình vào Console sửa lén cấu hình, hệ thống sẽ phát hiện ngay lập tức và ép AWS phải trở về trạng thái khai báo gốc."

---

### SLIDE 4: SẢN PHẨM THỰC TẾ LÀ CÁI GÌ? (THE PRODUCT & MVP)

#### 🖼️ [Nội dung hiển thị trên Slide]
```text
SẢN PHẨM ZERO D-RIFT MVP: INTERNAL CONTROL PLANE TRÊN AWS EKS

📦 Trải nghiệm Tự phục vụ (GitOps Workflow):
   Dev AI  --->  Commit 1 file YAML manifest (15 dòng) vào Git  --->  Có ngay hạ tầng chuẩn Security

🎯 02 Luồng cấp phát chuẩn hóa (Golden Paths):
   1. RAG Sandbox Blueprint: Amazon EKS + AWS S3 + RDS PostgreSQL/pgvector.
   2. Batch Training Blueprint: Cụm GPU Node tự động điều phối theo tải.
```

#### 🎙️ [Lời thoại thuyết trình - Speaker Pitch Script]
> "Sản phẩm của em là một động cơ IDP chạy ngầm trên AWS EKS. Kỹ sư AI không cần có kiến thức chuyên sâu về VPC hay IAM Policy. Họ chỉ cần nộp đúng 1 file YAML ngắn gọn vào Repository, hệ thống của em sẽ tự động thông dịch và dựng toàn bộ kiến trúc hạ tầng bảo mật trên AWS."

---

### SLIDE 5: TRỌNG TÂM & CHỈ SỐ GIẢI QUYẾT (VALUE & METRICS)

#### 🖼️ [Nội dung hiển thị trên Slide]
```text
BẢNG CHỈ SỐ ĐỊNH LƯỢNG (BASELINE VS ZERO D-RIFT)

| Chỉ số đo lường | Trước kia (Quy trình Thủ công) | Bây giờ (Zero D-Rift IDP) |
| :--- | :--- | :--- |
| ⏱️ Tốc độ cấp phát | 3 – 5 ngày | 🚀 Dưới 5 phút |
| 💰 Chi phí GPU rảnh | On-demand 24/7 (100% chi phí) | 📉 Tiết kiệm 60 - 70% (Scale-to-Zero & Spot) |
| 🛡️ Vá lỗi Bảo mật | Không tự phát hiện (Audit tay) | 🔒 Tự đóng Port < 60 giây |
| 🔄 Khôi phục DB | Khôi phục thủ công 2 – 4 giờ | ⚡ Auto-Restore DB < 2 phút |
| ⚙️ Thao tác kỹ sư | 12 – 15 bước thủ công | 🎯 01 lệnh Git commit |
```

#### 🎙️ [Lời thoại thuyết trình - Speaker Pitch Script]
> "Đây là những số liệu định lượng chứng minh giá trị của hệ thống. Zero D-Rift không chỉ giúp rút ngắn thời gian cấp phát từ vài ngày xuống dưới 5 phút, mà giá trị kinh tế cốt lõi nằm ở khả năng tự 'săn' máy GPU Spot giá rẻ lúc chạy, tự thu hồi Node GPU về 0 khi nhàn rỗi và tự vá lỗ hổng bảo mật trong tích tắc."

---

### SLIDE 6: DANH MỤC CÔNG NGHỆ CỐT LÕI (TECH STACK)

#### 🖼️ [Nội dung hiển thị trên Slide]
```text
KIẾN TRÚC CÔNG NGHỆ CLOUD-NATIVE

🌐 Cloud Infrastructure : AWS EKS, S3, RDS pgvector, AWS Spot Instances
🧠 Control Plane Core   : Crossplane (AWS Provisioning), kro (Blueprint Graph Definition)
💰 Dynamic FinOps       : Karpenter (Spot Orchestration), KEDA (Scale-to-Zero), OpenCost
🛡️ SecOps & GitOps      : ArgoCD (GitOps), AWS IAM IRSA (Zero-Trust), Kyverno, Secrets Manager
```

#### 🎙️ [Lời thoại thuyết trình - Speaker Pitch Script]
> "Toàn bộ bộ khung công nghệ này được xây dựng trên chuẩn Cloud-Native hiện đại nhất. Em sử dụng kro để đóng gói Blueprint, dùng Crossplane làm bộ não quản trị tài nguyên AWS, và sử dụng cặp đôi Karpenter - KEDA làm đôi tay tự động bật/tắt GPU Node theo nhu cầu sử dụng thực tế."

---

### SLIDE 7: THỰC CHỨNG & LIVE DEMO SCENARIOS (PROOF OF CONCEPT)

#### 🖼️ [Nội dung hiển thị trên Slide]
```text
3 KỊCH BẢN KIỂM THỬ THỰC CHỨNG (LIVE DEMO)

1. ⚡ Kịch bản Tốc độ & Bảo mật: 
   Push 1 file YAML ➔ Có ngay môi trường RAG hoàn chỉnh dưới 3 phút (Zero-Trust IRSA).

2. 💥 Kịch bản Phá hoại kép (SecOps & Stateful Healing):
   • Phá hoại: Mở toang Port 0.0.0.0/0 + Xóa sạch Database trên AWS Console.
   • Khôi phục: Tự đóng Port < 60s + Tự khôi phục DB từ Snapshot & tiêm Endpoint mới < 2m.

3. 📊 Kịch bản FinOps: 
   Tự động thu hồi Node GPU (Scale-to-Zero) và gửi Cảnh báo TTL hết hạn qua Slack.

(Cam kết Dự phòng: Bộ Video Demo Full HD + Log Offline lặp lại qua 20 lần đo)
```

#### 🎙️ [Lời thoại thuyết trình - Speaker Pitch Script]
> "Để chứng minh hệ thống vận hành thực tế, em xin trình diễn kịch bản 'Phá hoại kép'. Em sẽ cố tình vào AWS Console mở toang mạng public và xóa luôn Database Production. Hội đồng sẽ thấy hệ thống lập tức phát hiện sai lệch, tự vá lỗi mạng trong 60 giây, và tự khôi phục dữ liệu mà em không cần gõ thêm bất kỳ dòng lệnh nào."

---
