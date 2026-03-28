#!/usr/bin/env bash
# backup.sh — dump MongoDB data from a running mongo:3.6 container.
#
# Run this BEFORE upgrading to the new stack (while the OLD stack is still up).
# For docker-compose deployments with an external MongoDB container only.
#
# Standalone containers using embedded MongoDB are handled automatically by
# migration/99-mongo-migrate.sh on first launch of the new image.

set -euo pipefail

PROJECT="${COMPOSE_PROJECT_NAME:-unifi}"
NETWORK="${PROJECT}_unifi"
BACKUP_DIR="$(pwd)/mongo-backup"

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "Checking that the mongo service is running..."
if ! docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "^mongo$"; then
    echo "ERROR: mongo service is not running."
    echo "       Start your stack first: docker compose up -d"
    exit 1
fi

log "Creating backup directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

log "Dumping MongoDB from running mongo container..."
docker run --rm \
    --network "${NETWORK}" \
    -v "${BACKUP_DIR}:/dump" \
    mongo:3.6 \
    mongodump --host mongo --out /dump

DUMP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
log "Dump complete. Size: ${DUMP_SIZE}"
log "Backup saved to: ${BACKUP_DIR}"
log ""
log "Next steps to complete the upgrade:"
log "  1. docker compose down"
log "  2. docker compose up -d mongo   # starts mongo:7.0 only"
log "  3. ./restore.sh                 # restores data into mongo:7.0"
log "  4. docker compose up -d         # bring up the full stack"
