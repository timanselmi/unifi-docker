#!/usr/bin/env bash
# Embedded MongoDB migration helper.
# Runs at container start via: run-parts /usr/unifi/init.d/
#
# Applies ONLY to standalone containers using embedded MongoDB.
# Skipped automatically when DB_URI is set (external MongoDB users
# should use backup.sh + restore.sh instead).
#
# On first launch after upgrading from a pre-8.0 image:
#   - Archives the old MongoDB data directory
#   - Logs the most recent autobackup .unf path so you know what to restore

. /usr/unifi/functions

MARKER_FILE="${DATADIR}/.mongo_version_marker"
DB_DIR="${DATADIR}/db"

# Skip if using external MongoDB (docker-compose path)
if [ -n "${DB_URI:-}" ]; then
    exit 0
fi

# Marker present → already migrated or fresh 8.0 install, nothing to do
if [ -f "${MARKER_FILE}" ]; then
    exit 0
fi

# Marker absent + db directory exists → pre-8.0 data, needs archiving
if [ -d "${DB_DIR}" ]; then
    ARCHIVE_DIR="${DATADIR}/pre_migration_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${ARCHIVE_DIR}"
    log "MIGRATION: Old MongoDB data directory detected (no version marker present)."
    log "MIGRATION: Archiving all data → ${ARCHIVE_DIR}"

    # Move everything in DATADIR into the archive subfolder, skipping the
    # archive dir itself (it lives inside DATADIR)
    find "${DATADIR}" -maxdepth 1 -mindepth 1 ! -name "pre_migration_*" \
        -exec mv {} "${ARCHIVE_DIR}/" \;

    log "MIGRATION: Archive complete. UniFi will start fresh and show the setup wizard."

    # Find most recent autobackup in the archive and tell the user about it
    LATEST_BACKUP=$(ls -t "${ARCHIVE_DIR}/backup/autobackup/"*.unf 2>/dev/null | head -1 || true)
    if [ -n "${LATEST_BACKUP}" ]; then
        log "MIGRATION: *** ACTION REQUIRED ***"
        log "MIGRATION: Autobackup found: ${LATEST_BACKUP}"
        log "MIGRATION: After completing setup, restore via:"
        log "MIGRATION:   Settings → System → Backup → Restore"
    else
        log "MIGRATION: WARNING: No autobackup found."
        log "MIGRATION: You may need to reconfigure UniFi from scratch."
        log "MIGRATION: Your old files are preserved at: ${ARCHIVE_DIR}"
    fi
fi

# Write version marker so this only runs once
echo "8.0" > "${MARKER_FILE}"
