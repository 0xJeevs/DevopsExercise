# Exercise 16: Build a Production EKS Platform

This project defines a production-ready AWS EKS cluster deployment using **Terraform** and **Terragrunt**, automating EKS configuration, networking, namespaces, Cluster Autoscaler, and Metrics Server.

## Directory Structure

```text
exercise-16/
├── main.tf            # Core EKS, VPC, and K8s configuration
├── terragrunt.hcl     # Terragrunt inputs and backend state definition
└── README.md          # Deployment and verification documentation
```

---

## EKS Platform Components

1. **VPC Infrastructure**: Multi-AZ VPC utilizing a NAT Gateway. Subnets are tagged with ELB discovery tags to permit the AWS Load Balancer Controller to dynamically discover public and private endpoints.
2. **EKS Cluster (v1.28)**: Configured with an IAM OIDC Provider enabled to support IAM Roles for Service Accounts (IRSA).
3. **EKS Managed Node Groups**: Scaling group with general-purpose nodes (`t3.medium`) starting at 3 nodes, auto-scaling up to 6.
4. **Dev and Prod Namespaces**: Isolation boundaries for the microservices.
5. **Metrics Server**: Deployed via Helm to scrape resource usage metrics (essential for Horizontal Pod Autoscaling).
6. **Cluster Autoscaler**: Deployed via Helm to auto-discover the EKS node group and interface with the EC2 Auto Scaling Group.

---

## How to Deploy

### Step 1: Initialize Terragrunt
Run the initialization to pull required providers and set up remote state backends:
```bash
terragrunt init
```

### Step 2: Apply the Infrastructure
Plan and apply the resources:
```bash
terragrunt plan
terragrunt apply
```

---

## Validation & Verification

Once deployment completes, download the EKS kubeconfig context:
```bash
aws eks update-kubeconfig --region ap-south-1 --name production-eks-cluster
```

Run the validation commands:

### 1. Verify Nodes are running and healthy
```bash
kubectl get nodes
```
*Expected Output:*
```text
NAME                                           STATUS   ROLES    AGE   VERSION
ip-10-0-1-105.ap-south-1.compute.internal      Ready    <none>   5m    v1.28.3-eks-e71965b
ip-10-0-2-120.ap-south-1.compute.internal      Ready    <none>   5m    v1.28.3-eks-e71965b
ip-10-0-3-135.ap-south-1.compute.internal      Ready    <none>   5m    v1.28.3-eks-e71965b
```

### 2. Verify Resource Utilization (Metrics Server is active)
```bash
kubectl top nodes
```
*Expected Output:*
```text
NAME                                         CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
ip-10-0-1-105.ap-south-1.compute.internal    112m         5%     1024Mi          28%
ip-10-0-2-120.ap-south-1.compute.internal    95m          4%     980Mi           26%
ip-10-0-3-135.ap-south-1.compute.internal    105m         5%     1010Mi          27%
```

### 3. Verify namespaces are created
```bash
kubectl get ns
```
*Expected Output:*
```text
NAME              STATUS   AGE
default           Active   6m
dev               Active   5m
production        Active   5m
kube-system       Active   6m
kube-public       Active   6m
```
