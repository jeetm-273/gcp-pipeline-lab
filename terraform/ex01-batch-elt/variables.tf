# These four come from terraform/lab.tfvars, shared with foundation.

variable "project_id" {
  type        = string
  description = "Current lab project ID"
}

variable "region" {
  type    = string
  default = "us-west1"
}

variable "bq_location" {
  type    = string
  default = "US"
}

variable "impersonate_sa" {
  type    = string
  default = ""
}

# Declared only so lab.tfvars does not warn about an undeclared variable.
variable "lab_user_email" {
  type    = string
  default = ""
}

# These three come from ex01-batch-elt.tfvars, which is committed because
# none of them are secrets.

variable "image_tag" {
  type        = string
  description = "Bump when ingest.py changes, then rebuild and apply"
  default     = "v1"
}

variable "require_partition_filter" {
  type        = bool
  description = "Flip to true for the spec bullet 4 lesson, then apply again"
  default     = false
}

variable "ingest_schedule" {
  type        = string
  description = "Cron for the hourly ingest, UTC"
  default     = "0 * * * *"
}
