# Exercise 12: Node NotReady Production Incident

This document details the recovery plan and long-term prevention strategy for a worker node that became `NotReady` due to disk space exhaustion (`DiskPressure=True`).

## Incident Analysis

* **Symptoms**: Node status is `NotReady`, logs report `no space left on device`, and `du -sh /var/log/containers/*` indicates `95GB` of space is consumed by container logs.
* **Impact**: Under `DiskPressure`, the Kubelet attempts to reclaim disk space by evicting pods. If the root volume reaches 100% capacity, the Kubelet itself cannot write state files or communicate with the Kubernetes API, causing it to fall into `NotReady` status.

---

## Safe Node Recovery (Immediate Fix)

Do **NOT** run a blind `rm -rf /var/log/containers/*`. 
Kubernetes container log files in `/var/log/containers/` are symlinks to files under `/var/log/pods/`, which are actively held open by the container runtime (`containerd` or `docker`). Deleting them with `rm` removes the file paths, but the container processes will still hold the open file descriptors, and the disk space will **not** be freed until the processes are restarted.

Follow this safe recovery procedure:

### Step 1: Access the Node via SSM or SSH
SSM into the affected node:
```bash
aws ssm start-session --target <instance-id>
```

### Step 2: Truncate Active Log Files
Using `truncate -s 0` frees the disk space immediately because it reduces the file size to zero without deleting the file or invalidating the file descriptor.

```bash
# Locate and truncate logs larger than 500MB under the pods directory
find /var/log/pods/ -type f -name "*.log" -size +500M -exec truncate -s 0 {} \;
```

### Step 3: Trigger Container Runtime Garbage Collection (Optional)
If disk pressure is still reported, restart the container runtime to force it to release dead container resources and file handles:
```bash
# For containerd (default in newer EKS AMIs)
sudo systemctl restart containerd

# For docker
sudo systemctl restart docker
```
Within a minute, the Kubelet will detect that the disk usage has dropped, remove the `DiskPressure=True` taint, and return the node to `Ready` status.

---

## Long-Term Prevention

To prevent container logs from consuming the entire disk again, implement the following guardrails:

### 1. Configure Kubelet Log Rotation
Configure the Kubelet to automatically rotate and prune container logs using the following arguments in the Kubelet configuration (typically located in `/etc/kubernetes/kubelet/kubelet-config.json` or passed as flags):

* `containerLogMaxSize`: The maximum size a log file can reach before it is rotated (e.g. `10Mi`).
* `containerLogMaxFiles`: The maximum number of container log files that can be present for a container (e.g. `5`).

In the EKS Node bootstrap script (User Data), configure:
```json
{
  "containerLogMaxSize": "10Mi",
  "containerLogMaxFiles": 5
}
```

### 2. Configure Host-level Logrotate
Ensure system logs (such as `/var/log/messages`, `/var/log/secure`, `/var/log/audit/audit.log`) are also rotated. Add a logrotate config `/etc/logrotate.d/kubernetes` on the node:
```text
/var/log/pods/*/*.log {
    rotate 5
    daily
    maxsize 10M
    missingok
    notifempty
    compress
    sharedscripts
}
```

### 3. Deploy Log Shippers & Alerts
- **Deploy Daemonset Log Shippers**: Ensure logs are shipped off-node in near real-time (e.g., via FluentBit or Alloy to CloudWatch/Loki).
- **Set Up Prometheus Alerts**: Create an alert to notify the operations team when disk usage exceeds 80%:
  ```yaml
  alert: NodeDiskRunningFull
  expr: (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Host disk space running low on {{ $labels.instance }}"
  ```
