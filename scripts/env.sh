#!/usr/bin/env bash
# Source this, do not run it:
#
#   source scripts/env.sh
#
# Every value comes from a Terraform output. Nothing is hard coded, so a new
# lab project needs no edit here.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FND="$ROOT/terraform/foundation"
EX01="$ROOT/terraform/ex01-batch-elt"

tfout() { terraform -chdir="$1" output -raw "$2" 2>/dev/null; }

export PROJECT_ID
PROJECT_ID=$(tfout "$FND" project_id)

if [[ -z "$PROJECT_ID" ]]; then
  echo "foundation has no outputs yet." >&2
  echo "run: scripts/tf.sh foundation apply" >&2
  return 1 2>/dev/null || exit 1
fi

export PROJECT_NUMBER REGION BQ_LOCATION BUCKET IMAGE_PREFIX
PROJECT_NUMBER=$(tfout "$FND" project_number)
REGION=$(tfout "$FND" region)
BQ_LOCATION=$(tfout "$FND" bq_location)
BUCKET=$(tfout "$FND" bucket_name)
IMAGE_PREFIX=$(tfout "$FND" image_prefix)

export DATASET_RAW DATASET_STAGING DATASET_MARTS DATASET_ASSERTIONS
DATASET_RAW=$(tfout "$FND" dataset_raw)
DATASET_STAGING=$(tfout "$FND" dataset_staging)
DATASET_MARTS=$(tfout "$FND" dataset_marts)
DATASET_ASSERTIONS=$(tfout "$FND" dataset_assertions)

export DATAFORM_REPO DATAFORM_SA PIPELINE_RUNNER_SA
DATAFORM_REPO=$(tfout "$FND" dataform_repo)
DATAFORM_SA=$(tfout "$FND" dataform_sa)
PIPELINE_RUNNER_SA=$(tfout "$FND" pipeline_runner_sa)

# ex01 has not been applied during the build.sh step, so these can be empty.
export EXTERNAL_TABLE NATIVE_TABLE HOURLY_JOB BACKFILL_JOB SCHEDULER_JOB
EXTERNAL_TABLE=$(tfout "$EX01" external_table)
NATIVE_TABLE=$(tfout "$EX01" native_table)
HOURLY_JOB=$(tfout "$EX01" hourly_job)
BACKFILL_JOB=$(tfout "$EX01" backfill_job)
SCHEDULER_JOB=$(tfout "$EX01" scheduler_job)

export SCHEMA_PATH="$EX01/schemas/quakes.json"
export DATAFORM_DIR="$ROOT/dataform"
export REPO_ROOT="$ROOT"

gcloud config set project "$PROJECT_ID" --quiet 2>/dev/null
gcloud config set run/region "$REGION" --quiet 2>/dev/null

printf 'project  %s\nregion   %s\nbq loc   %s\nbucket   %s\n' \
  "$PROJECT_ID" "$REGION" "$BQ_LOCATION" "$BUCKET"

# Must be an if, not `[[ ... ]] && echo`. The && form returns exit 1 when the
# test is false, which kills any caller running under `set -e`.
if [[ -z "$NATIVE_TABLE" ]]; then
  echo "note: ex01 stack not applied yet"
fi
