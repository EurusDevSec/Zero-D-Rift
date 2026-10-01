# Zero D-Rift — Workflow cần nhớ

> **Nếu không nhớ gì, chỉ cần mở project và nhập `continue`.**

## 6 bước cho mỗi buổi làm việc

```text
1. CONTINUE  → Nạp packet nhỏ và kiểm tra trạng thái sống
2. SELECT    → Chọn đúng một outcome/parent task
3. LEARN     → Học đúng phần đang chặn task nếu công nghệ còn mới
4. BUILD     → Làm một task nhỏ theo Coach/Pair mode
5. VERIFY    → Chạy test và lưu evidence ở nơi chuẩn
6. SAVE      → Phân loại, rewrite và thu gọn checkpoint
```

## Lệnh sử dụng

### Bắt đầu

```text
continue
```

### Nếu chưa hiểu công nghệ

```text
/learn <chủ đề> phục vụ task hiện tại, chưa làm full solution
```

### Khi đã hiểu và bắt đầu làm

```text
Làm subtask tiếp theo theo Pair mode. Giải thích trước khi sửa file.
```

### Kiểm tra kết quả

```text
/verify
```

### Kết thúc buổi làm

```text
/save
```

## Chỉ cần nhớ 5 nguồn

| Muốn biết | Xem file |
|---|---|
| Toàn dự án đang ở phase nào | `.agent/docs/ROADMAP.md` |
| Phase hiện tại phải làm gì | Active `.agent/specs/SPEC-*.md` |
| Hôm nay đang dở việc gì | `.agent/workflows/active_context.md` |
| Tôi đang hiểu công nghệ đến đâu | `.agent/learning/CURRENT_STATUS.md` |
| Git/AWS/Kubernetes hiện ra sao | Truy vấn trực tiếp, không tin snapshot trong tài liệu |

## Khi nào một task được hoàn thành?

```text
Chạy được + Có evidence + Bạn giải thích được
```

Thiếu một trong ba điều trên thì chưa `DONE`.

## 5 điều không làm

1. Không học toàn bộ stack cùng lúc.
2. Một chat chỉ theo một outcome mạch lạc, thường là một parent task.
3. Không để agent xây full feature khi bạn chưa hiểu.
4. Không tạo AWS resource nếu chưa duyệt chi phí và teardown.
5. Không tự động `git add .`, commit hoặc push.

## Prompt dùng hằng ngày

Sao chép nguyên đoạn này khi bắt đầu:

```text
continue. Hãy cho tôi biết phase, task tiếp theo và kiến thức cần học.
Chỉ chọn một task phù hợp với buổi làm hôm nay.
Chỉ nạp context cần cho task; làm theo Coach/Pair mode và chưa chuyển task nếu chưa verify.
```

Khi kết thúc:

```text
/save. Ghi việc đã làm, evidence, phần tôi đã hiểu/chưa hiểu,
blocker, authority và một hành động nhỏ tiếp theo. Phân loại thông tin về đúng
nguồn, rewrite active context, chạy context checker. Không commit hoặc push.
```

Nếu vẫn làm cùng outcome nhưng chat đã dài, checkpoint rồi dùng `/compact`. Nếu
đổi outcome/phase gate/phạm vi ghi file, checkpoint rồi mở chat mới. Không cần
chờ một ngưỡng phần trăm context cố định.

