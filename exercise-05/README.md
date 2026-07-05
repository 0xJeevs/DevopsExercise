# Exercise 5: Helm Upgrade Failure

This document analyzes the Helm upgrade failure caused by attempting to change the deployment's label selector (`spec.selector.matchLabels`) in Version 2 of the chart.

## Why Immutable Field Errors Occur

In Kubernetes, the `spec.selector` field of a `Deployment`, `StatefulSet`, or `DaemonSet` is **immutable** once the resource is created. 

The selector defines the label query that the Deployment Controller uses to identify and manage its Pods. Allowing this field to change dynamically on an existing Deployment would lead to critical issues:
1. **Orphaned Pods**: The existing running pods (labeled `app: payment`) would no longer match the new selector (`app: payment-v2`). The controller would stop managing them, leaving them running indefinitely without updates or garbage collection.
2. **Resource Duplication**: The deployment controller, seeing zero pods matching the new selector `app: payment-v2`, would immediately spin up a new set of pods, potentially overloading cluster resources.

To prevent this, the Kubernetes API server rejects any patch or update request that changes `spec.selector`.

---

## Safe Upgrade Approaches

There are three ways to handle this in a production environment:

### Approach 1: Re-create the Deployment (Downtime Allowed)
If a brief period of downtime (seconds to minutes) is acceptable, delete the Deployment resource directly from the cluster, then run the helm upgrade:

```bash
# 1. Delete the deployment resource only (leaves services, ingresses, secrets intact)
kubectl delete deployment payment-service -n production

# 2. Run the Helm upgrade (which will recreate the deployment with the new selector)
helm upgrade payment-service . -n production
```

---

### Approach 2: Use Stable Selectors (Industry Best Practice)
To prevent this issue entirely, keep `spec.selector` stable and use other labels (like `version` or `app.kubernetes.io/version`) on the Pod template metadata for version tracking. 

* **Incorrect (Versioned Selector)**:
  ```yaml
  spec:
    selector:
      matchLabels:
        app: payment-v2 # Forces recreation on every version bump
  ```

* **Correct (Stable Selector + Dynamic Pod Labels)**:
  ```yaml
  spec:
    selector:
      matchLabels:
        app: payment # Remains stable forever
    template:
      metadata:
        labels:
          app: payment
          version: v2.0.0 # Can be changed freely
  ```

---

### Approach 3: Blue-Green Deployment (Zero-Downtime Migration)
If you must change the selector name and need zero-downtime:

1. **Deploy a new Deployment resource**:
   In the Helm templates, append the version to the deployment name (e.g. `payment-service-v2`), so that Kubernetes treats it as a new resource rather than patching the existing one.
2. **Update the Service Selector**:
   The Service resource selector **is mutable**. Update the Service's selector to point to the new label `app: payment-v2`. Traffic will instantly shift to the new pods.
3. **Prune the Old Deployment**:
   Once verified, delete the old deployment resource `payment-service-v1` manually or let Helm prune it (if managed properly via Helm releases).
