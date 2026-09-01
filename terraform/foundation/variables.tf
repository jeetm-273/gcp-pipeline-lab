variable "project_id" {
  type        = string
  description = "Current lab project ID"
}

variable "lab_user_email" {
  type        = string
  description = "Your Qwiklabs student account. Gets token creator on pipeline-runner"
}

variable "region" {
  type        = string
  description = "Cloud Run, GCS, Artifact Registry, Scheduler and Dataform region"
  default     = "us-west1"
}

variable "bq_location" {
  type        = string
  description = "BigQuery dataset location"
  default     = "US"
}

variable "impersonate_sa" {
  type        = string
  description = "Empty on the first apply, then the pipeline-runner email"
  default     = ""
}
