resource "google_storage_bucket" "raw" {
  name                        = "${var.project_id}-quakes"
  location                    = var.region
  uniform_bucket_level_access = true

  # Correct for a throwaway lab, wrong for production.
  force_destroy = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# External tables are read with the querying identity's GCS permissions, not
# the table's, so Dataform needs this if a model ever reads quakes_external.
resource "google_storage_bucket_iam_member" "dataform_reads" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.dataform_runner.email}"
}
