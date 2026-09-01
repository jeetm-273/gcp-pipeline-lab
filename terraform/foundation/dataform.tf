# The repository references the SA's email, so Terraform orders it after the
# account but not after the bindings. Setting a service account on a resource
# is itself an actAs check, so the bindings must land first or creation fails
# on a race that looks random.
resource "google_dataform_repository" "quakes" {
  provider = google-beta

  name            = "quakes-dataform"
  region          = var.region
  service_account = google_service_account.dataform_runner.email

  depends_on = [
    google_project_service.enabled,
    google_service_account_iam_member.dataform_agent_impersonates_runner,
    google_service_account_iam_member.dataform_agent_acts_as_runner,
    google_service_account_iam_member.you_act_as_dataform_runner,
  ]
}
