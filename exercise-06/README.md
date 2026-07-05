# Exercise 6: EKS Node Scale Failure Analysis

This document details the troubleshooting and root-cause analysis for the EKS scaling failure where the Horizontal Pod Autoscaler (HPA) requested 15 replicas but the cluster remained stuck at 5 replicas with pending pods.

## Incident Investigation & Classification

### 1. HPA Status (Healthy)
The HPA is **not** the issue. The HPA successfully monitored the metrics and calculated that `15` desired replicas are required to handle the traffic. It updated the deployment's desired state, but the scheduling failed.

### 2. Node Status (Resource Exhausted)
The existing nodes are healthy but fully saturated. The message `0/3 nodes available: Insufficient CPU` indicates that the Kubernetes scheduler attempted to place the new 10 pods, but none of the 3 existing worker nodes had enough unreserved CPU capacity to satisfy the pod's CPU requests. This is a normal capacity limit, which should trigger node scaling.

### 3. Cluster Autoscaler Status (Failed - Root Cause)
The Cluster Autoscaler (CA) logs state: `No node group config found`. 

This is the **root cause** of the outage. The Cluster Autoscaler is running inside the cluster, but it cannot find any Auto Scaling Groups (ASGs) to scale up. 

There are three primary reasons for this error:

#### Cause A: Missing Auto Scaling Group (ASG) Tags (Most Common)
The Cluster Autoscaler uses autodiscovery to find which EC2 Auto Scaling Groups belong to the EKS cluster. For autodiscovery to work, the ASG in AWS must be tagged with:
- Key: `k8s.io/cluster-autoscaler/enabled` | Value: `true` (or `yes`)
- Key: `k8s.io/cluster-autoscaler/<my-cluster-name>` | Value: `owned` (or `shared`)

If these tags are missing on the AWS Auto Scaling Group, the Cluster Autoscaler will ignore the ASG and report `No node group config found`.

#### Cause B: Misconfigured Cluster Autoscaler Deployment Arguments
The Cluster Autoscaler deployment spec might have a mismatched cluster name in its startup arguments, preventing it from matching the tags on the ASG.
* **Incorrect**: `--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/wrong-cluster-name`

#### Cause C: Insufficient IAM Permissions for Cluster Autoscaler
The IAM Role associated with the Cluster Autoscaler ServiceAccount (IRSA) lacks the permissions to interact with AWS Auto Scaling APIs. Thus, when it calls `DescribeAutoScalingGroups`, it is denied, leading to discovery failure.

---

## How to Fix (Remediation Steps)

### Step 1: Add Tags to the AWS Auto Scaling Group (ASG)
If using Terraform to manage the EKS Node Group, ensure the tags are applied to the Auto Scaling Group:
```hcl
tag {
  key                 = "k8s.io/cluster-autoscaler/my-eks-cluster"
  value               = "owned"
  propagate_at_launch = true
}

tag {
  key                 = "k8s.io/cluster-autoscaler/enabled"
  value               = "true"
  propagate_at_launch = true
}
```
*Note: If creating EKS managed node groups via AWS EKS APIs, EKS will automatically apply these tags to the managed ASGs. If utilizing self-managed node groups, these must be explicitly tagged.*

### Step 2: Validate the Cluster Autoscaler Deployment Spec
Ensure the command arguments in the Cluster Autoscaler deployment match the cluster name. Run `kubectl edit deployment cluster-autoscaler -n kube-system` and verify the arguments:
```yaml
spec:
  template:
    spec:
      containers:
        - name: cluster-autoscaler
          command:
            - ./cluster-autoscaler
            - --v=4
            - --stderrthreshold=info
            - --cloud-provider=aws
            - --skip-nodes-with-local-storage=false
            - --expander=least-waste
            - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/my-eks-cluster
```

### Step 3: Verify the Cluster Autoscaler IAM Policy
Ensure the IAM role attached to the Cluster Autoscaler ServiceAccount (`cluster-autoscaler` in `kube-system`) has the following permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeImages",
        "ec2:GetInstanceTypesFromInstanceRequirements"
      ],
      "Resource": "*"
    }
  ]
}
```
Once the tags and permissions are corrected, restart the Cluster Autoscaler deployment:
```bash
kubectl rollout restart deployment cluster-autoscaler -n kube-system
```
The autoscaler will discover the ASG, see the pending pods, update the ASG desired capacity from 3 to 6, and EKS will scale up the nodes.
