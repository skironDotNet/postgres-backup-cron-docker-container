#!/bin/sh
set -u

: "${PGHOST:=postgres}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGDATABASE:=postgres}"
: "${BACKUP_DIR:=/backups}"

mkdir -p "$BACKUP_DIR" || exit 1

lock="$BACKUP_DIR/.pg-backup.lock"
marker="$BACKUP_DIR/.backup-in-progress"
failed_marker="$BACKUP_DIR/.backup-failed"

# mkdir is atomic: reject overlapping jobs. A stale lock/marker after a crash
# must be investigated and removed manually before backups can resume.
if ! mkdir "$lock" 2>/dev/null; then
    echo 'ERROR: Backup already running or stale lock exists.' >&2
    exit 1
fi

# The marker spans discovery, dumping, and publishing. Kopia's essential
# pre-snapshot action should reject snapshots while this file exists.
if ! : > "$marker"; then
    rmdir "$lock" 2>/dev/null || true
    exit 1
fi

finished=0
cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ "$finished" -ne 1 ] || [ "$status" -ne 0 ]; then
        : > "$failed_marker"
    fi
    # A normal exit can safely clear this run's marker. A hard kill/crash
    # leaves it behind so Kopia cannot mistake stale dumps for fresh ones.
    rm -f "$marker"
    rmdir "$lock" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Mark the backup set invalid until every database and global object dump
# succeeds and all completed files have been published.
: > "$failed_marker" || exit 1

if ! databases=$(psql -X -A -t -w -v ON_ERROR_STOP=1 -c \
    'SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY datname'); then
    echo 'ERROR: Could not discover databases.' >&2
    exit 1
fi
[ -n "$databases" ] || { echo 'ERROR: No databases found.' >&2; exit 1; }

# Stage every dump first. No existing good dump is overwritten if a dump fails.
# Fixed filenames allow Kopia to manage historical versions.
while IFS= read -r db; do
    [ -n "$db" ] || continue
    label=$(printf '%s' "$db" | sed 's/[^[:alnum:]_.-]/_/g')
    temp="$BACKUP_DIR/db__${label}.dump.tmp"

    echo "Backing up database: $db"
    if ! pg_dump -w -Fc --dbname="$db" -f "$temp"; then
        echo "ERROR: pg_dump failed for: $db" >&2
        exit 1
    fi
done <<EOF_DATABASES
$databases
EOF_DATABASES

if ! pg_dumpall -w --globals-only -f "$BACKUP_DIR/globals.sql.tmp"; then
    echo 'ERROR: pg_dumpall --globals-only failed.' >&2
    exit 1
fi

# All dumps succeeded: publish the complete set. Renames are atomic per file,
# and the marker prevents Kopia from scanning during the publication window.
while IFS= read -r db; do
    [ -n "$db" ] || continue
    label=$(printf '%s' "$db" | sed 's/[^[:alnum:]_.-]/_/g')
    file="$BACKUP_DIR/db__${label}.dump"
    mv -f "$file.tmp" "$file" || exit 1
    echo "Completed: $file"
done <<EOF_DATABASES
$databases
EOF_DATABASES

mv -f "$BACKUP_DIR/globals.sql.tmp" "$BACKUP_DIR/globals.sql" || exit 1

rm -f "$failed_marker" || exit 1
finished=1
echo 'All PostgreSQL backups completed successfully.'
