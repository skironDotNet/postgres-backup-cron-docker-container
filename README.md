# PostgreSQL backup cron container

1. Adjust `PGHOST`, `PGUSER`, network name and backup host path in `docker-compose.yml`.
2. Put `PG_BACKUP_PASSWORD=your-password` in a local `.env` (never commit it).
3. Verify the image's PostgreSQL client major version is at least the server major version (change `FROM postgres:18-alpine` as appropriate).
4. `docker compose up -d --build`
5. Test immediately: `docker compose exec postgres-backup /job.sh`
6. Inspect results: `docker compose logs postgres-backup` and `ls -la /srv/backups/postgresql`.
7. Copy `.kopiaignore` to `/srv/backups/postgresql/.kopiaignore`, and make sure Kopia recognizes it as an ignore file at that snapshot root.

The backup script discovers all non-template connectable databases, makes one compressed custom-format dump per database, and dumps PostgreSQL global objects (roles / tablespaces). The script uses static .dump filenames, stages dumps as `.dump.tmp`, and publishes them only after all dumps succeed. It retains the latest successful dumps.

Kopia snapshots must run after dumps complete. Configure retention separately; The PostgreSQL superuser in this example is needed for comprehensive backup of global objects; protect its credentials and backup files.

### Configure Kopia's essential before-snapshot action to check both the in-progress and failed markers:
   
```
#!/bin/sh

BACKUP_DIR="/srv/backups/postgresql"

if [ -e "$BACKUP_DIR/.backup-in-progress" ] ||
   [ -e "$BACKUP_DIR/.backup-failed" ]; then
    echo "PostgreSQL backup incomplete or failed. Skipping snapshot." >&2
    exit 1
fi

exit 0
```

The script removes `.backup-failed` only after a fully successful backup. A container crash can leave a stale lock or marker, requiring manual inspection before the next run.

## backup user

For **PostgreSQL v14–18**, the simplest approach is to create a dedicated backup user and grant it the built-in `pg_read_all_data` role.

```
CREATE USER backup_job WITH PASSWORD 'your_strong_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

GRANT pg_read_all_data TO backup_job;
```                                

This allows the user to read all tables, views, and sequences across databases without granting write or administrative privileges.