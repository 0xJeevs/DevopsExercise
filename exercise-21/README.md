# Exercise 21: Production ALB Ingress Setup

This project configures an **AWS Application Load Balancer (ALB) Ingress Controller** to expose three microservices under a single domain name (`app.example.com`) using path-based routing, SSL termination, and HTTP-to-HTTPS redirect rules.

## Directory Structure

```text
exercise-21/
├── ingress.yaml     # Ingress manifest with routing, SSL, and redirect annotations
└── README.md        # Integration explanation and validation guide
```

---

## Routing & Specifications

### 1. Ingress Paths
Traffic is split and forwarded based on the URL prefix:
- **`app.example.com/api/*`** is forwarded to **`api-service`** on port `8080`.
- **`app.example.com/admin/*`** is forwarded to **`admin-service`** on port `8081`.
- **`app.example.com/dashboard/*`** is forwarded to **`dashboard-service`** on port `8082`.

### 2. SSL Termination & HTTPS Redirection
- **SSL Certificate**: Managed via AWS Certificate Manager (ACM) and attached to the ALB listener using the `alb.ingress.kubernetes.io/certificate-arn` annotation.
- **Redirection**: Traffic arriving on port 80 (HTTP) is matched against the `ssl-redirect` action rule first, executing a 301 Permanent Redirect to port 443 (HTTPS) at the load balancer level, reducing latency and avoiding traffic overhead inside the EKS cluster.

### 3. Health Checks
Health checks are configured globally:
- Endpoint: `/healthz`
- Interval: 15 seconds
- Success Code: HTTP 200
- If any backend container fails to respond successfully, the ALB will mark that IP as unhealthy and stop routing traffic to it.

---

## How to Deploy & Verify

### Step 1: Deploy the Ingress
Apply the ingress rules in EKS:
```bash
kubectl apply -f ingress.yaml -n production
```

### Step 2: Monitor ALB Controller Logs
Confirm that the controller successfully intercepts the Ingress creation and provisions the AWS ALB:
```bash
kubectl logs -f -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```
*Expected Log output:*
```text
{"level":"info","ts":"...","msg":"creating loadBalancer","loadBalancerName":"k8s-production-platform-xxxxxx"}
{"level":"info","ts":"...","msg":"creating listener","port":80}
{"level":"info","ts":"...","msg":"creating listener","port":443}
{"level":"info","ts":"...","msg":"successfully created Ingress"}
```

### Step 3: Retrieve the ALB DNS Name
Get the external address of the newly provisioned ALB:
```bash
kubectl get ingress platform-ingress -n production
```
*Expected Output:*
```text
NAME               CLASS    HOSTS             ADDRESS                                                                  PORTS   AGE
platform-ingress   <none>   app.example.com   k8s-production-platform-xxxxxx.ap-south-1.elb.amazonaws.com              80, 443 2m
```

### Step 4: Map DNS
Map a CNAME record in Route53 or your DNS manager pointing `app.example.com` to the ALB DNS Name:
`k8s-production-platform-xxxxxx.ap-south-1.elb.amazonaws.com`.

### Step 5: Test Connections (Curl)
Verify the HTTP redirect:
```bash
curl -I http://app.example.com/api/v1/users
```
*Expected Output:*
```text
HTTP/1.1 301 Moved Permanently
Server: awselb/2.0
Date: Sun, 05 Jul 2026 21:35:00 GMT
Content-Type: text/html
Content-Length: 134
Connection: keep-alive
Location: https://app.example.com:443/api/v1/users
```

Verify path-based SSL routing:
```bash
curl -I https://app.example.com/dashboard/index.html
# Returns HTTP 200 (if dashboard service is active and healthy)
```
