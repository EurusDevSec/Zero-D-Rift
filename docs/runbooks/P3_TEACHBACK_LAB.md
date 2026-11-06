# P3 Teach-back — Lab tự tay trên kind (DRF-38)

Mục tiêu: bạn **tự chạy** luồng Git → Argo CD → kro → Crossplane trên máy mình, tự phá vài chỗ, rồi trả lời 6 câu SPEC-P3 §7 bằng lời của bạn, dựa trên những gì **đã thấy**.
Không đụng AWS, không tốn tiền. Phần AWS (bucket thật, IAM thật) đã có ở `docs/evidence/p3/DRF37_L3_WINDOW_20261105.md`; lab này để bạn thấy phần cluster bằng tay mình.

- Thời gian: khoảng 60–75 phút.
- Cần: Docker Desktop đang chạy, khoảng 4 GiB RAM trống, kind/kubectl/helm như lab DRF-39.
- Kết quả: gửi câu trả lời 6 câu trong chat. Claude ghi nguyên văn vào `docs/evidence/p3/DRF38_P3_ACCEPTANCE_AUDIT_20261106.md` mục 6. Mức học chỉ được cập nhật từ phần bạn làm và nói được.

Mẹo: sau mỗi phần, ghi 1–2 dòng "mình thấy gì" vào một file nháp. Lúc trả lời chỉ cần đọc lại file đó.

## 0. Cluster và Argo CD

Làm **§0, §1, §2** của `docs/runbooks/P3_L2_KIND_LAB.md` (shell, cluster `zdr-p3-lab`, Argo CD v3.5.7 có kiểm sha256). **Dừng sau §2**: lần này Crossplane, provider và kro do Argo cài từ Git, không cài bằng tay.

Thêm một hàm tiện:

```bash
apps() { kubectl -n argocd get app -o custom-columns=APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision; }
```

## 1. Câu 1 — Từ Git tới bucket: ai làm gì?

Bật root app (y hệt window trên EKS):

```bash
kubectl apply -f gitops/bootstrap/root-app.yaml
kubectl -n argocd get app -w      # Ctrl+C khi 7 app con Synced/Healthy (3–5 phút; Git Bash không có lệnh watch)
apps
```

