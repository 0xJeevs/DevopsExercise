# Exercise 4: External Secrets Failure Analysis

This document details the troubleshooting steps and root-cause analysis for the `ExternalSecret` sync failure (`READY=False`) which led to a fatal application crash due to a missing `DB_PASSWORD` environment variable.

## Incident Investigation

The output of `kubectl describe externalsecret` shows:
```text
Status:
  Conditions:
    Status:   False
    Type:     Ready
  Events:
    Type:     Warning
    Reason:   SecretSyncedError
    Message:  AccessDeniedException: User is not authorized to perform: secretsmanager:GetSecretValue on resource: arn:aws:secretsmanager:ap-south-1:123456789012:secret:production/payment-service-1a2b3c
```

---

## Issue Classification

By analyzing the error message, we can isolate the failure:

### 1. AWS Issue (Root Cause)
The error `AccessDeniedException: User is not authorized to perform: secretsmanager:GetSecretValue` on the specific resource indicates that the AWS IAM role was **successfully assumed** (which rules out OIDC trust provider and ServiceAccount mapping issues in Kubernetes), but the assumed IAM role lacks the permissions required to retrieve the secret value from AWS Secrets Manager.

Common AWS-side reasons:
- **Insufficient IAM Policy**: The IAM policy attached to the role does not grant `secretsmanager:GetSecretValue`.
- **Resource ARN Mismatch**: The IAM policy contains a restricted resource path (e.g. `arn:aws:secretsmanager:ap-south-1:123456789012:secret:dev/*`) but the secret being accessed is under `production/*`.
- **KMS Key Permission Missing**: If the secret is encrypted with a custom Customer Managed Key (CMK) in AWS KMS, the IAM role must have permission to decrypt it:
  ```json
  "Action": [
    "kms:Decrypt"
  ]
  ```
  Without this, Secrets Manager will return an access denied error when attempting to decrypt and retrieve the secret.

### 2. Kubernetes Issue
While the AWS IAM error is the primary culprit, Kubernetes-side misconfigurations can also block this flow:
- **ServiceAccount Annotation**: The `SecretStore` is referencing a ServiceAccount that has the wrong role ARN annotated.
- **Namespace Issues**: A namespaced `SecretStore` is trying to access a secret without proper RBAC permissions, or a namespace restriction prevents the controller from creating the target Kubernetes Secret.

### 3. Secret Issue
- **Secret Doesn't Exist**: The secret path `production/payment-service` does not exist in the configured region (`ap-south-1`).
- **Property Mismatch**: The secret exists, but the key `db_password` does not exist within the JSON payload of the secret.

---

## Troubleshooting Playbook

### Step 1: Inspect the ExternalSecret and SecretStore
Check which SecretStore is being used and which ServiceAccount it references:
```bash
kubectl describe externalsecret payment-db-secret -n production
kubectl describe secretstore aws-secretsmanager -n production
```

Find the ServiceAccount name from the `SecretStore` spec and check its annotated role:
```bash
kubectl get sa <service-account-name> -n production -o yaml
```

### Step 2: Validate the IAM Role Policy in AWS
Identify the IAM Role ARN from the ServiceAccount annotation (e.g., `arn:aws:iam::123456789012:role/payment-secrets-role`).
Verify that the role has the following policy attached:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:ap-south-1:123456789012:secret:production/payment-service-*"
    }
  ]
}
```

*Note: If the secret name in AWS is `production/payment-service`, AWS appends a 6-character random suffix (e.g., `production/payment-service-XXXXXX`). The resource ARN in the IAM policy must end with a wildcard (`*`) or match the exact suffix.*

### Step 3: Verify KMS Permissions (If Encrypted)
If the secret uses a custom KMS key, ensure the IAM role is added as a user of that key:
```json
{
  "Effect": "Allow",
  "Action": "kms:Decrypt",
  "Resource": "arn:aws:kms:ap-south-1:123456789012:key/your-key-uuid"
}
```

### Step 4: Verify the Secret Content
Ensure the secret value in AWS Secrets Manager contains the correct JSON structure:
```json
{
  "db_password": "my-secure-password"
}
```
If the property name in the `ExternalSecret` manifest is `db_password` but the key in Secrets Manager is `password` or `DB_PASSWORD` (case-sensitive), the sync will fail.
