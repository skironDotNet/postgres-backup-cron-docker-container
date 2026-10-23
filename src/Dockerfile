# Use a client version at least as new as the PostgreSQL server major version.
FROM postgres:18-alpine

RUN apk add --no-cache tini tzdata

COPY job.sh /job.sh
RUN chmod 0755 /job.sh

ENV SCHEDULE_EXPR="0 2 * * *" \
    PGHOST=postgres \
    PGPORT=5432 \
    PGUSER=postgres \
    PGDATABASE=postgres \
    BACKUP_DIR=/backups \
    TZ=America/Chicago

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/bin/sh", "-c", "printf '%s /job.sh >> /proc/1/fd/1 2>&1\n' \"$SCHEDULE_EXPR\" > /etc/crontabs/root && exec crond -f -l 2"]