`gitops/requests/` trên `main` hiện trống (PR #25 đã xóa instance). Cho app requests đọc một commit **cũ** còn instance hợp lệ (`cff3ac9`). Root có selfHeal sẽ ghi đè thay đổi của bạn, nên dừng root trước:

```bash
kubectl -n argocd patch app zdr-root --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
kubectl -n argocd patch app zdr-requests --type merge -p '{"spec":{"source":{"targetRevision":"cff3ac9"}}}'
sleep 20; apps
```

Lần theo từng tầng và ghi lại bằng chứng:

```bash
# Git → Argo: app requests đang ở commit nào?
kubectl -n argocd get app zdr-requests -o jsonpath='{.status.sync.revision}{"\n"}'
# Argo → kro: instance do Argo tạo (có nhãn/annotation tracking của Argo)
kubectl -n zdr-requests get storageappspike spike -o jsonpath='{.metadata.annotations}{"\n"}'
# kro → Crossplane: Bucket MR do kro tạo (nhãn kro.run/... cho biết instance nào)
kubectl -n zdr-requests get bucket.s3.aws.m.upbound.io -o json | jq '.items[] | {name: .metadata.name, kro: (.metadata.labels | with_entries(select(.key | startswith("kro.run"))))}'
# Crossplane → AWS: provider cố gọi AWS (trên kind không có credential)
kubectl -n zdr-requests get bucket.s3.aws.m.upbound.io -o jsonpath='{range .items[*].status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}' | cut -c1-200
```

**Phải thấy:** revision là `cff3ac9…`. Instance có annotation tracking của Argo. Bucket mang nhãn `kro.run/…` trỏ về instance `spike`. Bucket báo `Synced=False` vì thiếu credential (trên EKS, chỗ này là IRSA; xem DRF37 lúc 16:20).

## 2. Câu 2 — Argo `Synced/Healthy` mà instance không Ready: xem gì, theo thứ tự nào?

Bạn đang ở đúng tình huống đó. Xem lần lượt:

```bash
apps | grep requests                                         # 1. Argo: Synced/Healthy
kubectl -n zdr-requests get storageappspike spike             # 2. kro: STATE, READY
kubectl -n zdr-requests get storageappspike spike -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
kubectl -n zdr-requests get bucket.s3.aws.m.upbound.io        # 3. Crossplane MR: SYNCED/READY
kubectl -n zdr-requests describe bucket.s3.aws.m.upbound.io | tail -15     # events
kubectl -n crossplane-system logs $(kubectl -n crossplane-system get pods -o name | grep provider-aws-s3) --tail=20   # 4. provider log
kubectl -n zdr-requests get deploy                            # 5. Deployment có chưa? Vì sao?
```

**Phải thấy:** Argo xanh; instance `IN_PROGRESS`, chờ node `bucket`; MR `SYNCED=False`; **không có Deployment** (kro chờ bucket Ready mới tạo app).

## 3. Câu 3 — Xóa instance thì bucket, MR, Crossplane ra sao?

**3a. Xóa bằng tay khi Git vẫn còn file:**

```bash
kubectl -n zdr-requests delete storageappspike spike
sleep 15; kubectl -n zdr-requests get storageappspike,bucket.s3.aws.m.upbound.io
```

Quan sát: điều gì xảy ra sau khoảng 15 giây? Ai làm việc đó? (gợi ý: selfHeal của app requests)

**3b. Xóa qua Git** (cách đúng): cho app requests đọc `main`, nơi file đã bị xóa:

```bash
kubectl -n argocd patch app zdr-requests --type merge -p '{"spec":{"source":{"targetRevision":"main"}}}'
for i in 1 2 3 4 5 6; do sleep 5; kubectl -n zdr-requests get storageappspike,bucket.s3.aws.m.upbound.io,deploy --no-headers 2>/dev/null | wc -l; done
kubectl get providers.pkg.crossplane.io; kubectl -n crossplane-system get pods
```

**Phải thấy:** số dòng về `0` (instance, MR mất), còn provider và pod Crossplane **vẫn chạy**.

Đọc chính sách xóa và so với kết quả trên EKS:

```bash
sed -n 1,8p gitops/platform/rgd/storage-app-spike.yaml      # ghi chú về managementPolicies mặc định "*"
grep -n "16:24" docs/evidence/p3/DRF37_L3_WINDOW_20261105.md
```

## 4. Câu 4 — Pod provider lấy credential AWS thế nào, cái gì chặn nó đụng bucket khác?

```bash
kubectl get deploymentruntimeconfig provider-aws-s3 -o yaml | sed -n '/spec:/,$p'
# Gắn ARN GIẢ (account 000000000000) như window đã làm với ARN thật:
kubectl patch deploymentruntimeconfig provider-aws-s3 --type merge \
  -p '{"spec":{"serviceAccountTemplate":{"metadata":{"annotations":{"eks.amazonaws.com/role-arn":"arn:aws:iam::000000000000:role/zero-drift-p3-crossplane-s3"}}}}}'
sleep 10; kubectl -n crossplane-system get sa provider-aws-s3 -o jsonpath='{.metadata.annotations}{"\n"}'
kubectl -n crossplane-system delete $(kubectl -n crossplane-system get pods -o name | grep provider-aws-s3)
sleep 30; kubectl -n crossplane-system get pods -o json | jq '[.items[] | select(.metadata.name | startswith("provider-aws-s3")) | .spec.containers[0].env[]?.name] | index("AWS_ROLE_ARN") != null'
```

**Phải thấy:** SA có annotation. Nhưng jq in `false` trên kind, trong khi trên EKS là `true` (DRF37 16:20:25). Tự tìm lý do: ai chèn biến `AWS_ROLE_ARN` và token vào pod? (gợi ý: một webhook chỉ EKS có)

Phần "chặn bucket khác" nằm trong Terraform. Đọc rồi phá thử (không cần AWS):

```bash
sed -n '/trust_policy = {/,/^  }/p;/permissions_policy = {/,/^  }/p' infra/terraform/modules/p3-provider-irsa/main.tf
cd infra/terraform
sed -i 's#Resource = \["arn:aws:s3:::${var.bucket_prefix}\*"\]#Resource = ["*"]#' modules/p3-provider-irsa/main.tf
terraform test 2>&1 | tail -3        # phải FAIL
git checkout modules/p3-provider-irsa/main.tf && terraform test 2>&1 | tail -1 && cd ../..
```

Đối chiếu với bằng chứng thật: dòng `AccessDenied` ở DRF37 lúc 16:23.

## 5. Câu 5 — Vì sao chỉ được gỡ Crossplane khi MR đã hết?

Tạo lại một MR, rồi **cố tình** xóa provider trước:

```bash
kubectl -n argocd patch app zdr-requests --type merge -p '{"spec":{"source":{"targetRevision":"cff3ac9"}}}'
sleep 30; kubectl -n zdr-requests get bucket.s3.aws.m.upbound.io
kubectl -n argocd patch app zdr-requests --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
kubectl -n argocd patch app zdr-providers --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
kubectl -n argocd patch app zdr-providers --type merge -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}'
kubectl -n argocd delete app zdr-providers --timeout=120s
```

Sau đó thử xóa instance:

```bash
kubectl -n zdr-requests delete storageappspike spike --timeout=60s
kubectl -n zdr-requests get bucket.s3.aws.m.upbound.io -o jsonpath='{range .items[*]}{.metadata.name} deleting={.metadata.deletionTimestamp} finalizers={.metadata.finalizers}{"\n"}{end}'
kubectl get crd buckets.s3.aws.m.upbound.io -o jsonpath='{.metadata.deletionTimestamp}{"\n"}' 2>&1
```

Ghi lại đúng những gì bạn thấy: MR còn không, có `deletionTimestamp` không, finalizer nào giữ nó, CRD ra sao. Trên EKS, nếu bucket thật còn mà controller đã mất, ai sẽ xóa bucket AWS?

Gỡ kẹt (chỉ trên lab):

```bash
for b in $(kubectl -n zdr-requests get bucket.s3.aws.m.upbound.io -o name 2>/dev/null); do
  kubectl -n zdr-requests patch $b --type merge -p '{"metadata":{"finalizers":[]}}'
done
kubectl -n zdr-requests get storageappspike,bucket.s3.aws.m.upbound.io 2>&1
```

## 6. Câu 6 — Vì sao Terraform giữ role, còn bucket thì không?

```bash
grep -n "p3_provider_irsa" infra/terraform/main.tf
grep -rn "kind: Bucket" gitops/platform/rgd/
grep -n "16:28\|16:43" docs/evidence/p3/DRF37_L3_WINDOW_20261105.md
```

Tự trả lời 3 ý:
- Role phải có **trước** hay **sau** cluster/controller? Sống bao lâu?
- Bucket được tạo khi nào, do ai yêu cầu (người dùng qua Git hay người vận hành)?
- Ở bước teardown (A3 của runbook P3): vì sao lúc gỡ admin vẫn phải giữ `-var enable_p3_provider_role=true`?

## 7. Dọn

```bash
kind delete cluster --name zdr-p3-lab
kind get clusters          # không còn zdr-p3-lab
git status --short         # sạch (bước 4 đã trả file Terraform)
```

## Gửi câu trả lời

Trả lời trong chat, mỗi câu 2–5 dòng, bằng lời của bạn. Nhắc tới bước bạn đã chạy và điều bạn thấy. Ví dụ: "ở bước 3a thì instance quay lại sau khoảng 15 giây vì…". Câu nào chưa chắc thì cứ nói chưa chắc; lỗ hổng sẽ được ghi lại để học tiếp, không bị tính là trượt.

1. Đi từ một instance được merge trong Git tới bucket AWS: ở mỗi bước, thành phần nào làm việc?
2. Argo báo `Synced/Healthy` mà instance không Ready: bạn xem những đâu, theo thứ tự nào?
3. Xóa instance thì bucket AWS ra sao? MR? Bản thân Crossplane?
4. Pod provider lấy credential AWS bằng cách nào, và cái gì ngăn nó đụng bucket khác?
5. Vì sao chỉ được gỡ Crossplane sau khi các managed resource đã hết?
6. Vì sao Terraform giữ role của provider mà không giữ bucket?

## Giới hạn

- kind không có IRSA, không có AWS: phần credential thật, `AccessDenied` thật và bucket bị xóa thật lấy từ evidence DRF37.
- Kết quả ở phần 5 chưa được Claude chạy trước. Đó là chỗ để bạn tự quan sát; nếu khác với dự kiến thì ghi lại đúng như thấy.
