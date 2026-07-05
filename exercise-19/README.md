# Exercise 19: Helm Chart Engineering

This project builds a reusable, environment-agnostic **Helm Chart** for EKS microservices. It abstracts away common Kubernetes objects, exposing a simple parameters surface for environment configuration.

## Directory Structure

```text
payment-service-chart/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default values
├── values-dev.yaml         # Dev environment overrides
├── values-qa.yaml          # QA environment overrides
├── values-prod.yaml        # Prod environment overrides
└── templates/              # Kubernetes templates
    ├── _helpers.tpl        # Template labels and naming helpers
    ├── deployment.yaml     # Application deployment template
    ├── service.yaml        # ClusterIP service template
    ├── ingress.yaml        # ALB Ingress template
    ├── configmap.yaml      # Environmental variables ConfigMap
    ├── secret.yaml         # Sensitive configurations Secret
    └── hpa.yaml            # Autoscaling configuration template
```

---

## Features Supported

1. **Replicas**: Managed statically when autoscaling is disabled, or dynamically via HPA.
2. **Resources**: Configurable limits and requests per container, optimized for different staging requirements.
3. **ConfigMaps**: Populates system environment variables dynamically from key-value lists.
4. **Secrets**: Automatically encodes sensitive inputs into Kubernetes opaque Secrets.
5. **Ingress**: Deploys an Ingress configuration targeting the ALB controller, supporting custom domains and SSL termination.
6. **Autoscaling**: Mounts a Horizontal Pod Autoscaler targeting CPU utilization thresholds.

---

## Environment Comparison

| Parameters | Dev | QA | Prod |
|---|---|---|---|
| **Replicas** | 1 (Static) | 2 (Min) / 5 (Max) | 3 (Min) / 10 (Max) |
| **CPU Requests** | 50m | 200m | 500m |
| **Memory Requests** | 64Mi | 256Mi | 512Mi |
| **Ingress Host** | `dev-payment.example.com` | `qa-payment.example.com` | `payment.example.com` |
| **Autoscaling** | Disabled | Enabled (Target: 80% CPU) | Enabled (Target: 75% CPU) |
| **SSL Redirect** | No | No | Yes (Redirect 80 -> 443) |

---

## How to Run & Verify

Before deploying, you can render and validate the template configuration for any environment.

### 1. Render Dev templates
```bash
helm template payment-service ./payment-service-chart -f ./payment-service-chart/values-dev.yaml
```

### 2. Render Prod templates
```bash
helm template payment-service ./payment-service-chart -f ./payment-service-chart/values-prod.yaml
```

### 3. Dry-run installation in production
Test configuration validity directly on the active EKS cluster without running live updates:
```bash
helm install payment-service ./payment-service-chart \
  -f ./payment-service-chart/values-prod.yaml \
  --namespace production \
  --dry-run
```
All resources will print out and lint check successfully.
