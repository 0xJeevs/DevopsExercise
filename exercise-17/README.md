# Exercise 17: Implement IRSA for Application Access

This project implements **IAM Roles for Service Accounts (IRSA)**, enabling application pods in EKS to securely access AWS DynamoDB without using static AWS access keys.

## Directory Structure

```text
exercise-17/
├── iam-policy.json       # IAM Policy for DynamoDB access
├── trust-policy.json     # IAM Role Trust Relationship with EKS OIDC
├── service-account.yaml  # Kubernetes ServiceAccount with annotations
└── README.md             # Implementation and validation guide
```

---

## Technical Overview

IRSA works by using EKS's OpenID Connect (OIDC) identity provider. The flow is:
1. The **ServiceAccount** is annotated with the IAM Role ARN.
2. The **EKS Pod Identity Webhook** monitors pod creations. If a pod uses an annotated ServiceAccount, it modifies the Pod spec by mounting a web identity token volume and injecting the `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` environment variables.
3. The **AWS SDK** (e.g. boto3, AWS SDK for Java/Go) reads these variables, calls the AWS STS service `AssumeRoleWithWebIdentity` to exchange the Kubernetes token for temporary security credentials, and uses them to access DynamoDB.

---

## Step-by-Step Implementation

### Step 1: Extract OIDC Provider URL
Retrieve your EKS cluster's OIDC issuer URL:
```bash
aws eks describe-cluster --name production-eks-cluster --query "cluster.identity.oidc.issuer" --output text
```
*Output will look like: `https://oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLETOCKEN`*

### Step 2: Create IAM OIDC Provider (If not already done)
```bash
eksctl utils associate-iam-oidc-provider --cluster production-eks-cluster --approve
```

### Step 3: Create the IAM Policy
Create the IAM policy to allow CRUD operations on DynamoDB:
```bash
aws iam create-policy \
  --policy-name payment-service-dynamodb-policy \
  --policy-document file://iam-policy.json
```

### Step 4: Create the IAM Role with the Trust Policy
Update `trust-policy.json` with your cluster's OIDC ID and account number. Then create the role:
```bash
aws iam create-role \
  --role-name payment-service-dynamodb-role \
  --assume-role-policy-document file://trust-policy.json

# Attach the policy to the role
aws iam attach-role-policy \
  --role-name payment-service-dynamodb-role \
  --policy-arn arn:aws:iam::123456789012:policy/payment-service-dynamodb-policy
```

### Step 5: Deploy the ServiceAccount to EKS
Apply the ServiceAccount manifest in the target namespace:
```bash
kubectl apply -f service-account.yaml -n production
```

---

## Verification

Deploy a pod using the ServiceAccount:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-irsa-pod
  namespace: production
spec:
  serviceAccountName: payment-service-sa
  containers:
    - name: app
      image: amazon/aws-cli:latest
      command: ["sleep", "3600"]
```
Apply the test pod:
```bash
kubectl apply -f test-pod.yaml
```

Verify that the credentials are automatically injected into the pod environment:
```bash
# 1. Verify Role ARN environment variable
kubectl exec -it test-irsa-pod -n production -- env | grep AWS_ROLE_ARN
# Expected output: AWS_ROLE_ARN=arn:aws:iam::123456789012:role/payment-service-dynamodb-role

# 2. Verify token mount is present
kubectl exec -it test-irsa-pod -n production -- ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/token
# Expected output: /var/run/secrets/eks.amazonaws.com/serviceaccount/token exists

# 3. Test DynamoDB operations using AWS CLI (assumes role inside container)
kubectl exec -it test-irsa-pod -n production -- aws dynamodb get-item \
  --table-name customer-data \
  --key '{"customer_id": {"S": "12345"}}' \
  --region ap-south-1
```
If the command executes without access denied errors, IRSA is functioning correctly.
