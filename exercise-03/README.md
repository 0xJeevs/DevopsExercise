# Exercise 3: ArgoCD OutOfSync Production Incident

This document details the analysis of the ArgoCD OutOfSync incident where the live cluster has 5 replicas of the `payment-service` while the Git repository specifies only 3.

## Incident Investigation

### 1. What Changed (ArgoCD Diff)
Running `argocd app diff payment-service` would show the following diff:
```diff
===== apps/Deployment production/payment-service ======
3c3
<   replicas: 3
---
>   replicas: 5
```
The live cluster state has drifted from the Git configuration by scaling from 3 to 5 replicas.

---

### 2. Who Changed It (Finding the Root Cause)

There are two primary scenarios that cause this mismatch:

#### Scenario A: The Horizontal Pod Autoscaler (HPA) Scaled It
If there is an HPA resource targeting the `payment-service` deployment, it will dynamically modify the `spec.replicas` field in the live cluster during peak load.
* **To Verify**: Check if an HPA exists:
  ```bash
  kubectl get hpa -n production
  ```
  Check the HPA events to see if it triggered scale-up actions:
  ```bash
  kubectl describe hpa payment-service-hpa -n production
  ```

#### Scenario B: Manual Hotfix / CLI Intervention
A engineer manually ran a command such as `kubectl scale deployment payment-service --replicas=5` or edited the deployment in-place to handle traffic.
* **To Verify**: Query the Kubernetes API Server Audit Logs (e.g., via CloudWatch Logs Insights for EKS):
  ```sql
  fields @timestamp, user.username, userAgent, verb, requestURI
  | filter requestURI like "/apis/apps/v1/namespaces/production/deployments/payment-service"
  | filter verb in ["patch", "update"]
  | sort @timestamp desc
  | limit 20
  ```
  This will reveal the IAM user/Role or ServiceAccount (`user.username`) and client tool (`userAgent`) that executed the change.

---

## 3. How to Prevent Recurrence

Depending on the cause, apply the appropriate remediation path:

### Option 1: If using Horizontal Pod Autoscaling (HPA)
When using an HPA, ArgoCD should ignore changes to the `replicas` field to prevent it from constantly fighting the HPA and forcing a roll-back.

1. **Configure `ignoreDifferences` in the ArgoCD Application**:
   Modify the ArgoCD Application resource to ignore changes to the replicas field:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: payment-service
     namespace: argocd
   spec:
     # ... other specs ...
     ignoreDifferences:
       - group: apps
         kind: Deployment
         jsonPointers:
           - /spec/replicas
   ```
2. **Remove `replicas` from the Git Deployment Manifest**:
   Remove the line `replicas: 3` from the git-managed deployment YAML. When deploying, Kubernetes will initialize with default replicas (1), and then the HPA will immediately scale it to the desired count.

---

### Option 2: If the scale was a manual intervention (No HPA)
If HPA is not in use, manual changes should be forbidden and automatically reverted:

1. **Enable ArgoCD Self-Heal**:
   Ensure ArgoCD's `selfHeal` is set to `true`. This will detect the manual manual changes and automatically override them, bringing the cluster replicas back to 3.
   ```yaml
   spec:
     syncPolicy:
       automated:
         prune: true
         selfHeal: true  # Automatically overrides manual drift
   ```
2. **Lock Down IAM & RBAC**:
   Restrict `update`, `patch`, and `scale` permissions on deployments within the production namespace. Developers should only have Read-Only permissions, forcing all changes to go through the Pull Request (PR) review process in Git.
