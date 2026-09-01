#!/usr/bin/env bash
# Load GCS into quakes_native.
#
# bq load is a batch load, not a query. Batch loads are always free. A CTAS
# from quakes_external would be a query and would bill for every GCS byte read.
# Same table at the end, but one costs money at scale and the other never does.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/env.sh"

if [[ -z "$NATIVE_TABLE" ]]; then
  echo "ex01 stack not applied. run: scripts/tf.sh ex01 apply" >&2
  exit 1
fi

# The partitioning flags are passed even though Terraform already set them, so
# --replace (WRITE_TRUNCATE) can never quietly drop the spec.
bq --location="$BQ_LOCATION" load \
  --source_format=NEWLINE_DELIMITED_JSON \
  --replace \
  --schema="$SCHEMA_PATH" \
  --time_partitioning_field=event_time \
  --time_partitioning_type=DAY \
  --clustering_fields=region \
  "${PROJECT_ID}:${DATASET_RAW}.quakes_native" \
  "gs://${BUCKET}/raw/quakes/*"

echo
bq --location="$BQ_LOCATION" query --use_legacy_sql=false \
  "SELECT
     COUNT(*)                    AS rows_loaded,
     COUNT(DISTINCT event_id)    AS distinct_events,
     COUNT(DISTINCT DATE(event_time)) AS day_partitions,
     MIN(event_time)             AS oldest,
     MAX(event_time)             AS newest
   FROM \`${NATIVE_TABLE}\`
   WHERE event_time > TIMESTAMP '1900-01-01'"

cat <<'EOF'

--------------------------------------------------------------------
A load with --replace may reset require_partition_filter. Check now:

    scripts/tf.sh ex01 plan     # expect: No changes

If it offers to put the flag back, that is the drift described at the
end of plan/05-bigquery-lessons.md. Write it up, then:

    scripts/tf.sh ex01 apply
--------------------------------------------------------------------
EOF
