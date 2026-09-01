# project is set explicitly on both tables because dataset_id arrives as a
# plain string from the remote state, not as a resource reference, so the
# provider cannot infer the project from it.

resource "google_bigquery_table" "quakes_external" {
  project             = var.project_id
  dataset_id          = local.fnd.dataset_raw
  table_id            = "quakes_external"
  deletion_protection = false

  external_data_configuration {
    autodetect    = false
    source_format = "NEWLINE_DELIMITED_JSON"
    source_uris   = ["gs://${local.fnd.bucket_name}/raw/quakes/*"]
    schema        = file("${path.module}/schemas/quakes.json")

    # CUSTOM declares the types instead of guessing them. If BigQuery rejects
    # a pinned schema alongside hive partitioning, set autodetect = true and
    # drop the schema line on this table only. See question R1 in plan/README.
    hive_partitioning_options {
      mode                     = "CUSTOM"
      source_uri_prefix        = "gs://${local.fnd.bucket_name}/raw/quakes/{dt:DATE}/{hh:INTEGER}"
      require_partition_filter = false
    }
  }
}

# Created empty. scripts/load_native.sh fills it with bq load, which is a
# batch load and therefore free. A CTAS from the external table would be a
# query and would bill for every GCS byte read.
resource "google_bigquery_table" "quakes_native" {
  project                  = var.project_id
  dataset_id               = local.fnd.dataset_raw
  table_id                 = "quakes_native"
  deletion_protection      = false
  schema                   = file("${path.module}/schemas/quakes.json")
  require_partition_filter = var.require_partition_filter
  clustering               = ["region"]

  time_partitioning {
    type  = "DAY"
    field = "event_time"
  }
}
