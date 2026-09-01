# This file is foundation's public interface. Anything not here is invisible
# to the ex01 stack and to the shell scripts.

output "project_id" {
  value = var.project_id
}

output "project_number" {
  value = data.google_project.current.number
}

output "region" {
  value = var.region
}

output "bq_location" {
  value = var.bq_location
}

output "bucket_name" {
  value = google_storage_bucket.raw.name
}

output "registry_repo" {
  value = google_artifact_registry_repository.images.repository_id
}

# One place holding the registry URL format, so build.sh and ex01 cannot
# disagree about it.
output "image_prefix" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "dataset_raw" {
  value = google_bigquery_dataset.layer["quakes"].dataset_id
}

output "dataset_staging" {
  value = google_bigquery_dataset.layer["quakes_staging"].dataset_id
}

output "dataset_marts" {
  value = google_bigquery_dataset.layer["quakes_marts"].dataset_id
}

output "dataset_assertions" {
  value = google_bigquery_dataset.layer["dataform_assertions"].dataset_id
}

output "dataform_repo" {
  value = google_dataform_repository.quakes.name
}

output "dataform_sa" {
  value = google_service_account.dataform_runner.email
}

output "pipeline_runner_sa" {
  value = google_service_account.pipeline_runner.email
}
