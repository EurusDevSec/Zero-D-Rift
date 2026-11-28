# Baseline batch thủ công (EXPERIMENT_PLAN §5.3, SPEC-P7 T4, D7, D9)

> Trạng thái: **PLAN**. Viết 28/11, chưa chạy lần nào. Lần chạy đầu là dry run trong window 29/11 (`official=false`).
> Người chạy: **bạn** (owner). Claude chỉ ghi phiếu đếm thao tác ([BASELINE_INTERACTION_SHEET.md](BASELINE_INTERACTION_SHEET.md)).

So sánh dễ nhớ: nền tảng giống **taxi gọi qua app**: có message thì xe tới, chạy xong 60 giây là xe đi. Baseline là **tự
thuê xe theo giờ**: bạn gọi xe (tạo node), lái (chạy Job), xong vẫn giữ xe 30 phút như người vận hành thật hay làm
(idle window 1,800 s), rồi mới trả. Hai bên chở **cùng một hàng**: cùng image, cùng 300 step, cùng `m5.large`, cùng
kiểm tra marker/checkpoint như P6. Profile khoá: [`batch-cpu-small-v1`](../../experiments/profiles/batch-cpu-small-v1.json).

## Luật chơi

- **Mốc bắt đầu:** lúc bạn gõ lệnh đầu tiên của bước 1. **Mốc kết thúc:** inventory sạch ở bước 7.
- **Đếm thao tác** (§5.1): mỗi lệnh bạn gõ là 1 interaction. Chờ thụ động không tính. Sửa lỗi, chạy lại hay retry đều
  được tính và ghi riêng.
- **Stop rule** (§5.4):
  - node chưa Ready sau 3,600 s → run failed;
  - Job quá 2,700 s → run failed;
  - teardown quá 1,800 s → dừng, báo, dọn khẩn.
  - Vượt stop rule là failed run, không tự loại.
- **Tiền:** chỉ On-Demand, không dùng giá Spot giả định. Chi phí được tính sau bằng `collect_timeline.sh --roles baseline` +
  `cost_calc.py run`.
- **Không in** ID instance, IP, endpoint, ARN, URL hàng đợi ra màn hình hay vào file commit. Các biến giữ trong shell.

## 0. Biến của window (một lần)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift && export AWS_PROFILE=zdr-tf AWS_REGION=us-east-1 CL=zero-drift T=tenant-a
```

```bash
RUN=BL-BATCH-$(date -u +%Y%m%dT%H%M%SZ); REQ=manual-1; BKT=zero-drift-batch-$T-$REQ; echo "$RUN $BKT"
```

Hàng đợi lấy từ `platform-config` (giữ trong biến, không in):

```bash
QURL=$(kubectl -n zdr-platform get cm platform-config -o jsonpath='{.data.queueUrl}'); [[ -n "$QURL" ]] && echo "queue OK"
```

## 1. Preflight (mốc bắt đầu)

```bash
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo "T0=$T0"; aws sts get-caller-identity --query 'Arn' --output text | sed -E 's/[0-9]{12}/<acct>/; s#/[^/]*$#/<session>#'
```

Không có node batch hay baseline nào, và không có request batch nào đang bật (để KEDA không giành message):

```bash
kubectl get nodes -l zero-drift.io/pool=batch --no-headers | wc -l; kubectl get scaledjob -A --no-headers | wc -l
```

```bash
aws sqs get-queue-attributes --queue-url "$QURL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --query Attributes --output text
```

**Phải thấy:** `0`, `0`, `0 0`. Khác thì dừng: dọn trước rồi mới bắt đầu.

## 2. Tạo một node On-Demand bằng CLI (D7)

Tạo cùng AMI release với EC2NodeClass `batch`, cùng instance profile, subnet và security group (theo tag discovery):

```bash
AMI=$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/1.35/amazon-linux-2023/x86_64/standard/amazon-eks-node-al2023-x86_64-standard-1.35-v20261026/image_id --query Parameter.Value --output text); SUB=$(aws ec2 describe-subnets --filters Name=tag:karpenter.sh/discovery,Values=$CL --query 'Subnets[0].SubnetId' --output text); SG=$(aws ec2 describe-security-groups --filters Name=tag:karpenter.sh/discovery,Values=$CL --query 'SecurityGroups[0].GroupId' --output text); [[ -n "$AMI" && -n "$SUB" && -n "$SG" ]] && echo "inputs OK"
```

User data cho nodeadm. Nhãn `zero-drift.io/role=baseline` không NodePool nào có, nên Karpenter không tạo node cho Job này:

```bash
UD=$(mktemp); read -r EP CA CIDR < <(aws eks describe-cluster --name $CL --query 'cluster.[endpoint,certificateAuthority.data,kubernetesNetworkConfig.serviceIpv4Cidr]' --output text); cat > "$UD" <<EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="//"

