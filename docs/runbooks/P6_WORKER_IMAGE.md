# P6 — Worker và image BatchTrainingJob (DRF-75, P6-T2.1)

Runbook để tự làm lại. Không có AWS, không có credential thật. Chỉ dùng Docker
local, cộng GitHub Actions ở mục C.
Code: `workloads/batch-training/`. README có bảng S3 key, biến môi trường và exit code.

## Bức tranh: hệ thống giống một bếp nhận order

```text
submit (thu ngân)            SQS (thanh treo order)          train (đầu bếp)
  1. sổ có "submitted"? ──┐
  2. ghi "submit-started"  │   {requestId,tenant,           1. lấy 1 order, ghi RECEIVED-n
     (chỉ lần đầu: 412)    │    runAttempt,steps}           2. order nhà khác? treo lại (vis 0)
  3. treo order ───────────┴──────────────►  ─────────────► 3. món đã xong? xoá order (ALREADY_DONE)
  4. ghi "submitted"                                         4. nấu, cứ 25 bước chụp ảnh nồi (ckpt)
                                                             5. xong: artifact, SUCCEEDED
                       heartbeat 40 s: "tôi vẫn đang nấu" ── 6. xoá order → MESSAGE_DELETED
```

- Mất điện giữa chừng (SIGTERM, mất node): đầu bếp chụp ảnh nồi rồi đi. Order vẫn
  treo đó, 120 s sau hiện lại; đầu bếp mới nấu tiếp từ ảnh, không từ đầu.
- Thu ngân treo order hai lần (crash giữa bước 3 và 4): đầu bếp thứ hai thấy
  `SUCCEEDED`, chỉ xoá order. Món không bị nấu hai lần.

## A. Kiểm local (Git Bash, ~1 phút sau lần pull đầu)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
bash workloads/batch-training/test.sh
bash workloads/batch-training/smoke.sh
```

**Phải thấy:**
- `test.sh`: `65 passed`.
- `smoke.sh`: kết thúc bằng `SMOKE PASS`. Nó dừng với `FAIL: …` (exit khác 0) nếu
  một bước sai.

`smoke.sh` tự dọn container và network. Image `batchtraining:smoke` vẫn còn; xoá bằng
`docker image rm batchtraining:smoke`.

## B. Đọc output của `smoke.sh`, đoán trước khi chạy

| Bước | Dự đoán (ghi trước) | Phải thấy |
|---|---|---|
| user và root filesystem | uid? `touch /probe` được không? | `10001`; `Read-only file system` |
| L2 conditional write | lần ghi thứ hai trả gì? giá trị đầu còn không? | `conditional_second=412:PreconditionFailed`, `first_value_kept=true`, `conditional_write=PASS` |
| submit hai lần | queue có mấy message? | lần 2 in `ALREADY_SUBMITTED`; queue `1 0` |
| train | có những key nào? checkpoint ở bước nào? | 9 key, checkpoint 25 và 50 (bước 60 là artifact) |
| SIGTERM | exit code? message ở đâu? | `143`; queue `0 1` (đang in-flight, chưa xoá) |
| resume | train tiếp từ bước nào? accuracy so với run 1? | `resumed from step N` với N > 0; accuracy giống hệt run 1 (dữ liệu sinh từ seed) |

Bước "release" trong smoke purge queue rồi gửi lại cùng run key, thay cho việc chờ
120 s visibility timeout. Logic resume chỉ phụ thuộc checkpoint trong S3, nên phép
thay này không làm yếu kiểm tra.

## C. Publish lên GHCR (cùng mẫu D8 của P4, SPEC-P6 A12)

Workflow `.github/workflows/batch-training-image.yml`:
- trên PR: chạy `test.sh` và `smoke.sh`, **không push**, không có token ghi;
- trên `main`: chạy lại, rồi push `ghcr.io/eurusdevsec/zero-d-rift/batch-training:sha-<commit>`.

1. Merge PR. Đây là lần publish đầu tiên, nên merge chính là bước owner đồng ý push.
2. Tab Actions → run `batch-training-image` của commit merge → Summary có dòng
   `Image: ghcr.io/…@sha256:…`.
3. Kiểm tra pull không cần đăng nhập (config Docker trống):

   ```bash
   IMG=ghcr.io/eurusdevsec/zero-d-rift/batch-training@sha256:<digest>
   anon="$(mktemp -d)"; echo '{}' > "$anon/config.json"
   DOCKER_CONFIG="$anon" docker pull "$IMG"; rm -rf "$anon"
   bash workloads/batch-training/smoke.sh "$IMG"
   ```

4. Pull báo `denied` hoặc `unauthorized` nghĩa là package private. Vào
   `github.com/EurusDevSec?tab=packages` → `zero-d-rift/batch-training` → Package
   settings → Change visibility → Public. Bước này công khai image, nên owner tự làm.
5. Ghi digest vào `docs/VERSION_MATRIX.md` (dòng "BatchTraining image") bằng một PR
   nhỏ. Manifest của T2.2 dùng `@sha256:<digest>`, không dùng tag.

**Undo:** Package settings → xoá version (hoặc cả package). Image không có secret.
Code: xoá nhánh `hoang/drf-75-p6-t21-worker` nếu chưa merge; sau merge thì revert PR.

## D. L2 trên S3 thật (để vào preflight cửa sổ L3)

§9.3 L2 cần thêm một lần chạy trên S3 thật. Nó ghi vào AWS, nên chạy trong cửa sổ
L3 đã được duyệt, từ một Pod `batch-train` của tenant-a, sau khi bucket đã Ready:

```bash
kubectl -n tenant-a run bt-l2 --rm -i --restart=Never --image "$IMG" \
  --overrides '{"spec":{"serviceAccountName":"batch-train","automountServiceAccountToken":false}}' \
  -- probe s3-conditional --bucket <bucket> --prefix probe --expect-role zero-drift-batch-tenant-a
```

Phải thấy `caller_role_match=true` và `conditional_write=PASS`. Lệnh đầy đủ (kèm
security context để qua `restricted` và Kyverno) sẽ nằm trong `P6_L3_WINDOW.md`.

## Tự thử (không bắt buộc)

- `FAIL_PROFILE=fail-always`: chạy train 3 lần, thấy `RECEIVED-1..3`, không có `SUCCEEDED`.
- Đổi `HEARTBEAT_SECONDS=120` với `VISIBILITY_TIMEOUT=120`: exit 2, heartbeat phải ngắn hơn.
- Chạy `probe s3-get` không có `--expect-role` và không có endpoint: exit 2.

## Giới hạn

- kind và smoke không chứng minh SQS thật, IRSA, DLQ (`maxReceiveCount` là của AWS),
  Kyverno hay NetworkPolicy. Các thứ đó chỉ có ở L3.
- `cleanup` chỉ xoá message của request. Job đã xong là object Kubernetes; operator xoá
  bằng `kubectl` trong runbook cửa sổ (image không cần quyền Kubernetes API).
