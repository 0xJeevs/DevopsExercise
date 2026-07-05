# Exercise 9: Prometheus Monitoring Failure Analysis

This document details the troubleshooting and root-cause analysis for the Prometheus monitoring failure where the `payment-service` targets are marked as `DOWN` with the error `context deadline exceeded`.

## The Root Cause: Port Name Mismatch

Prometheus Operator uses `ServiceMonitor` resources to discover and scrape application endpoints. It resolves target IPs and ports by matching labels and port names defined in the Kubernetes Service.

In this incident, there is a mismatch in the port naming configuration:

### 1. The Service Definition
The application's Service exposes its endpoint using the name `prometheus`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: payment-service
  labels:
    app: payment-service
spec:
  ports:
    - name: prometheus  # Target port is named 'prometheus'
      port: 8080
      targetPort: 8080
  selector:
    app: payment-service
```

### 2. The ServiceMonitor Definition
The ServiceMonitor specifies the target port to scrape using the name `metrics`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: payment-service-monitor
spec:
  selector:
    matchLabels:
      app: payment-service
  endpoints:
    - port: metrics  # Mismatch: looking for a Service port named 'metrics'
      path: /metrics
      interval: 15s
```

### Why this causes "context deadline exceeded"
Because the ServiceMonitor refers to the port `metrics` which does not exist on the Service:
1. The Prometheus Operator fails to map the endpoint correctly, or maps it to an incorrect default target port (such as the container's default port or port 80).
2. The network connection attempts to connect to a port that the application container is not listening on (or is blocked by Network Policies/Firewalls).
3. The connection attempt times out, resulting in the `context deadline exceeded` error in the Prometheus target console.

---

## How to Fix (Remediation Steps)

To resolve the mismatch, you must align the port names. The standard convention is to name the port `metrics` in both files.

### Step 1: Update the Service Port Name
Edit the Service manifest to change the port name from `prometheus` to `metrics`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: payment-service
  labels:
    app: payment-service
spec:
  ports:
    - name: metrics  # Aligned port name
      port: 8080
      targetPort: 8080
  selector:
    app: payment-service
```

### Step 2: Ensure ServiceMonitor matches
Keep the ServiceMonitor endpoint pointing to `metrics`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: payment-service-monitor
spec:
  selector:
    matchLabels:
      app: payment-service
  endpoints:
    - port: metrics  # Matches the Service port name
      path: /metrics
      interval: 15s
```

### Step 3: Apply the changes
Apply the updated manifests:
```bash
kubectl apply -f service.yaml
kubectl apply -f servicemonitor.yaml
```

### Verification
1. Run `kubectl get endpoints payment-service` to verify the IP and port mapping:
   ```text
   NAME              ENDPOINTS             AGE
   payment-service   10.244.1.45:8080      5m
   ```
2. Log into the Prometheus UI, navigate to **Status -> Targets**, and confirm that `payment-service-monitor` shows the target status as `UP`.
