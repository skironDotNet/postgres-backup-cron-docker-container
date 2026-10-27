# PostgreSQL backup cron container

1. Adjust `PGHOST`, `PGUSER`, network name and backup host path in `docker-compose.yml`.
2. Put `BACKUP_USER_PASSWORD=your-password` in a local `.env` (never commit it).
3. Verify the image's PostgreSQL client major version is at least the server major version. The Dockerfile uses `alpine:3.23` with `postgresql18-client`; adjust the client package and Alpine release together if a different major version is needed.
4. `docker compose up -d --build`
5. Test immediately: `docker compose exec postgres-backup /job.sh`
6. Inspect results: `docker compose logs postgres-backup` and `ls -la /srv/backups/postgresql`.
7. Copy `.kopiaignore` to `/srv/backups/postgresql/.kopiaignore`, and make sure Kopia recognizes it as an ignore file at that snapshot root.

The backup script discovers all non-template connectable databases, makes one compressed custom-format dump per database, and dumps PostgreSQL global objects (roles / tablespaces). The script uses static `db__<sanitized-database-name>.dump` filenames, stages dumps as `db__<sanitized-database-name>.dump.tmp`, and publishes them only after all dumps succeed. It retains the latest successful dumps. Global objects are staged as `globals.sql.tmp` and published as `globals.sql`.

## Configuration

The image installs only PostgreSQL 18 client tools and their dependencies,
plus `tini` and timezone data. Alpine's built-in BusyBox supplies the shell and
cron daemon. No PostgreSQL server package is installed. The build checks that
`psql`, `pg_dump`, `pg_dumpall`, and `pg_restore` run and that the `postgres`
server command is absent.

Rebuild, inspect the image size in bytes, and recreate the container:

```sh
./build.sh
docker image inspect postgres-backup-cron --format '{{.Size}}'
docker compose up -d --force-recreate
```

| Variable | Script default | Compose setting |
| --- | --- | --- |
| `PGHOST` | `postgres` | `pgsql` |
| `PGPORT` | `5432` | `5432` |
| `PGUSER` | `postgres` | `backup_job` |
| `PGDATABASE` | `postgres` | `postgres` |
| `BACKUP_DIR` | `/backups` | `/backups`, mounted from `/srv/backups/postgresql` |
| `PGPASSWORD` | Unset; PostgreSQL client password environment variable | From `BACKUP_USER_PASSWORD` in `.env` |

`PGDATABASE` selects the initial connection database for discovery; each dump
targets its discovered database name. `BACKUP_USER_PASSWORD` is a Compose input,
not a variable read by `job.sh`. Compose sets `SCHEDULE_EXPR` to `0 2 * * *`
and `TZ` to `America/Chicago` for daily backups at 02:00.

## Dump filenames and restore

Database names are sanitized by replacing characters other than letters, numbers,
`_`, `.`, and `-` with `_`. For example, `sales europe` produces
`db__sales_europe.dump` inside `BACKUP_DIR`.

Existing files using the old hash suffix are not renamed or deleted automatically.
After verifying a successful backup with the new names, remove obsolete hashed
files from the backup directory if they are no longer needed.

Restore global objects first when needed, then restore the database into an
existing empty database. Use a suitably privileged restore account and adjust
paths and connection settings for your environment:

```sh
psql --host=pgsql --username=postgres --dbname=postgres --set=ON_ERROR_STOP=1 --file=/srv/backups/postgresql/globals.sql
createdb --host=pgsql --username=postgres 'sales europe'
pg_restore --host=pgsql --username=postgres --dbname='sales europe' --exit-on-error /srv/backups/postgresql/db__sales_europe.dump
```

The filename is sanitized; the restore target uses the original database name.

## Kopia

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
