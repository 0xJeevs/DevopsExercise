#!/bin/bash
# EKS / Application Configuration S3 Restore Script
set -e

# Configuration
BUCKET_NAME=${S3_BACKUP_BUCKET:-"my-eks-backups-123456789012"}
RESTORE_DIR="/tmp/restore_staging"
TARGET_NAMESPACE="production"

# If backup file is not provided as an argument, get the latest backup from S3
if [ -z "$1" ]; then
    echo "No specific backup file provided. Querying ECR / S3 for the latest backup..."
    LATEST_BACKUP=$(aws s3 ls "s3://${BUCKET_NAME}/backups/" | sort | tail -n 1 | awk '{print $4}')
    if [ -z "$LATEST_BACKUP" ]; then
        echo "ERROR: No backups found in S3 bucket s3://${BUCKET_NAME}/backups/"
        exit 1
    fi
    BACKUP_FILE="$LATEST_BACKUP"
else
    BACKUP_FILE="$1"
fi

echo "=== STARTING RESTORE PROCESS ==="
echo "--> Restoring from: s3://${BUCKET_NAME}/backups/${BACKUP_FILE}"

# 1. Clean and create staging directory
rm -rf "$RESTORE_DIR"
mkdir -p "$RESTORE_DIR"

# 2. Download from S3
echo "--> Downloading backup archive..."
aws s3 cp "s3://${BUCKET_NAME}/backups/${BACKUP_FILE}" "/tmp/${BACKUP_FILE}"

# 3. Extract contents
echo "--> Extracting files..."
tar -xzf "/tmp/${BACKUP_FILE}" -C "$RESTORE_DIR"

# 4. Restore Kubernetes Manifests
echo "--> Re-applying Kubernetes resources to EKS..."
if [ -f "${RESTORE_DIR}/k8s_production_cms.yaml" ]; then
    kubectl apply -f "${RESTORE_DIR}/k8s_production_cms.yaml" -n "$TARGET_NAMESPACE"
fi

if [ -f "${RESTORE_DIR}/k8s_production_secrets.yaml" ]; then
    # Filter metadata properties that would conflict (like resourceVersion, uid) if re-applying directly
    kubectl apply -f "${RESTORE_DIR}/k8s_production_secrets.yaml" -n "$TARGET_NAMESPACE"
fi

if [ -f "${RESTORE_DIR}/k8s_production_all.yaml" ]; then
    kubectl apply -f "${RESTORE_DIR}/k8s_production_all.yaml" -n "$TARGET_NAMESPACE"
fi

# 5. Restore application configuration files locally if needed
if [ -d "${RESTORE_DIR}/app_configs" ]; then
    echo "--> Restoring local application config directory..."
    mkdir -p /app/config
    cp -r "${RESTORE_DIR}/app_configs/." /app/config/
fi

# 6. Clean staging directory
rm -rf "$RESTORE_DIR"
rm -f "/tmp/${BACKUP_FILE}"

echo "=== RESTORE COMPLETED SUCCESSFULY ==="