--//
Content-Type: application/node.eks.aws

apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster: {name: $CL, apiServerEndpoint: $EP, certificateAuthority: $CA, cidr: $CIDR}
  kubelet:
    flags: ["--node-labels=zero-drift.io/pool=batch,zero-drift.io/role=baseline", "--register-with-taints=zero-drift.io/batch=true:NoSchedule"]
--//--
EOF
unset EP CA CIDR; echo "user data OK"
```

```bash
EXP=$(date -u -d '+3 hours' +%Y-%m-%dT%H:%M:%SZ); TAGS="{Key=Project,Value=Zero-D-Rift},{Key=Owner,Value=HoangLV},{Key=Environment,Value=PoC},{Key=RunId,Value=$RUN},{Key=ExpiresAt,Value=$EXP},{Key=zero-drift.io/role,Value=baseline},{Key=Name,Value=zdr-baseline-batch}"; IID=$(aws ec2 run-instances --instance-type m5.large --image-id "$AMI" --subnet-id "$SUB" --security-group-ids "$SG" --iam-instance-profile Name=zero-drift-karpenter-node --metadata-options HttpTokens=required,HttpPutResponseHopLimit=1 --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3","Encrypted":true,"DeleteOnTermination":true}}]' --tag-specifications "ResourceType=instance,Tags=[$TAGS]" "ResourceType=volume,Tags=[$TAGS]" --user-data "file://$UD" --count 1 --query 'Instances[0].InstanceId' --output text); rm -f "$UD"; [[ "$IID" == i-* ]] && echo "instance created $(date -u +%T)Z"
```

**Nếu lỗi** (quota, capacity): ghi lỗi vào phiếu, không thử loại máy khác vì profile khoá `m5.large`. Thử lại tối đa 1 lần,
có tính interaction.

## 3. Node join, nhãn, taint, danh tính

```bash
kubectl wait node -l zero-drift.io/role=baseline --for=condition=Ready --timeout=900s && kubectl get nodes -l zero-drift.io/role=baseline -L zero-drift.io/pool,node.kubernetes.io/instance-type -o custom-columns=READY:.status.conditions[-1].type,TAINT:.spec.taints[*].key,TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type
```

**Phải thấy:** `Ready`, taint `zero-drift.io/batch`, `m5.large`. Danh tính workload: ServiceAccount `batch-train`
(tenant) và `batch-submit` (`zdr-platform`) đã được `window.sh annotate` gắn role, giống nền tảng:

```bash
kubectl -n $T get sa batch-train -o jsonpath='{.metadata.annotations}' | grep -c role-arn; kubectl -n zdr-platform get sa batch-submit -o jsonpath='{.metadata.annotations}' | grep -c role-arn
```

## 4. Bucket, gửi message, chạy Job (không KEDA)

Bucket trong prefix của tenant (nền tảng để Crossplane tạo bucket này):

```bash
aws s3api create-bucket --bucket "$BKT" >/dev/null && aws s3api put-bucket-tagging --bucket "$BKT" --tagging "TagSet=[{Key=Project,Value=Zero-D-Rift},{Key=Owner,Value=HoangLV},{Key=Environment,Value=PoC},{Key=RunId,Value=$RUN},{Key=ExpiresAt,Value=$EXP}]" && echo "bucket OK"
```

Gửi message bằng đúng lệnh `submit` của image. Nền tảng chạy lệnh này trong Job `submit` của kro:

```bash
cat <<EOF | kubectl apply -f - >/dev/null && echo "submit Job created $(date -u +%T)Z"
apiVersion: batch/v1
kind: Job
metadata: {name: $T-$REQ-submit-1, namespace: zdr-platform, labels: {app.kubernetes.io/name: batch-submit, zero-drift.io/role: baseline}}
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 300
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: batch-submit
      securityContext: {runAsNonRoot: true, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: submit
          image: ghcr.io/eurusdevsec/zero-d-rift/batch-training@sha256:d2bb517d884710dd269285773b6fd5de74b631a4faafdb2fd2a3c0020cbb470e
          args: ["submit"]
          env:
            - {name: TENANT, value: "$T"}
            - {name: REQUEST_ID, value: "$REQ"}
            - {name: RUN_ATTEMPT, value: "1"}
            - {name: STEPS, value: "300"}
            - {name: BUCKET, value: "$BKT"}
            - {name: QUEUE_URL, value: "$QURL"}
            - {name: AWS_REGION, value: "$AWS_REGION"}
            - {name: AWS_DEFAULT_REGION, value: "$AWS_REGION"}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 50m, memory: 96Mi}, limits: {memory: 192Mi}}
