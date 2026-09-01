resource "google_service_account" "pipeline_runner" {
  account_id   = "pipeline-runner"
  display_name = "Drives terraform and the scheduler"
}

resource "google_service_account" "dataform_runner" {
  account_id   = "dataform-runner"
  display_name = "Dataform workflow execution"
}

# The lab asks for this one explicitly. Note it takes .name, not .email.
resource "google_service_account_iam_member" "you_impersonate_pipeline_runner" {
  service_account_id = google_service_account.pipeline_runner.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.lab_user_email}"
}

locals {
  pipeline_runner_roles = [
    "roles/artifactregistry.admin",
    "roles/bigquery.admin",
    "roles/cloudscheduler.admin",
    "roles/dataform.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
    "roles/run.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/storage.admin",
  ]
}

resource "google_project_iam_member" "pipeline_runner" {
  for_each = toset(local.pipeline_runner_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.pipeline_runner.email}"
}

# Forces the Dataform service agent account into existence. Building the
# email by hand only works if something already triggered its creation.
resource "google_project_service_identity" "dataform" {
  provider = google-beta
  service  = "dataform.googleapis.com"

  depends_on = [google_project_service.enabled]
}

# This is the binding that unblocked Dataform on a previous lab project.
resource "google_service_account_iam_member" "dataform_agent_impersonates_runner" {
  service_account_id = google_service_account.dataform_runner.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_project_service_identity.dataform.email}"
}

# The two serviceAccountUser bindings below are insurance. tokenCreator grants
# getAccessToken; serviceAccountUser grants actAs, which is a different
# permission that GCP checks when a resource is configured to run as an SA.
resource "google_service_account_iam_member" "dataform_agent_acts_as_runner" {
  service_account_id = google_service_account.dataform_runner.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_project_service_identity.dataform.email}"
}

# dataform_sync.sh runs as you, not as pipeline-runner. gcloud does not inherit
# Terraform's impersonation, so your own account needs actAs too.
resource "google_service_account_iam_member" "you_act_as_dataform_runner" {
  service_account_id = google_service_account.dataform_runner.name
  role               = "roles/iam.serviceAccountUser"
  member             = "user:${var.lab_user_email}"
}

resource "google_project_iam_member" "dataform_runner_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataform_runner.email}"
}
