locals {
  datasets = {
    quakes              = "Raw layer. External and native tables over GCS"
    quakes_staging      = "Dataform staging. Deduped, one row per event"
    quakes_marts        = "Dataform marts"
    dataform_assertions = "Dataform assertion results"
  }
}

resource "google_bigquery_dataset" "layer" {
  for_each = local.datasets

  dataset_id  = each.key
  location    = var.bq_location
  description = each.value

  # Needed or destroy fails on a non-empty dataset.
  delete_contents_on_destroy = true
}

# Read on raw, write on the layers Dataform owns. Dataform cannot overwrite
# the raw tables.
resource "google_bigquery_dataset_iam_member" "dataform_reads_raw" {
  dataset_id = google_bigquery_dataset.layer["quakes"].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataform_runner.email}"
}

resource "google_bigquery_dataset_iam_member" "dataform_writes" {
  for_each = toset(["quakes_staging", "quakes_marts", "dataform_assertions"])

  dataset_id = google_bigquery_dataset.layer[each.key].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform_runner.email}"
}
