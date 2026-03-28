#!/usr/bin/env bash
# Embedded MongoDB migration helper.
# Runs at container start via: run-parts /usr/unifi/init.d/
#
# Applies ONLY to standalone containers using embedded MongoDB.
# Skipped automatically when DB_URI is set (external MongoDB users
# should use backup.sh + restore.sh instead).
#
# On first launch after upgrading from a pre-8.0 image:
#   - Reads the WiredTiger version from db/WiredTiger to identify the source
#   - Archives the entire data directory so UniFi starts with a clean slate
#   - Logs the most recent autobackup .unf path so you know what to restore

. /usr/unifi/functions

MARKER_FILE="${DATADIR}/.mongo_version_marker"
DB_DIR="${DATADIR}/db"
WT_META="${DB_DIR}/WiredTiger"

# Skip if using external MongoDB (docker-compose path)
if [ -n "${DB_URI:-}" ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Read WiredTiger version from data files (if present).
# MongoDB 3.6 shipped with WiredTiger 3.x; 4.2+ jumped to 10.x+.
# A major version < 10 reliably identifies pre-4.2 (almost always 3.6) data.
# ---------------------------------------------------------------------------
wt_version=""
wt_major=0
if [ -f "${WT_META}" ]; then
    wt_version=$(awk '/^WiredTiger [0-9]/{print $2; exit}' "${WT_META}")
    wt_major=$(echo "${wt_version}" | cut -d. -f1)
fi

# ---------------------------------------------------------------------------
# Marker-present path: migration already ran (or fresh 8.0 install).
# Cross-check the WiredTiger version so we can warn if something looks wrong.
# ---------------------------------------------------------------------------
if [ -f "${MARKER_FILE}" ]; then
    recorded=$(cat "${MARKER_FILE}")
    # If the marker says 8.0 but WiredTiger looks ancient, warn and skip —
    # better to be cautious than to silently re-archive a good database.
    if [ -n "${wt_version}" ] && [ "${wt_major}" -lt 10 ] 2>/dev/null; then
        log "MIGRATION: WARNING: Marker present (${recorded}) but WiredTiger ${wt_version} looks pre-4.2."
        log "MIGRATION: If data was not restored yet, remove ${MARKER_FILE} and restart."
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# No marker. Decide whether migration is needed.
# ---------------------------------------------------------------------------
needs_migration=false

if [ -d "${DB_DIR}" ]; then
    if [ -f "${WT_META}" ]; then
        # We can read the actual WiredTiger version — use it as the primary signal.
        if [ "${wt_major}" -lt 10 ] 2>/dev/null; then
            log "MIGRATION: Detected WiredTiger ${wt_version} (MongoDB ~3.6 era) — migration required."
            needs_migration=true
        else
            # WiredTiger 10+ — data could be from MongoDB 4.2–7.x.
            # Still incompatible with 8.0 without a proper upgrade path, so migrate.
            log "MIGRATION: Detected WiredTiger ${wt_version} — data predates MongoDB 8.0 marker, migrating."
            needs_migration=true
        fi
    else
        # db/ exists but no WiredTiger file — unusual, but archive to be safe.
        log "MIGRATION: db/ present but WiredTiger metadata not found — archiving as precaution."
        needs_migration=true
    fi
fi

if [ "${needs_migration}" = true ]; then
    ARCHIVE_DIR="${DATADIR}/pre_migration_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${ARCHIVE_DIR}"
    log "MIGRATION: Source WiredTiger version: ${wt_version:-unknown}"
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

# Write version marker — record detected source WiredTiger version for auditing
{
    echo "target=8.0"
    echo "source_wiredtiger=${wt_version:-unknown}"
    echo "migrated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MARKER_FILE}"
