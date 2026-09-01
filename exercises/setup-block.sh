#!/bin/bash

# ============================================================
# GCP DATA ENGINEERING ROADMAP
# Day 1 — Setup / Environment Initialization
# ============================================================
#
# PURPOSE
# -------
# This file is our reusable environment setup/checkpoint.
#
# We are using temporary Qwiklabs projects, so PROJECT_ID,
# bucket names, service accounts, and allowed regions may
# change between lab sessions.
#
# Run this file at the beginning of a new Qwiklabs session.
#
# Exercise-specific files and commands should stay inside
# their respective exercise folders.
#
# ============================================================


# ------------------------------------------------------------
# 1. ENVIRONMENT VARIABLES
# ------------------------------------------------------------

# export PROJECT_ID="$(gcloud config get-value project)"
echo PROJECT_ID="XXXXX"

# Qwiklabs projects may enforce different resource-location
# policies.
#
# IMPORTANT:
# Do NOT assume us-central1.
#
# The current project accepted us-west1 for Cloud Run and
# Cloud Storage.
#
# If a new Qwiklabs project rejects this region, inspect:
#
#   gcloud org-policies describe constraints/gcp.resourceLocations \
#     --project="$PROJECT_ID"
#
# and choose an allowed region.
#
export REGION="us-west1"
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" \
  --format="value(projectNumber)")

export DATAFORM_REGION="us-west1"
export DATAFORM_REPO="quakes-dataform"
export DATAFORM_WORKSPACE="dev"

export SA="pipeline-runner"
export SA_EMAIL="$SA@$PROJECT_ID.iam.gserviceaccount.com"

# Exercise 01 bucket
export BUCKET="${PROJECT_ID}-quakes"


echo "========================================"
echo "GCP Data Engineering Environment"
echo "========================================"
echo "PROJECT_ID : $PROJECT_ID"
echo "REGION     : $REGION"
echo "SA         : $SA"
echo "SA_EMAIL   : $SA_EMAIL"
echo "BUCKET     : $BUCKET"
echo "========================================"


# ------------------------------------------------------------
# 2. AUTHENTICATION CHECK
# ------------------------------------------------------------
#
# Confirm which Qwiklabs student account is active.
#

gcloud auth list


# ------------------------------------------------------------
# 3. PROJECT CHECK
# ------------------------------------------------------------

gcloud config get-value project
gcloud config set project PROJECT_ID

# ------------------------------------------------------------
# 4. CLOUD RUN REGION
# ------------------------------------------------------------
#
# Cloud Run jobs/services will use this region by default.
#

gcloud config set run/region "$REGION"


# ------------------------------------------------------------
# 5. REQUIRED GOOGLE CLOUD APIS
# ------------------------------------------------------------
#
# Roadmap uses:
#
# - BigQuery
# - Cloud Run
# - Cloud Storage
# - Dataform
# - Pub/Sub
# - Dataflow
# - Workflows
# - Dataplex
# - Artifact Registry
#
# Qwiklabs may already have some/all APIs enabled.
#
# We VERIFY instead of blindly enabling everything.
#

gcloud services list --enabled | grep -E \
'bigquery|run|storage|dataform|pubsub|dataflow|workflows|dataplex|artifactregistry'


# ------------------------------------------------------------
# 6. SERVICE ACCOUNT
# ------------------------------------------------------------
#
# Roadmap service account:
#
#   pipeline-runner
#
# Some Qwiklabs projects provide it.
# Some may not.
#
# Check before trying to create or modify it.
#

gcloud iam service-accounts list


# ------------------------------------------------------------
# 7. SERVICE ACCOUNT IMPERSONATION
# ------------------------------------------------------------
#
# Production/sandbox architecture will use:
#
#   roles/iam.serviceAccountTokenCreator
#
# and commands such as:
#
#   --impersonate-service-account="$SA_EMAIL"
#
# However, Qwiklabs student accounts may not have permission
# to grant themselves this role.
#
# Therefore this is NOT automatically configured here.
#
# Previously tested:
#
#   gcloud auth print-access-token \
#     --impersonate-service-account="$SA_EMAIL"
#
# Qwiklabs result:
#
#   PERMISSION_DENIED
#
# We will complete this later in a GCP environment where we
# control IAM permissions.
#


