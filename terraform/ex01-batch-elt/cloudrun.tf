locals {
  image = "${local.fnd.image_prefix}/quake-ingest:${var.image_tag}"

  ingest_jobs = {
    hourly   = "hour"
    backfill = "month"
  }
}

# Two jobs from one block, differing only in the MODE env var. The double
# template block is not a typo: the outer one is the execution template, the
# inner one is the task template.
resource "google_cloud_run_v2_job" "ingest" {
  for_each = local.ingest_jobs

  name                = "quake-${each.key}"
  location            = var.region
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.quake_ingest.email
      max_retries     = 1
      timeout         = "900s"

      containers {
        image = local.image

        env {
          name  = "BUCKET"
          value = local.fnd.bucket_name
        }

        env {
          name  = "MODE"
          value = each.value
        }
      }
    }
  }
}

# Only the hourly job is scheduled, so only it needs an invoker.
resource "google_cloud_run_v2_job_iam_member" "scheduler_invokes_hourly" {
  name     = google_cloud_run_v2_job.ingest["hourly"].name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.fnd.pipeline_runner_sa}"
}