EOF
```

Job training: cùng spec với Job do KEDA tạo, chỉ khác `nodeSelector` (node baseline) và không có ScaledJob:

```bash
cat <<EOF | kubectl apply -f - >/dev/null && echo "train Job created $(date -u +%T)Z"
apiVersion: batch/v1
kind: Job
metadata: {name: batch-$REQ-1, namespace: $T, labels: {zero-drift.io/role: baseline}}
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 2700
  template:
    metadata:
      labels: {app.kubernetes.io/name: batch-train, rag.zero-drift.io/tenant: $T, batch.zero-drift.io/request: $REQ, batch.zero-drift.io/attempt: "1"}
    spec:
      restartPolicy: Never
      serviceAccountName: batch-train
      automountServiceAccountToken: false
      nodeSelector: {zero-drift.io/role: baseline}
      tolerations: [{key: zero-drift.io/batch, operator: Equal, value: "true", effect: NoSchedule}]
      securityContext: {runAsNonRoot: true, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: train
          image: ghcr.io/eurusdevsec/zero-d-rift/batch-training@sha256:d2bb517d884710dd269285773b6fd5de74b631a4faafdb2fd2a3c0020cbb470e
          args: ["train"]
          env:
            - {name: TENANT, value: "$T"}
            - {name: REQUEST_ID, value: "$REQ"}
            - {name: RUN_ATTEMPT, value: "1"}
            - {name: FAIL_PROFILE, value: "none"}
            - {name: BUCKET, value: "$BKT"}
            - {name: QUEUE_URL, value: "$QURL"}
            - {name: AWS_REGION, value: "$AWS_REGION"}
            - {name: AWS_DEFAULT_REGION, value: "$AWS_REGION"}
            - {name: HEARTBEAT_SECONDS, value: "40"}
            - {name: VISIBILITY_TIMEOUT, value: "120"}
            - {name: POD_NAME, valueFrom: {fieldRef: {fieldPath: metadata.name}}}
            - {name: NODE_NAME, valueFrom: {fieldRef: {fieldPath: spec.nodeName}}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 500m, memory: 384Mi}, limits: {memory: 512Mi}}
