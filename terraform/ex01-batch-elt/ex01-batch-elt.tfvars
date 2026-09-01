image_tag       = "v1"
ingest_schedule = "0 * * * *"

# Phase 4 step 6: flip this to true, then scripts/tf.sh ex01 apply.
# The plan should show ~ update in place on quakes_native, never -/+ recreate.
require_partition_filter = true
