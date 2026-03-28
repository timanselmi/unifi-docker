#!/usr/bin/env bash
# restore.sh — restore MongoDB data into a running mongo:7.0 container.
#
# Run this AFTER:
#   docker compose down
#   docker compose up -d mongo   (starts the new mongo:7.0 service)
#
# For docker-compose deployments with an external MongoDB container only.

set -euo pipefail

PROJECT="${COMPOSE_PROJECT_NAME:-unifi}"
NETWORK="${PROJECT}_unifi"
BACKUP_DIR="$(pwd)/mongo-backup"

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "Checking backup directory..."
if [ ! -d "${BACKUP_DIR}" ] || [ -z "$(ls -A "${BACKUP_DIR}" 2>/dev/null)" ]; then
    echo "ERROR: No backup found at ${BACKUP_DIR}"
    echo "       Run ./backup.sh against the old stack first."
    exit 1
fi

log "Checking that the mongo service is running..."
if ! docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "^mongo$"; then
    echo "ERROR: mongo service is not running."
    echo "       Start it first: docker compose up -d mongo"
    exit 1
fi

log "Restoring MongoDB data into mongo:7.0..."
docker run --rm \
    --network "${NETWORK}" \
    -v "${BACKUP_DIR}:/dump" \
    mongo:7.0 \
    mongorestore --host mongo --drop /dump

log "Restore complete."
log ""
log "Next step: docker compose up -d"
