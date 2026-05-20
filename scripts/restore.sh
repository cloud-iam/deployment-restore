#!/bin/bash -x
# Runs INSIDE the postgres container, in two contexts:
#   1. Auto, on first volume init — mounted at /docker-entrypoint-initdb.d/10-restore.sh.
#   2. Manually re-runnable — `docker compose exec postgres /scripts/restore.sh [<file>]`.
#
# Picks the newest *.bin in /backups (or uses the explicit path arg), drops
# every table in the public schema, runs pg_restore, then clears jgroupsping*.
# Expects a *decrypted* pg_dump -Fc backup.

set -euo pipefail

DB="${POSTGRES_DB:-keycloak}"
export PGUSER="${POSTGRES_USER:-postgres}"

backup="${1:-}"
if [[ -z "${backup}" ]]; then
  backup="$(ls -1t /backups/*.bin 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "${backup}" ]]; then
  echo "[restore] no *.bin in /backups — leaving DB empty"
  exit 0
fi
if [[ ! -f "${backup}" ]]; then
  echo "[restore] ERROR: file not found: ${backup}" >&2
  exit 1
fi

echo "[restore] selected: ${backup}"

# Drop everything in public. No-op on first init; needed on re-import.
for i in $(seq 1 10); do
  drops="$(psql -d "${DB}" -tAc "SELECT 'DROP TABLE \"'||tablename||'\" CASCADE;' FROM pg_catalog.pg_tables WHERE schemaname='public';")"
  [[ -z "${drops}" ]] && break
  echo "[restore] drop iteration ${i}: $(echo "${drops}" | wc -l) tables"
  echo "${drops}" | psql -d "${DB}" -q
done

echo "[restore] pg_restore..."
pg_restore -v -Fc -c --no-owner --no-acl --if-exists -d "${DB}" "${backup}"

echo "[restore] clearing jgroupsping* tables"
sql="$(psql -d "${DB}" -tAc "SELECT 'DELETE FROM \"'||tablename||'\";' FROM pg_catalog.pg_tables WHERE schemaname='public' AND tablename LIKE 'jgroupsping%';")"
if [[ -n "${sql}" ]]; then
  echo "${sql}" | psql -d "${DB}" -q
fi

echo "[restore] done."
