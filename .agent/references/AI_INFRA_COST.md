# AI infrastructure cost: motivation sources for Zero D-Rift

> **TL;DR** · Để làm gì: nguồn cho phần "Bối cảnh và bài toán" (chi phí hạ tầng AI là rủi ro sống còn) ·
> Trạng thái: tìm 21/11/2026, đa số là nguồn thứ cấp, **phải mở nguồn gốc trước khi trích vào báo cáo** ·
> Kết luận: chi phí suy luận (inference) chiếm phần lớn chi tiêu AI, lãng phí cloud đang tăng lại vì AI, nên cần
> cấp phát có kiểm soát chi phí ngay từ đầu · Liên quan: `docs/de_cuong_tot_nghiep_ver3.md` mục 3, ADR-0006, P6–P7 ·
> Mục lục: 1 Lập luận · 2 Nguồn · 3 Cách viết an toàn · 4 Nối với dự án

## 1. Lập luận (một câu)

AI tốn hạ tầng theo từng lượt dùng → không kiểm soát thì dùng càng nhiều càng lỗ → cần nền tảng cấp phát
có cổng chặn, thu hồi tài nguyên nhàn rỗi và đo chi phí theo tenant. Zero D-Rift chứng minh **cơ chế** đó
ở quy mô PoC; không hứa con số tiết kiệm ở quy mô công ty.

## 2. Nguồn (độ tin cậy ghi rõ)

| Chủ đề | Nội dung | Nguồn | Độ tin cậy |
|---|---|---|---|
| Character.AI | 08/2024: Google cấp phép mô hình, thuê lại 2 nhà sáng lập; công ty ngừng tự huấn luyện mô hình lớn vì "insanely expensive to train frontier models", chuyển sang dùng mô hình mở. **Không phá sản.** | [Bloomberg](https://www.bloomberg.com/news/articles/2024-08-02/character-ai-co-founders-hired-by-google-in-licensing-deal), [Axios](https://www.axios.com/2024/08/05/google-characterai-venture-capital), [The Batch](https://www.deeplearning.ai/the-batch/google-acquires-character-ai-talent-and-tech-in-strategic-move) | Cao (báo lớn) |
| OpenAI Sora | Báo chí đưa tin Sora bị dừng năm 2026; ước tính chi phí suy luận ~15 triệu USD/ngày lúc cao điểm (Forbes, Cantor Fitzgerald), ~1,30 USD GPU cho mỗi video 10 giây; trưởng nhóm Sora nói 10/2025 "the economics are currently completely unsustainable". Ngày dừng và phạm vi dừng (app/API) các nguồn mâu thuẫn. OpenAI không phá sản. | [Digital Applied](https://www.digitalapplied.com/blog/openai-sora-shutdown-ai-product-market-fit-lessons), [Monday Momentum](https://www.mondaymomentum.io/p/the-most-expensive-failure-in-ai-history), [AI Tool Briefing](https://aitoolbriefing.com/blog/openai-sora-shutdown-robotics-pivot-2026/) | Thấp–vừa: blog thứ cấp; số là **ước tính của analyst**, không phải sổ sách OpenAI. Cần tìm bài Forbes/Reuters gốc |
| FinOps for AI | FinOps Foundation coi AI là một nhóm công nghệ riêng trong FinOps Framework; tối ưu suy luận GenAI có thể chiếm 80–90% tổng chi AI; GPU cấp thừa và để rảnh là vấn đề chi phí riêng | [FinOps for AI](https://www.finops.org/wg/finops-for-ai/), [Optimizing GenAI usage](https://www.finops.org/wg/optimizing-genai-usage/) | Vừa: trang gốc chỉ đọc được một phần |
| Lãng phí cloud | Flexera State of the Cloud 2026 (753 người): lãng phí IaaS/PaaS ước tính **29%**, tăng lần đầu sau 5 năm (2025: 27%), một phần do workload AI | [Flexera press release](https://www.flexera.com/about-us/press-center/flexera-finds-cloud-value-is-rising-while-ai-waste-grows), [Flexera blog 2026](https://www.flexera.com/blog/finops/flexera-2026-state-of-the-cloud-report-the-convergence-of-cloud-and-value/) | Vừa–cao: khảo sát, là ước tính |
| Biên lợi nhuận AI | Biên lợi nhuận gộp sản phẩm AI ~45% (2025) so với 60–80% của phần mềm truyền thống (ICONIQ, a16z qua tổng hợp); nhóm tăng trưởng nhanh nhất ~25% (Bessemer) | [1752vc](https://www.1752.vc/learn/ai-gross-margins-and-inference-costs), [SoftwareSeni](https://www.softwareseni.com/why-ai-gross-margins-are-so-much-lower-than-saas-and-what-that-means-for-your-business/) | Thấp–vừa: blog nhắc lại báo cáo; cần đọc ICONIQ/Bessemer gốc |
| ChatGPT Atlas | Chưa tìm, chưa xác minh | — | **Không dùng** |

## 3. Cách viết an toàn trong báo cáo

- Viết: "chi phí suy luận là gánh nặng lớn; nhiều công ty thu hẹp hoặc dừng sản phẩm vì kinh tế đơn vị
  không bền vững [nguồn]". Không viết "X phá sản vì GPU".
- Ghi rõ số là **ước tính** và của ai (analyst, khảo sát). Không trích blog thứ cấp khi đã có nguồn gốc.
- Không dùng ví dụ nào chưa mở được nguồn gốc.

## 4. Nối với dự án

| Cơ chế Zero D-Rift | Giải quyết | Phase |
|---|---|---|
| Cổng window, `platform-config` (externalRef) | Không tạo tài nguyên khi chưa được phép | P2, P4 |
| TTL, thu hồi tài nguyên nhàn rỗi, tag `RunId`/`ExpiresAt` | Không trả tiền cho thứ không dùng, truy được tiền đi đâu | P4–P6 |
| Karpenter + Spot, KEDA scale theo hàng đợi | Chỉ bật máy khi có việc, dùng máy rẻ | P6 |
| OpenCost theo tenant | Đo chi phí từng tenant, tính kinh tế đơn vị | P7 |
| Teardown có bằng chứng | Không còn gì tính tiền sau campaign | P10 |
