resource "google_service_account" "quake_ingest" {
  account_id   = "quake-ingest"
  display_name = "Cloud Run ingestion job runtime"
}

# Foundation owns the bucket, this stack owns an identity and grants it access.
# Ex03 will do the same thing for its Dataflow SA, in its own stack, without
# either exercise editing the other.
resource "google_storage_bucket_iam_member" "ingest_writes" {
  bucket = local.fnd.bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.quake_ingest.email}"
}
