# Zero D-Rift — Workflow cần nhớ

> **Nếu không nhớ gì, chỉ cần mở project và nhập `continue`.**

## 5 bước cho mỗi buổi làm việc

```text
1. CONTINUE  → Agent báo đang ở đâu và việc tiếp theo
2. LEARN     → Học đúng phần cần cho task nếu công nghệ còn mới
3. BUILD     → Làm một task nhỏ theo Pair mode
4. VERIFY    → Chạy test và lưu bằng chứng
5. SAVE      → Ghi checkpoint để chat sau tiếp tục
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

## Chỉ cần nhớ 4 file

| Muốn biết | Xem file |
|---|---|
| Toàn dự án đang ở phase nào | `.agent/docs/ROADMAP.md` |
| Phase hiện tại phải làm gì | Active `.agent/specs/SPEC-*.md` |
| Hôm nay đang dở việc gì | `.agent/workflows/active_context.md` |
| Tôi đã hiểu công nghệ đến đâu | `.agent/learning/LEARNING_LOG.md` |

## Khi nào một task được hoàn thành?

```text
Chạy được + Có evidence + Bạn giải thích được
```

Thiếu một trong ba điều trên thì chưa `DONE`.

## 5 điều không làm

1. Không học toàn bộ stack cùng lúc.
2. Không làm nhiều task trong một session.
3. Không để agent xây full feature khi bạn chưa hiểu.
4. Không tạo AWS resource nếu chưa duyệt chi phí và teardown.
5. Không tự động `git add .`, commit hoặc push.

## Prompt dùng hằng ngày

Sao chép nguyên đoạn này khi bắt đầu:

```text
continue. Hãy cho tôi biết phase, task tiếp theo và kiến thức cần học.
Chỉ chọn một task phù hợp với buổi làm hôm nay.
Làm theo Coach/Pair mode và chưa chuyển task nếu chưa verify.
```

Khi kết thúc:

```text
/save. Ghi việc đã làm, evidence, phần tôi đã hiểu/chưa hiểu,
blocker và một hành động nhỏ tiếp theo. Không commit hoặc push.
```

