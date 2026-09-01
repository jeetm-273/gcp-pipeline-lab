provider "google" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = var.impersonate_sa != "" ? var.impersonate_sa : null
}

provider "google-beta" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = var.impersonate_sa != "" ? var.impersonate_sa : null
}
