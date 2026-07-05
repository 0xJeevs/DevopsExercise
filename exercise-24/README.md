# Exercise 24: DynamoDB Application Deployment

This project deploys a Python microservice to EKS that performs CRUD operations (Read, Write, Update) on Amazon DynamoDB. The container executes without static AWS credentials, relying on **IAM Roles for Service Accounts (IRSA)** for authentication.

## Directory Structure

```text
exercise-24/
├── app.py             # Flask application using boto3
├── requirements.txt   # Python project dependencies
├── Dockerfile         # Docker packaging configuration
├── deployment.yaml    # Kubernetes deployment and service manifests
└── README.md          # Setup and execution guide
```

---

## Technical Flow & Security

Rather than injecting static credentials (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) which risk source exposure, the application uses **IRSA**:
- The deployment is associated with the `payment-service-sa` ServiceAccount.
- The EKS Pod Identity Webhook injects temporary authentication files into the container at startup.
- The `boto3` SDK automatically resolves these tokens and assumes the designated IAM role (`payment-service-dynamodb-role`) to communicate securely with DynamoDB.

---

## CRUD API Endpoints

1. **GET `/customer/<id>`**
   - Operation: reads a record from DynamoDB using `GetItem`.
   - Action: `table.get_item(Key={'customer_id': customer_id})`
2. **POST `/customer`**
   - Operation: creates a customer record using `PutItem`.
   - Action: `table.put_item(Item=data)`
3. **PUT `/customer/<id>`**
   - Operation: updates a customer record attribute using `UpdateItem`.
   - Action: `table.update_item(...)`
4. **GET `/healthz`**
   - Operation: runs a lightweight healthcheck on DynamoDB via `describe_table`.

---

## Execution Guide

### Step 1: Create the DynamoDB Table
Verify that the `customer-data` table is created in AWS:
```bash
aws dynamodb create-table \
    --table-name customer-data \
    --attribute-definitions AttributeName=customer_id,AttributeType=S \
    --key-schema AttributeName=customer_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region ap-south-1
```

### Step 2: Build and Push the Container
```bash
# Build the image
docker build -t 123456789012.dkr.ecr.ap-south-1.amazonaws.com/customer-service:latest .

# Authenticate docker to AWS ECR
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.ap-south-1.amazonaws.com

# Push the image
docker push 123456789012.dkr.ecr.ap-south-1.amazonaws.com/customer-service:latest
```

### Step 3: Deploy to EKS
```bash
kubectl apply -f deployment.yaml -n production
```

---

## Verification & API Testing

### 1. Test Readiness (Health check)
Verify the pod connects successfully to DynamoDB:
```bash
# Port-forward the service to test locally
kubectl port-forward svc/customer-service 8080:80 -n production
```
In another terminal, check health:
```bash
curl http://localhost:8080/healthz
# Expected output: {"status": "healthy"}
```

### 2. Test Write (POST)
Write a new customer record to DynamoDB:
```bash
curl -X POST http://localhost:8080/customer \
  -H "Content-Type: application/json" \
  -d '{"customer_id": "cust-999", "name": "Alice Smith", "email": "alice@example.com"}'
# Expected output: {"message": "Customer created successfully"}
```

### 3. Test Read (GET)
Read the created customer:
```bash
curl http://localhost:8080/customer/cust-999
# Expected output: {"customer_id": "cust-999", "name": "Alice Smith", "email": "alice@example.com"}
```

### 4. Test Update (PUT)
Update the customer details:
```bash
curl -X PUT http://localhost:8080/customer/cust-999 \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice Jones"}'
# Expected output: {"message": "Customer updated successfully", "attributes": {"name": "Alice Jones"}}
```
Verify the change in DynamoDB using the AWS CLI:
```bash
aws dynamodb get-item --table-name customer-data --key '{"customer_id": {"S": "cust-999"}}' --region ap-south-1
```
The name field will return "Alice Jones", validating that EKS assumed the IAM role and authorized the write operations.
