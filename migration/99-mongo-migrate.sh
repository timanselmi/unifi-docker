#!/usr/bin/env bash
# Embedded MongoDB migration helper.
# Runs at container start via: run-parts /usr/unifi/init.d/
#
# Applies ONLY to standalone containers using embedded MongoDB.
# Skipped automatically when DB_URI is set (external MongoDB users
# should use backup.sh + restore.sh instead).
#
# On first launch after upgrading from a pre-7.0 image:
#   - Archives the old MongoDB data directory
#   - Logs the most recent autobackup .unf path so you know what to restore

. /usr/unifi/functions

MARKER_FILE="${DATADIR}/.mongo_version_marker"
DB_DIR="${DATADIR}/db"
AUTOBACKUP_DIR="${DATADIR}/backup/autobackup"

# Skip if using external MongoDB (docker-compose path)
if [ -n "${DB_URI:-}" ]; then
    exit 0
fi

# Marker present → already migrated or fresh 7.0 install, nothing to do
if [ -f "${MARKER_FILE}" ]; then
    exit 0
fi

# Marker absent + db directory exists → pre-7.0 data, needs archiving
if [ -d "${DB_DIR}" ]; then
    ARCHIVE_DIR="${DATADIR}/db_archive_$(date +%Y%m%d_%H%M%S)"
    log "MIGRATION: Old MongoDB data directory detected (no version marker present)."
    log "MIGRATION: Archiving ${DB_DIR} → ${ARCHIVE_DIR}"
    mv "${DB_DIR}" "${ARCHIVE_DIR}"
    log "MIGRATION: Archive complete. MongoDB 7.0 will initialise a fresh database."

    # Find most recent autobackup and tell the user about it
    LATEST_BACKUP=$(ls -t "${AUTOBACKUP_DIR}"/*.unf 2>/dev/null | head -1 || true)
    if [ -n "${LATEST_BACKUP}" ]; then
        log "MIGRATION: *** ACTION REQUIRED ***"
        log "MIGRATION: Autobackup found: ${LATEST_BACKUP}"
        log "MIGRATION: After completing setup, restore via:"
        log "MIGRATION:   Settings → System → Backup → Restore"
    else
        log "MIGRATION: WARNING: No autobackup found in ${AUTOBACKUP_DIR}"
        log "MIGRATION: You may need to reconfigure UniFi from scratch."
        log "MIGRATION: Your old database files are preserved at: ${ARCHIVE_DIR}"
    fi
fi

# Write version marker so this only runs once
echo "7.0" > "${MARKER_FILE}"
