# Use a client version at least as new as the PostgreSQL server major version.
FROM alpine:3.23

RUN apk add --no-cache postgresql18-client tini tzdata \
    && psql --version \
    && pg_dump --version \
    && pg_dumpall --version \
    && pg_restore --version \
    && ! command -v postgres

COPY job.sh /job.sh
RUN chmod 0755 /job.sh

ENV SCHEDULE_EXPR="0 2 * * *" \
    PGHOST=pgsql \
    PGPORT=5432 \
    PGUSER=backup_job \
    PGDATABASE=postgres \
    BACKUP_DIR=/backups \
    TZ=America/Chicago

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/bin/sh", "-c", "printf '%s /job.sh >> /proc/1/fd/1 2>&1\n' \"$SCHEDULE_EXPR\" > /etc/crontabs/root && exec crond -f -l 2"]
