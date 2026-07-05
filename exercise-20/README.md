# Exercise 20: External Secrets Integration

This project integrates **AWS Secrets Manager** with EKS using the **External Secrets Operator (ESO)** to automatically synchronize keys (`DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`) into a native Kubernetes Secret.

## Directory Structure

```text
exercise-20/
├── secretstore.yaml     # Specifies AWS Secrets Manager provider configuration
├── externalsecret.yaml  # Maps AWS secret keys to the target Kubernetes Secret
└── README.md            # Integration walkthrough and validation commands
```

---

## Technical Workflow

1. A secret containing `db_username`, `db_password`, and `jwt_secret` is created in AWS Secrets Manager under the path `production/payment-service-secrets`.
2. The `SecretStore` acts as a cluster/namespace bridge, pointing to AWS Secrets Manager using the regional endpoint (`ap-south-1`) and referencing the EKS ServiceAccount (`payment-service-sa`) that has the IRSA IAM role.
3. The `ExternalSecret` requests the mapping of specific keys and properties from AWS Secrets Manager to the Kubernetes Secret resource `payment-app-secret`.
4. The ESO controller polls AWS at the specified `refreshInterval` (e.g., every 10 minutes) and reconciles changes.

---

## Setup & Execution

### Step 1: Store the Secrets in AWS Secrets Manager
Run the AWS CLI command to create the secret structure:
```bash
aws secretsmanager create-secret \
  --name production/payment-service-secrets \
  --description "Database and JWT secrets for payment-service" \
  --secret-string '{"db_username":"payment_admin","db_password":"SuperSecurePassword123!","jwt_secret":"MyUltraSecretJWTKey2026"}' \
  --region ap-south-1
```

### Step 2: Deploy the SecretStore
```bash
kubectl apply -f secretstore.yaml -n production
```

### Step 3: Deploy the ExternalSecret
```bash
kubectl apply -f externalsecret.yaml -n production
```

---

## Verification & Validation

### 1. Verify the ExternalSecret Status
Check if the operator successfully synced the secret:
```bash
kubectl get externalsecret payment-secret-sync -n production
```
*Expected Output:*
```text
NAME                  STORE                 REFRESH   STATUS         READY
payment-secret-sync   aws-secrets-manager   10m       SecretSynced   True
```

### 2. Verify the Native Kubernetes Secret is Created
Verify that the target Kubernetes Secret `payment-app-secret` was automatically generated:
```bash
kubectl get secret payment-app-secret -n production
```
*Expected Output:*
```text
NAME                 TYPE     DATA   AGE
payment-app-secret   Opaque   3      1m
```

### 3. Verify Secret Contents (Decoded)
Confirm the values were decoded and mapped correctly:
```bash
kubectl get secret payment-app-secret -n production -o jsonpath='{.data.DB_USERNAME}' | base64 --decode
# Output: payment_admin

kubectl get secret payment-app-secret -n production -o jsonpath='{.data.DB_PASSWORD}' | base64 --decode
# Output: SuperSecurePassword123!

kubectl get secret payment-app-secret -n production -o jsonpath='{.data.JWT_SECRET}' | base64 --decode
# Output: MyUltraSecretJWTKey2026
```
This confirms that the synchronization pipeline is fully operational.
