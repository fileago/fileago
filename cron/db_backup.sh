#!/bin/bash
# --------------------------------------------------------------------------
# Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.
#
# This software is proprietary and confidential.
# Unauthorized copying of this file, via any medium, is strictly prohibited.
# 
# For license information, see the LICENSE.txt file in the root directory of
# this project.
# --------------------------------------------------------------------------

# db_backup.sh - Script to handle Neo4j data backup and its retention.
# It is executed daily via cron.sh script. No need to manually run it.

set -euo pipefail

# ---------- Backup Configuration (can be changed) ----------
ENABLE_BACKUP=true
CREATE_TARBALL=true
RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=2
CHECK_CONSISTENCY=false

# ---------- Db Configuration (do not modify) ----------
NEO4J_BIN="/var/lib/neo4j/bin"
TIMESTAMP=$(date +%Y-%m-%d.%H-%M)
BACKUP_ROOT="/backup"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

# Check if backup is enabled
if [ "$ENABLE_BACKUP" != "true" ]; then
  echo "Backup disabled via ENABLE_BACKUP config. Exiting."
  exit 0
fi

# Ensure directories exist
mkdir -p "${BACKUP_DIR}" "${BACKUP_ROOT}/daily" "${BACKUP_ROOT}/weekly" "${BACKUP_ROOT}/monthly"

# Execute Neo4j backup
echo "Starting Neo4j backup..."
if ! "${NEO4J_BIN}/neo4j-admin" backup \
  --backup-dir="${BACKUP_DIR}" \
  --name="graph.db" \
  --check-consistency="${CHECK_CONSISTENCY}"; then
  echo "Backup failed! Exiting..."
  rm -rf "${BACKUP_DIR}"
  exit 1
fi

# Determine backup type based on day
day_of_week=$(date +%u)
day_of_month=$(date +%d)

if [ "${day_of_month}" == "01" ]; then
  TARGET_DIR="${BACKUP_ROOT}/monthly"
elif [ "${day_of_week}" == "7" ]; then
  TARGET_DIR="${BACKUP_ROOT}/weekly"
else
  TARGET_DIR="${BACKUP_ROOT}/daily"
fi

if [ "$CREATE_TARBALL" == "true" ]; then
  echo "Creating archive..."
  tar -czf "${BACKUP_ROOT}/${TIMESTAMP}.tar.gz" -C "${BACKUP_ROOT}" "${TIMESTAMP}"
  mv "${BACKUP_ROOT}/${TIMESTAMP}.tar.gz" "${TARGET_DIR}/"
  rm -rf "${BACKUP_DIR}"
  
  echo "Applying retention policies..."
  find "${BACKUP_ROOT}/daily" -name "*.tar.gz" -type f -mtime +${RETENTION_DAILY} -delete
  find "${BACKUP_ROOT}/weekly" -name "*.tar.gz" -type f -mtime +$((RETENTION_WEEKLY * 7)) -delete
  find "${BACKUP_ROOT}/monthly" -name "*.tar.gz" -type f -mtime +$((RETENTION_MONTHLY * 30)) -delete
  
  echo "Backup completed successfully: ${TIMESTAMP}.tar.gz"
else
  mv "${BACKUP_DIR}" "${TARGET_DIR}/${TIMESTAMP}"
  
  echo "Applying retention policies..."
  find "${BACKUP_ROOT}/daily" -mindepth 1 -maxdepth 1 -type d -mtime +${RETENTION_DAILY} -exec rm -rf {} \;
  find "${BACKUP_ROOT}/weekly" -mindepth 1 -maxdepth 1 -type d -mtime +$((RETENTION_WEEKLY * 7)) -exec rm -rf {} \;
  find "${BACKUP_ROOT}/monthly" -mindepth 1 -maxdepth 1 -type d -mtime +$((RETENTION_MONTHLY * 30)) -exec rm -rf {} \;
  
  echo "Backup completed successfully: ${TIMESTAMP}"
fi
