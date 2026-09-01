# Cloud Scheduler cannot run a Cloud Run job natively. It makes an
# authenticated POST to the Cloud Run Admin API, which starts the job. Hence
# an http_target with an oauth_token, and hence pipeline-runner needing
# run.invoker in cloudrun.tf.
#
# time_zone is UTC because the partition paths are UTC. A local timezone would
# drift against them twice a year.
resource "google_cloud_scheduler_job" "hourly_ingest" {
  name      = "quake-hourly-ingest"
  region    = var.region
  schedule  = var.ingest_schedule
  time_zone = "Etc/UTC"

  retry_config {
    retry_count = 2
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.ingest["hourly"].name}:run"

    oauth_token {
      service_account_email = local.fnd.pipeline_runner_sa
    }
  }
}
