#!/usr/bin/env bash
# Actual bytes processed and billed for recent queries.
#
# processed = what BigQuery read. Moves when pruning works.
# billed    = what you pay. Floored at 10 MB per table referenced per query,
#             so at this data size it will not move at all. That is the lesson.
#
# This query is also the seed of Exercise 05's final deliverable.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/env.sh"

HOURS="${1:-3}"
REGION_VIEW="region-$(printf '%s' "$BQ_LOCATION" | tr '[:upper:]' '[:lower:]')"

# If JOBS_BY_PROJECT is denied, swap to INFORMATION_SCHEMA.JOBS, which shows
# only your own jobs and needs fewer permissions.
bq --location="$BQ_LOCATION" query --use_legacy_sql=false "
SELECT
  FORMAT_TIMESTAMP('%H:%M:%S', creation_time)        AS query_time,
  SUBSTR(REGEXP_REPLACE(query, r'\\s+', ' '), 1, 68) AS q,
  total_bytes_processed                              AS processed,
  total_bytes_billed                                 AS billed,
  ROUND(total_bytes_billed / 1048576, 2)             AS mib_billed,
  TIMESTAMP_DIFF(end_time, start_time, MILLISECOND)  AS ms
FROM \`${REGION_VIEW}\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ${HOURS} HOUR)
  AND job_type = 'QUERY'
  AND statement_type != 'SCRIPT'
ORDER BY creation_time DESC
LIMIT 30"
