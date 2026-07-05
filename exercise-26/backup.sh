#!/bin/bash
# EKS / Application Configuration S3 Backup Script
set -e

# Configuration
BUCKET_NAME=${S3_BACKUP_BUCKET:-"my-eks-backups-123456789012"}
BACKUP_DIR="/tmp/backup_staging"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="app_config_backup_${TIMESTAMP}.tar.gz"

echo "=== STARTING BACKUP PROCESS ==="

# 1. Clean and create staging directory
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# 2. Collect Kubernetes Configurations
echo "--> Backing up active Kubernetes namespace config..."
kubectl get all -n production -o yaml > "${BACKUP_DIR}/k8s_production_all.yaml"
kubectl get configmaps -n production -o yaml > "${BACKUP_DIR}/k8s_production_cms.yaml"
kubectl get secrets -n production -o yaml > "${BACKUP_DIR}/k8s_production_secrets.yaml"

# 3. Collect local application config files
echo "--> Collecting application config files..."
cp -r /app/config "${BACKUP_DIR}/app_configs" 2>/dev/null || echo "No local app configs in /app/config"

# 4. Compress files
echo "--> Creating tarball archive..."
tar -czf "/tmp/${BACKUP_FILE}" -C "$BACKUP_DIR" .

# 5. Upload to S3
echo "--> Uploading backup archive to S3 bucket [s3://${BUCKET_NAME}]..."
# Assumes pod has S3 PutObject permission via IRSA
aws s3 cp "/tmp/${BACKUP_FILE}" "s3://${BUCKET_NAME}/backups/${BACKUP_FILE}"

# 6. Cleanup local temporary staging files
rm -rf "$BACKUP_DIR"
rm -f "/tmp/${BACKUP_FILE}"

echo "=== BACKUP COMPLETED SUCCESSFULY ==="
