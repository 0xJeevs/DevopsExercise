# Exercise 2: IAM / IRSA Failure Analysis

This document details the incident where an application deployed on EKS failed to read from DynamoDB, showing that it assumed the worker node group IAM role instead of the designated IRSA role.

## Incident Diagnosis

### 1. Why is the Node Role being used?
The AWS SDK (e.g., `botocore` / `boto3` in Python) resolves credentials using the **AWS Default Credentials Provider Chain** in the following order:
1. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
2. Web Identity Token credentials (injected by the EKS Pod Identity Webhook for IRSA).
3. ECS container credentials.
4. **EC2 Instance Metadata Service (IMDS)** (the worker node's IAM role).

Since the SDK failed to retrieve credentials via **Web Identity Token (IRSA)**, it fell back down the chain to IMDS and assumed the worker node's role: `arn:aws:sts::123456789012:assumed-role/eks-nodegroup-role`. Since this worker node role is not authorized to access DynamoDB, it resulted in an `AccessDeniedException`.

---

### 2. Why is IRSA not working?
There are three main root causes for IRSA failing to inject credentials into a Pod:

#### Cause A: Missing or Incorrect `serviceAccountName` in Pod Spec
The pod might not be configured to use the ServiceAccount with the IAM mapping, falling back to the `default` ServiceAccount.
* **Verification**: Run `kubectl get pod <pod-name> -o yaml` and check `spec.serviceAccountName`.

#### Cause B: Missing or Incorrect annotation on the ServiceAccount
The ServiceAccount exists but lacks the annotation that instructs the EKS Mutating Webhook to inject the IAM role credentials.
* **Verification**: Run `kubectl get sa <service-account-name> -o yaml` and look for:
  ```yaml
  metadata:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-dynamodb-role
  ```

#### Cause C: Misconfigured IAM Trust Policy (Trust Relationship)
The IAM role trust policy does not trust the EKS Cluster's OIDC provider or does not match the exact ServiceAccount namespace and name.
* **Verification**: Look at the role's Trust Relationship in IAM:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLETOCKEN"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            // Error here: mismatched namespace, SA name, or incorrect OIDC URL
            "oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLETOCKEN:sub": "system:serviceaccount:default:payment-service-sa",
            "oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLETOCKEN:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  }
  ```

---

## 3. How to Fix (Remediation Steps)

Follow these steps to configure IRSA correctly:

### Step 1: Correct the ServiceAccount Annotation
Ensure the ServiceAccount is created with the exact IAM role ARN:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: payment-service-sa
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/payment-service-dynamodb-role
```

### Step 2: Reference the ServiceAccount in the Deployment
Explicitly declare the `serviceAccountName` in the pod spec of the Deployment:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: production
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: payment-service
    spec:
      serviceAccountName: payment-service-sa  # Crucial link
      containers:
        - name: application
          image: 123456789012.dkr.ecr.ap-south-1.amazonaws.com/payment-service:v1.0.0
```

### Step 3: Update the IAM Role Trust Policy
Verify that the Trust Policy allows the specific OIDC provider and targets the exact namespace and ServiceAccount name:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLETOCKEN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLETOCKEN:sub": "system:serviceaccount:production:payment-service-sa",
          "oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLETOCKEN:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### Step 4: Redploy the Pods
Delete the running pods to force the mutating webhook to re-evaluate and inject the required IRSA environment variables:
```bash
kubectl rollout restart deployment payment-service -n production
```

### Verification
Once restarted, describe the pod and verify that:
1. `AWS_ROLE_ARN` environment variable is set to `arn:aws:iam::123456789012:role/payment-service-dynamodb-role`.
2. `AWS_WEB_IDENTITY_TOKEN_FILE` is set to `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`.
3. A volume mount exists for the web identity token.