# ------------------------------------------------------------
# 8. CLOUD STORAGE
# ------------------------------------------------------------
#
# Verify existing buckets.
#

gcloud storage buckets list


# ------------------------------------------------------------
# 9. EXERCISE 01 BUCKET
# ------------------------------------------------------------
#
# Exercise 01 requires:
#
#   USGS
#     ↓
#   Cloud Run Job
#     ↓
#   Cloud Storage
#     ↓
#   BigQuery
#     ↓
#   Dataform
#
# We use one dedicated bucket:
#
#   ${PROJECT_ID}-quakes
#
# If it already exists, do nothing.
#
# If it doesn't exist, create it using REGION.
#

if gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then

    echo "Bucket already exists:"
    echo "  gs://$BUCKET"

else

    echo "Creating bucket:"
    echo "  gs://$BUCKET"

    gcloud storage buckets create "gs://$BUCKET" \
        --location="$REGION"

fi


# ------------------------------------------------------------
# 10. EXERCISE 01 CHECKPOINT
# ------------------------------------------------------------
#
# COMPLETED SO FAR
# ----------------
#
# [x] USGS public earthquake feed tested
#
# [x] Understand USGS GeoJSON structure
#
# [x] ingest.py created
#
# [x] ingest.py converts USGS GeoJSON → NDJSON
#
# [x] Cloud Run Job created:
#
#       quake-ingestion
#
# [x] Cloud Run Job successfully executed
#
# [x] Data written to:
#
#       gs://$BUCKET/raw/quakes/
#         dt=YYYY-MM-DD/
#           hh=HH/
#             quakes.ndjson
#
# [x] BigQuery dataset created:
#
#       $PROJECT_ID:quakes
#
# [x] BigQuery external table created:
#
#       quakes.quakes_external
#
# [x] Hive partitioning verified
#
# [x] External table queried successfully
#
#
# NEXT
# ----
#
# [ ] Create native BigQuery table
# [ ] Partition native table by event date
# [ ] Cluster native table by region
# [ ] Compare external vs native query bytes
# [ ] Enable require_partition_filter
# [ ] Test unfiltered query failure
# [ ] Dataform staging model
# [ ] Dataform daily seismic summary
# [ ] Dataform assertions
#
#
# Exercise-specific implementation lives in:
#
#   ./ex01-ingestion/
#
# Expected files:
#
#   ingest.py
#   Dockerfile
#   external_table.json
#
# Do NOT move these into setup.sh.
#


# ------------------------------------------------------------
# 11. IMPORTANT QWIKLABS NOTES
# ------------------------------------------------------------
#
# Qwiklabs projects are temporary.
#
# On a new project:
#
#   PROJECT_ID changes
#   BUCKET changes
#   service accounts may change
#   allowed regions may change
#
# Therefore:
#
#   source this file again:
#
#       source ./setup.sh
#
# or:
#
#       ./setup.sh
#
# depending on how the shell variables are being used.
#
# NEVER hard-code a previous Qwiklabs PROJECT_ID or bucket.
#
# ============================================================


# ------------------------------------------------------------
# 12. CURRENT STATUS
# ------------------------------------------------------------

echo
echo "========================================"
echo "SETUP CHECKPOINT"
echo "========================================"
echo "[x] Project"
echo "[x] Authentication"
echo "[x] Cloud Run region"
echo "[x] APIs verified"
echo "[x] Service account checked"
echo "[x] Storage checked"
echo "[x] Exercise 01 bucket checked"
echo
echo "Exercise 01 progress:"
echo "[x] USGS ingestion"
echo "[x] Cloud Run Job"
echo "[x] GCS raw layer"
echo "[x] BigQuery dataset"
echo "[x] External table"
echo "[x] Hive partitioning"
echo
echo "[NEXT] Native BigQuery table"
echo "========================================"