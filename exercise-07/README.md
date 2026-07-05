# Exercise 7: ALB Ingress Failure Analysis

This document details the troubleshooting and root-cause analysis for an application exposure failure where external requests fail with a `504 Gateway Timeout`, the ingress reports `Target registration failed`, and the AWS Load Balancer Controller logs report `Unable to discover subnets`.

## Incident Investigation

The logs of `aws-load-balancer-controller` reveal:
```text
{"level":"error","ts":"2026-07-05T21:35:00Z","msg":"Unable to discover subnets","error":"couldn't find subnets for load balancer"}
```
Additionally, `kubectl describe ingress payment-ingress -n production` shows:
```text
Events:
  Type     Reason                  Age    From                         Message
  ----     ------                  ----   ----                         -------
  Warning  TargetRegistrationFail  2m     aws-load-balancer-controller  Target registration failed: TargetGroupNotFound or InvalidParameter
```

---

## Root Cause Analysis

The incident is caused by a failure of the **AWS Load Balancer Controller's Subnet Auto-Discovery mechanism**.

### 1. Subnet Tagging Mismatch (Primary Issue)
When an Ingress is created with the `alb` class, the AWS Load Balancer Controller queries the AWS API to locate subnets in the cluster's VPC where it can provision the ALB's network interfaces. It relies on specific tags to determine which subnets are public (internet-facing) and which are private (internal).

If the subnets lack the appropriate tags, the controller fails to resolve the networking layout, cannot complete target registration, and fails to route traffic to the pods, leading to a `504 Gateway Timeout`.

#### Required Tags:
* **For Public (Internet-Facing) Load Balancers**:
  The VPC's public subnets must be tagged with:
  - Key: `kubernetes.io/role/elb` | Value: `1`
* **For Private (Internal) Load Balancers**:
  The VPC's private subnets must be tagged with:
  - Key: `kubernetes.io/role/internal-elb` | Value: `1`
* **Cluster Scope Tag (Highly Recommended)**:
  To prevent cross-talk between multiple clusters in the same VPC:
  - Key: `kubernetes.io/cluster/<cluster-name>` | Value: `shared` or `owned`

### 2. direct Pod Routing (Target Type: `ip`) Security Group Block
The ingress specifies `alb.ingress.kubernetes.io/target-type: ip`.
In this mode, the ALB routes traffic directly to the Pod IPs rather than routing through the NodePort of the worker nodes.
If the subnets are successfully discovered but target registration still fails with health check timeouts, it is because:
- The **Security Group** associated with the Pods (or EKS Node Security Group) does not allow inbound traffic from the security group automatically created/used by the ALB on the application's container port.
- The ALB cannot verify the pod's health check endpoint (e.g. `/healthz` returning HTTP 200), marks the target as unhealthy, and fails the gateway connection (HTTP 504).

---

## How to Fix (Remediation Steps)

### Step 1: Add Tags to EKS Subnets in AWS
Identify the public and private subnets inside your AWS VPC. Add the following tags:

* **Public Subnets**:
  ```text
  kubernetes.io/role/elb = 1
  kubernetes.io/cluster/my-eks-cluster = shared
  ```
* **Private Subnets**:
  ```text
  kubernetes.io/role/internal-elb = 1
  kubernetes.io/cluster/my-eks-cluster = shared
  ```

If you are using Terraform to deploy the VPC and subnets, add them to your `aws_subnet` configuration:
```hcl
resource "aws_subnet" "public" {
  # ... other configs ...
  tags = {
    "kubernetes.io/role/elb"                  = "1"
    "kubernetes.io/cluster/my-eks-cluster"    = "shared"
  }
}

resource "aws_subnet" "private" {
  # ... other configs ...
  tags = {
    "kubernetes.io/role/internal-elb"         = "1"
    "kubernetes.io/cluster/my-eks-cluster"    = "shared"
  }
}
```

### Step 2: Set Ingress Target Group Configuration
Review your Ingress annotations to make sure they match the subnet roles. For example, if you want an internet-facing ALB, the ingress scheme must be `internet-facing` (which maps to the public subnets with the `elb` tag):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: payment-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing  # Targets public subnets
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/healthcheck-port: traffic-port
spec:
  rules:
    - host: payment.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: payment-service
                port:
                  number: 8080
```

### Step 3: Validate Security Group Rules
Ensure the Pod's security groups permit TCP traffic on port `8080` (or your container port) from the ALB security group. If you are using the AWS VPC CNI with security groups for pods, define a `SecurityGroupPolicy` or modify the Node Security Group to allow ingress from the load balancer.
