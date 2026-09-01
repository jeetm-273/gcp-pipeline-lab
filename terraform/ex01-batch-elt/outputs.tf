output "external_table" {
  value = "${var.project_id}.${local.fnd.dataset_raw}.quakes_external"
}

output "native_table" {
  value = "${var.project_id}.${local.fnd.dataset_raw}.quakes_native"
}

output "hourly_job" {
  value = google_cloud_run_v2_job.ingest["hourly"].name
}

output "backfill_job" {
  value = google_cloud_run_v2_job.ingest["backfill"].name
}

output "scheduler_job" {
  value = google_cloud_scheduler_job.hourly_ingest.name
}

output "image" {
  value = local.image
}

output "ingest_sa" {
  value = google_service_account.quake_ingest.email
}