EOF
```

Marker "process thực sự bắt đầu" là object `TRAINING_STARTED` trong S3, giống P6:

```bash
kubectl -n $T wait job/batch-$REQ-1 --for=condition=complete --timeout=2700s; date -u +%T
```

## 5. Kiểm kết quả (cùng tiêu chí B04 của P6)

```bash
aws s3api list-objects-v2 --bucket "$BKT" --prefix "runs/$REQ/1/" --query 'Contents[].Key' --output text | tr '\t' '\n' | sed "s#runs/$REQ/1/##" | sort | uniq -c | awk '{print $2}' | grep -cE '^(submit-started|TRAINING_STARTED|SUCCEEDED|MESSAGE_DELETED|artifact/model.json)$'
```

```bash
aws s3api list-objects-v2 --bucket "$BKT" --prefix "runs/$REQ/1/ckpt/" --query 'length(Contents)' --output text; aws sqs get-queue-attributes --queue-url "$QURL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --query Attributes --output text
```

**Phải thấy:**
- `5`: đủ năm marker;
- `≥ 1` checkpoint (300 step, cứ 25 step một checkpoint, nên khoảng 12);
- hàng đợi `0 0`.

Thiếu marker nào là run failed: ghi vào phiếu.

## 6. Giữ node 1,800 s (idle window khoá)

```bash
IDLE0=$(date -u +%s); while (( $(date -u +%s) - IDLE0 < 1800 )); do printf '\ridle %4ds / 1800s ' $(( $(date -u +%s) - IDLE0 )); sleep 30; done; echo; date -u +%T
```

Đồng hồ chạy trên màn hình. Không làm gì khác trên node này trong lúc chờ (passive wait, không tính interaction).

## 7. Trả node, kiểm inventory (mốc kết thúc)

```bash
kubectl drain -l zero-drift.io/role=baseline --ignore-daemonsets --delete-emptydir-data --timeout=300s >/dev/null; aws ec2 terminate-instances --instance-ids "$IID" --query 'TerminatingInstances[0].CurrentState.Name' --output text
```

```bash
aws ec2 wait instance-terminated --instance-ids "$IID" && kubectl delete node -l zero-drift.io/role=baseline --ignore-not-found >/dev/null; T1=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo "T1=$T1"
```

Inventory:
- không còn instance, volume hay IP nào của run;
- bucket rỗng rồi xoá (nền tảng xoá bằng `forceDestroy`).

```bash
aws ec2 describe-instances --filters Name=tag:RunId,Values=$RUN Name=instance-state-name,Values=pending,running,stopping,stopped --query 'length(Reservations)' --output text; aws ec2 describe-volumes --filters Name=tag:RunId,Values=$RUN --query 'length(Volumes)' --output text
```

```bash
aws s3 rm "s3://$BKT" --recursive --quiet && aws s3api delete-bucket --bucket "$BKT" && kubectl -n $T delete job batch-$REQ-1 --ignore-not-found && kubectl -n zdr-platform delete job $T-$REQ-submit-1 --ignore-not-found; unset IID
```

**Phải thấy:** `0`, `0`; bucket xoá được. Ghi T1 vào phiếu.

## 8. Ghi lại

- Phiếu đếm: interactions, commands, waits, errors, remedial actions, và `automated_actions_count` của mỗi lệnh chạy
  nhiều thao tác.
- Trong vòng 1 giờ (trước khi EC2 quên instance đã terminate):

```bash
bash experiments/lib/collect_timeline.sh --context "$(kubectl config current-context)" --start "$T0" --end "$T1" --run-id "$RUN" --out "experiments/runs/P7-DRY/$RUN" --arm baseline --pair-id P7-DRY-1 --roles baseline >/dev/null && python -I experiments/lib/cost_calc.py run "experiments/runs/P7-DRY/$RUN/cost/cost_input.json" | grep -E 'billed_seconds|variable_compute_usd'
```

(`--context` nhận giá trị trong shell; lệnh không in giá trị đó ra.)

## Dọn khẩn (stop rule)

```bash
aws ec2 describe-instances --filters Name=tag:zero-drift.io/role,Values=baseline Name=instance-state-name,Values=pending,running --query 'Reservations[].Instances[].InstanceId' --output text | xargs -r aws ec2 terminate-instances --instance-ids >/dev/null; echo "terminate requested"
```

Sau đó chạy bước 7 (inventory) và ghi lý do dừng vào phiếu.
