# Exercise 26: S3 Backup & Restore Solution

This project implements an automated, secure **Backup & Restore Strategy** for application configurations and Kubernetes resources on EKS using **Amazon S3** as the durable storage backend.

## Directory Structure

```text
exercise-26/
├── backup.sh        # Packages configs and uploads them to S3
├── restore.sh       # Downloads configs from S3 and re-applies them to EKS
└── README.md        # Backup architecture and restore verification guide
```

---

## Technical Architecture

```mermaid
graph TD
    CronJob[Kubernetes CronJob] -->|Triggers Schedule| BackupPod[Backup Job Pod]
    BackupPod -->|1. Executes backup.sh| K8sAPI[Kubernetes API Server]
    K8sAPI -->|2. Pulls active YAMLs| BackupPod
    BackupPod -->|3. Packages tarball| Storage[/tmp/staging]
    BackupPod -->|4. Assumes IAM Role| AWSSTS[AWS STS]
    BackupPod -->|5. Uploads archive| AWSS3[Amazon S3 Bucket]
```

### 1. IAM S3 Access Configuration (IRSA)
To allow EKS workloads to backup to S3, a dedicated ServiceAccount is used that maps to an IAM role with S3 write permissions.

#### IAM S3 Policy (`backup-s3-policy.json` snippet)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-eks-backups-123456789012",
        "arn:aws:s3:::my-eks-backups-123456789012/*"
      ]
    }
  ]
}
```

---

## Scheduling via Kubernetes CronJob

Deploy a CronJob to run the backup script daily at 2:00 AM:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: platform-backup-job
  namespace: production
spec:
  schedule: "0 2 * * *"  # Run every day at 2:00 AM
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: backup-sa  # Uses IRSA with S3 IAM Role
          restartPolicy: OnFailure
          containers:
            - name: backup-container
              image: amazon/aws-cli:latest
              command: ["/bin/bash", "-c", "/scripts/backup.sh"]
              env:
                - name: S3_BACKUP_BUCKET
                  value: "my-eks-backups-123456789012"
              volumeMounts:
                - name: script-vol
                  mountPath: /scripts
          volumes:
            - name: script-vol
              configMap:
                name: backup-scripts
```

---

## Demonstration: Execute Backup & Restore

### Part 1: Running a Manual Backup
To run the backup immediately without waiting for the cron schedule:
```bash
# Create manual job from existing CronJob configuration
kubectl create job --from=cronjob/platform-backup-job manual-backup-001 -n production

# Monitor logs
kubectl logs -f job/manual-backup-001 -n production
```
*Expected logs:*
```text
=== STARTING BACKUP PROCESS ===
--> Backing up active Kubernetes namespace config...
--> Collecting application config files...
--> Creating tarball archive...
--> Uploading backup archive to S3 bucket [s3://my-eks-backups-123456789012]...
upload: /tmp/app_config_backup_20260705_213500.tar.gz to s3://my-eks-backups-123456789012/backups/app_config_backup_20260705_213500.tar.gz
=== BACKUP COMPLETED SUCCESSFULY ===
```

---

### Part 2: Simulating Disaster Recovery (Restoration)

#### Step 1: Simulate configuration loss
Delete a ConfigMap and scale the deployment to 0:
```bash
kubectl delete configmap payment-service-config -n production
kubectl scale deployment payment-service --replicas=0 -n production
```

#### Step 2: Trigger the Restore Process
Run the restore script inside a restore helper pod, or execute the script directly from a management host:
```bash
# Executing restore.sh without arguments auto-selects the latest backup archive from S3
./restore.sh
```
*Expected restore logs:*
```text
=== STARTING RESTORE PROCESS ===
No specific backup file provided. Querying ECR / S3 for the latest backup...
--> Restoring from: s3://my-eks-backups-123456789012/backups/app_config_backup_20260705_213500.tar.gz
--> Downloading backup archive...
download: s3://my-eks-backups-123456789012/backups/app_config_backup_20260705_213500.tar.gz to /tmp/app_config_backup_20260705_213500.tar.gz
--> Extracting files...
--> Re-applying Kubernetes resources to EKS...
configmap/payment-service-config created
deployment.apps/payment-service configured
=== RESTORE COMPLETED SUCCESSFULY ===
```

#### Step 3: Verify Restoration
Confirm that the ConfigMap is restored and the Deployment has scaled back to its original replica count:
```bash
kubectl get configmap payment-service-config -n production
kubectl get deploy payment-service -n production
```
The resources will be back up and running, confirming a successful restoration flow.
