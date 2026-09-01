data "google_project" "current" {}

locals {
  apis = [
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com",
    "dataform.googleapis.com",
    "iamcredentials.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
  ]
}

# disable_on_destroy stays false so a destroy does not turn BigQuery off
# for the whole project.
resource "google_project_service" "enabled" {
  for_each = toset(local.apis)

  service            = each.value
  disable_on_destroy = false
}
