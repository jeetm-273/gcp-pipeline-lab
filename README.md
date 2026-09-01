# GCP Pipeline Lab

Five exercises that build one pipeline, each adding a single new idea. Public
keyless data throughout. Runs on throwaway Qwiklabs projects, so the repo is the
only durable artifact and everything is rebuildable from it.

| # | Title | Cost | Status |
|---|---|---|---|
| 01 | Batch ELT with no processing engine | Free | **12 of 13 done.** Only unattended scheduler evidence left. See `notes/ex01-results.md` |
| 02 | A real webhook into BigQuery, with no pipeline | Free | not started |
| 03 | Real streaming, and the Beam model | Metered | not started |
| 04 | Orchestration, twice, then pick one | Metered | not started |
| 05 | Quality, access, and watching your own spend | Free | not started |

Exercise 03 bills per worker-second until drained. Exercise 04 has a monthly
floor for an idle Composer environment. Each gets its own Terraform stack so it
can be destroyed on its own.

---

# Layout

```
terraform/
  lab.tfvars            gitignored. the ONLY place the project ID lives
  lab.tfvars.example    copy this each lab
  foundation/           APIs, service accounts, bucket, 4 datasets,
                        artifact registry, dataform repo. Apply first
  ex01-batch-elt/       external + native tables, 2 Cloud Run jobs,
                        scheduler. Own state, destroy independently
apps/quake-ingest/      container source for the ingest job
dataform/               one Dataform project, shared by all exercises
scripts/                see the table below
notes/ex01-results.md   Exercise 01 evidence. One file per exercise
secrets/                gitignored except README and examples
plan/                   local only, not committed. Detailed notes per exercise
```

## What each script does

| Script | What it does | When you run it |
|---|---|---|
| `scripts/tf.sh` | Terraform wrapper. Adds the var files for you | Instead of raw `terraform` |
| `scripts/env.sh` | Loads project, region, bucket, table names into your shell from Terraform outputs | `source` it after each apply |
| `scripts/build.sh` | Builds and pushes the ingest container | After foundation, before ex01 |
| `scripts/load_native.sh` | `bq load` from GCS into `quakes_native`. Free, it is a batch load | After any ingest run |
| **`scripts/bytes_report.sh`** | **Reads INFORMATION_SCHEMA for bytes processed and billed per query. This is the file to run for the bytes comparison** | After running the Q1 to Q7 set |
| `scripts/dataform_sync.sh` | Uploads `dataform/`, compiles, runs, prints per action state | After any SQLX edit |

---

# Exercise 01, step by step

Two parts. **Part A rebuilds the infrastructure** and takes about 25 minutes.
**Part B is the actual exercise** and takes about 55 minutes. Part A is proven;
Part B is what completes the task.

## Part A: rebuild on a new lab

### A0. Commit first

```bash
git status --short
```

Should print nothing. If it does not, commit before continuing.

### A1. New lab credentials

```bash
cp secrets/lab-credentials.md.example secrets/lab-credentials.md
```

Fill in username, password, project ID, expiry. Nothing reads this file, it is
your note. It never reaches GitHub.

### A2. Log in, twice

```bash
gcloud auth login
gcloud auth application-default login
```

Pick the **student account** both times. The first is for `gcloud` and `bq`. The
second is for Terraform. Skipping the second gives a confusing credentials error
later.

```bash
gcloud auth list --filter=status:ACTIVE --format='value(account)'
```

Expect `student-XX-xxxxxxxx@qwiklabs.net`.

### A3. Clear the dead lab's files

```bash
rm -f terraform/foundation/terraform.tfstate*
rm -f terraform/ex01-batch-elt/terraform.tfstate*
rm -f terraform/lab.tfvars
rm -f dataform/workflow_settings.yaml
```

Do **not** delete `.terraform.lock.hcl` or `ex01-batch-elt.tfvars`. Both carry
over on purpose.

### A4. One file to edit

```bash
cp terraform/lab.tfvars.example terraform/lab.tfvars
```

Set `project_id` and `lab_user_email`. Leave `impersonate_sa = ""`.

Confirm `require_partition_filter = false` in
`terraform/ex01-batch-elt/ex01-batch-elt.tfvars`. Part B needs to measure without
it first.

```bash
gcloud config set project YOUR_NEW_PROJECT_ID
```

### A5. Build

```bash
scripts/tf.sh foundation init
scripts/tf.sh foundation apply
```

Expect `Apply complete! Resources: 38 added`. If it errors saying an API is not
enabled, run apply again. Google takes a minute to switch APIs on and Terraform
does not wait.

```bash
source scripts/env.sh
```

Prints project, region, bq loc, bucket, then `note: ex01 stack not applied yet`.
That note is correct at this point.

```bash
./scripts/build.sh
```

Expect `SUCCESS` and `pushed .../quake-ingest:v1`. About 35 seconds.

```bash
scripts/tf.sh ex01 init
scripts/tf.sh ex01 apply
```

Expect `Apply complete! Resources: 8 added`.

```bash
source scripts/env.sh
```

Run again. The `not applied yet` note should be gone.

### A6. Impersonation

Edit `terraform/lab.tfvars`:

```hcl
impersonate_sa = "pipeline-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com"
```

**Wait about 4 minutes before testing.** The binding applies instantly but IAM
propagation lags. The first attempt returns `PERMISSION_DENIED` even though the
binding is present and correct. This is not a lab restriction.

```bash
gcloud auth print-access-token \
  --impersonate-service-account="pipeline-runner@${PROJECT_ID}.iam.gserviceaccount.com" \
  >/dev/null && echo "it works"

scripts/tf.sh foundation plan
scripts/tf.sh ex01 plan
```

Both plans should say `No changes`. If still denied after 10 minutes, set
`impersonate_sa = ""` back, note it in `notes/ex01-results.md`, and move on.

### A7. Data in

```bash
gcloud run jobs execute quake-backfill --region "$REGION" --wait
```

Two to three minutes.

```bash
gcloud storage ls "gs://$BUCKET/raw/quakes/" | wc -l                 # expect ~31
gcloud storage ls --recursive "gs://$BUCKET/raw/quakes/**" | wc -l   # expect ~720
```

Prove the scheduler chain:

```bash
gcloud scheduler jobs run quake-hourly-ingest --location "$REGION"
gcloud run jobs executions list --job quake-hourly --region "$REGION" --limit 3
```

Expect an execution with `RUN BY pipeline-runner@...`

```bash
./scripts/load_native.sh
```

Expect about 10,900 rows across 31 day partitions.

### A8. Dataform first run

```bash
./scripts/dataform_sync.sh
```

Expect `compilation clean`, then 6 actions all SUCCEEDED.

**Note:** Terraform creates the Dataform *repository*. The `dev` *workspace* is
created by this script, because `google_dataform_repository_workspace` does not
exist in the Terraform provider. So an empty repo with no workspace before you
run this is normal, not a bug.

---

## Part B: the exercise itself

This is what completes the task. Record everything in `notes/ex01-results.md`.

### B1. Pick your busiest date

```bash
bq --location="$BQ_LOCATION" query --use_legacy_sql=false \
  "SELECT dt, COUNT(*) n FROM \`$EXTERNAL_TABLE\` GROUP BY dt ORDER BY n DESC LIMIT 5"
```

Call the winner `PICK_DATE` below.

### B2. Write your predictions BEFORE running anything

Open `notes/ex01-results.md` and fill the Predicted column. This is the whole point of
the "Done when" line. Rules of thumb:

```
native, no filter        = whole table, about 1.4 MB
native, one day          = table / 31, about 46 KB   <- 31, not 720
native, + region filter  = NO CHANGE. one day is a single block
native, fewer columns    = proportional to just those columns
external, dt filter      = the ~24 files under that dt
external, no filter      = every file the glob matches, about 4 MB of NDJSON
```

And the billing rule:

```
bytes billed = max(10 MB per table referenced, bytes actually scanned)
```

Since the table is under 10 MB, **billed will read 10 MB for every native query
no matter how well you prune.** Processed is the number that moves. Knowing that
is what "predict the bytes billed" means.

### B3. Run the query set

Replace `PROJECT` and `PICK_DATE`. Dry run first with `--dry_run` to get the
estimate, then run for real.

**Q1, external, no filter**
```sql
SELECT region, COUNT(*) AS n, AVG(magnitude) AS avg_mag
FROM `PROJECT.quakes.quakes_external`
GROUP BY region ORDER BY n DESC
```

**Q2, external, partition filter**
```sql
SELECT region, COUNT(*) AS n, AVG(magnitude) AS avg_mag
FROM `PROJECT.quakes.quakes_external`
WHERE dt = DATE 'PICK_DATE'
GROUP BY region ORDER BY n DESC
```

**Q3, native, no filter**
```sql
SELECT region, COUNT(*) AS n, AVG(magnitude) AS avg_mag
FROM `PROJECT.quakes.quakes_native`
GROUP BY region ORDER BY n DESC
```

**Q4, native, partition filter**
```sql
SELECT region, COUNT(*) AS n, AVG(magnitude) AS avg_mag
FROM `PROJECT.quakes.quakes_native`
WHERE event_time >= TIMESTAMP 'PICK_DATE 00:00:00 UTC'
  AND event_time <  TIMESTAMP_ADD(TIMESTAMP 'PICK_DATE 00:00:00 UTC', INTERVAL 1 DAY)
GROUP BY region ORDER BY n DESC
```

**Q5, native, partition plus cluster filter.** Q4 plus `AND region = 'ak'`.
Predict no change.

**Q6, native, column pruning.** Q4 again but `SELECT *` with no aggregation,
compared against Q4.

**Q7, external, column pruning**
```sql
SELECT magnitude, region
FROM `PROJECT.quakes.quakes_external`
WHERE dt = DATE 'PICK_DATE'
```

Dry run syntax:

```bash
bq --location="$BQ_LOCATION" query --use_legacy_sql=false --dry_run "PASTE_SQL_HERE"
```

Note: dry run on the **native** table gives an accurate byte count. Dry run on
the **external** table cannot, because BigQuery has not opened the GCS files yet.
Expect 0 or a useless number there, and write down what you actually see. That
asymmetry is itself part of the lesson.

### B4. Read the real numbers

```bash
./scripts/bytes_report.sh
```

**This is the file for the bytes review.** It queries
`INFORMATION_SCHEMA.JOBS_BY_PROJECT` and prints, per query, the bytes processed,
the bytes billed, the MiB billed and the duration. Fill those into the table in
`notes/ex01-results.md`.

Optional argument is a lookback in hours, default 3:

```bash
./scripts/bytes_report.sh 6
```

### B5. Write the conclusion

Four things in `notes/ex01-results.md`:

- Which pruning reduced processed bytes, and by roughly what ratio
- Why billed did not move
- At what data size billed would start tracking processed
- Whether you would keep the external table here, and why

The strongest argument for the last one: `quakes_native` is about **1.4 MB** in
BigQuery while the same data as NDJSON in GCS is about **4 MB**. Columnar
encoding plus compression makes native 2.8x smaller, so even an unfiltered native
scan reads a third of what the external table must, before any pruning. Then Q6
against Q7 shows native can skip columns and NDJSON cannot.

### B6. require_partition_filter

Edit `terraform/ex01-batch-elt/ex01-batch-elt.tfvars`:

```hcl
require_partition_filter = true
```

```bash
scripts/tf.sh ex01 plan
```

Confirm it says `~ update in-place` on `quakes_native`. If it says
`-/+ destroy and recreate`, stop and read why, that would delete your data.

```bash
scripts/tf.sh ex01 apply
```

Now run Q3 again. It fails. Paste the verbatim error into `notes/ex01-results.md`. It
looks like:

```
Cannot query over table 'PROJECT.quakes.quakes_native' without a filter over
column(s) 'event_time' that can be used for partition elimination
```

Check the boundary:

| Action | Expected |
|---|---|
| Q3, no filter | fails |
| Q4, one day filter | works |
| `./scripts/load_native.sh` | works. Loads are not queries |
| `SELECT COUNT(*)` no filter | fails. Even a count must name a partition |

### B7. Break test A, compilation

Break the **reference**, not a column name. In
`dataform/definitions/staging/stg_quakes.sqlx` change
`${ref("quakes_native")}` to `${ref("quakes_nativeee")}`.

Why not a column name: Dataform translates SQLX to SQL without validating columns
against BigQuery, so a bad column compiles fine and fails later at execution.
The dependency graph is the thing compilation can actually check. Take a backup
first, since restoring matters:

```bash
cp dataform/definitions/staging/stg_quakes.sqlx /tmp/stg_quakes.GOOD
```

```bash
./scripts/dataform_sync.sh
```

Expect the script to stop at `[5/8] COMPILATION FAILED`, with no invocation
created and BigQuery untouched. Record the error, and record that the mart's
timestamp did not change:

```bash
bq show --format=prettyjson "${PROJECT_ID}:quakes_marts.daily_seismic_summary" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['lastModifiedTime'])"
```

Then revert the typo.

### B8. Break test B, assertion failure

This is the better demonstration, because the model is valid and runs.

First check whether duplicates already exist. After a backfill plus any hourly
run they usually do, because both cover the same hours and the timestamped
filenames mean neither overwrites the other. If `native_rows` already exceeds
`native_distinct`, skip straight to the break. Otherwise force some:

```bash
gcloud run jobs execute quake-hourly --region "$REGION" --wait
gcloud run jobs execute quake-hourly --region "$REGION" --wait
./scripts/load_native.sh
```

Confirm the dedup works before breaking it:

```bash
bq --location="$BQ_LOCATION" query --use_legacy_sql=false "
SELECT
  (SELECT COUNT(*) FROM \`${PROJECT_ID}.quakes.quakes_native\`
     WHERE event_time > TIMESTAMP '1900-01-01')          AS native_rows,
  (SELECT COUNT(DISTINCT event_id) FROM \`${PROJECT_ID}.quakes.quakes_native\`
     WHERE event_time > TIMESTAMP '1900-01-01')          AS native_distinct,
  (SELECT COUNT(*) FROM \`${PROJECT_ID}.quakes_staging.stg_quakes\`) AS staging_rows"
```

`native_rows` should exceed `native_distinct`, and `staging_rows` should equal
`native_distinct` exactly. That is the dedup, proven.

Now comment out the `QUALIFY` block in `stg_quakes.sqlx` and sync:

```bash
./scripts/dataform_sync.sh
```

Expected action states:

```
SUCCEEDED    quakes_staging.stg_quakes
FAILED       dataform_assertions.quakes_staging_stg_quakes_assertions_uniqueKey_0
SKIPPED      quakes_marts.daily_seismic_summary
```

Staging built. Its uniqueness assertion caught the duplicates. **The mart did not
run.** That is spec bullet 5's last sentence, demonstrated.

See what the assertion caught:

```sql
SELECT * FROM `PROJECT.dataform_assertions.quakes_staging_stg_quakes_assertions_uniqueKey_0`
LIMIT 10
```

Restore the `QUALIFY`, sync again, all green.

### B9. What the assertions do not catch

```sql
SELECT event_type, SUM(event_count) AS n
FROM `PROJECT.quakes_marts.daily_seismic_summary`
GROUP BY event_type ORDER BY n DESC
```

Expect roughly:

```
  10687  earthquake
    165  quarry blast
     64  explosion
      7  ice quake
      5  landslide
```

241 non-earthquake rows passed every structural assertion, because `uniqueKey`
and `nonNull` check shape and not meaning. Record this. It is the cheapest
demonstration in the exercise of what assertions do not do for you, and it is why
Exercise 05 needs a Dataplex scan.

### B10. Unattended scheduler evidence

Come back after two hour boundaries:

```bash
gcloud run jobs executions list --job quake-hourly --region "$REGION" --limit 10
```

Executions appearing on the hour with nobody triggering them. Paste into results.
This is the only evidence for the "trigger hourly" half of spec bullet 1.

---

# Exercise 01 completion checklist

**12 of 13 done.** Full evidence in `notes/ex01-results.md`.

| # | Spec requirement | Status |
|---|---|---|
| 1a | Cloud Run job flattens the feed to one JSON object per line | done |
| 1b | Writes to `raw/quakes/dt=/hh=/` | done |
| 1c | **Triggered hourly by Cloud Scheduler, observed unattended** | **OPEN.** See below |
| 2a | External table with Hive partitioning | done |
| 2b | Query it, note bytes billed | done |
| 3a | Native table partitioned by event date, clustered by region | done |
| 3b | Loaded with `bq load`, not CTAS | done |
| 3c | Same query, compare bytes billed | done, 19.4x measured |
| 4 | `require_partition_filter = true`, run unfiltered, read the error | done, verbatim captured |
| 5a | `stg_quakes` deduped on event id | done, 7 duplicates removed |
| 5b | `daily_seismic_summary` mart | done |
| 5c | `uniqueKey` and `nonNull` assertions | done |
| 5d | Break a model, confirm the mart does not update | done, both tests |
| ✔ | Done when: predict bytes billed before running | done, 3 exact and 2 close |
| ✔ | Done when: defend external vs native | done, measured |

## The one open item

Spec bullet 1c. No work, only wall-clock time. The chain is proven, we fired the
scheduler by hand and saw `RUN BY pipeline-runner`, but nobody has watched it
fire on its own.

On any future lab, after Part A, leave it alone for two hours then run **B10**:

```bash
gcloud run jobs executions list --job quake-hourly --region "$REGION" --limit 10
```

Paste the output into `notes/ex01-results.md` and Exercise 01 is 13 of 13.

## Headline results, for reference

| Finding | Number |
|---|---|
| Native vs external, same query, same day | **19.4x** less on native |
| Full native scan of 31 days vs one external day | 131,144 vs 191,047. **Native wins** |
| Partition pruning on native | 13x cut |
| Column pruning on native, 2 cols vs `SELECT *` | 6.9x |
| Column pruning on external | **none.** Q2 and Q7 read identical bytes |
| Bytes billed, every query | 10,485,760, the 10 MiB floor |
| Native storage vs the same data as NDJSON | 1.43 MB vs 4.04 MiB, 2.8x |

---

# Teardown

Reverse order. ex01 reads foundation's state, so it goes first.

```bash
scripts/tf.sh ex01 destroy
scripts/tf.sh foundation destroy
```

Then reset for next time:

```bash
rm -f terraform/*/terraform.tfstate*
rm -f terraform/lab.tfvars dataform/workflow_settings.yaml
rm -f secrets/lab-credentials.md
```

Reset `require_partition_filter = false` in `ex01-batch-elt.tfvars` so the next
run measures without it first.

Commit `notes/ex01-results.md`. It is the only thing that survives the project.

---

# Gotchas, already hit and diagnosed

| Symptom | Cause and fix |
|---|---|
| `PERMISSION_DENIED` on impersonation right after apply | IAM propagation lag. Wait 4 minutes and retry. The binding is fine |
| `API not enabled` during a fresh apply | Enablement lag. Run apply again |
| Dataform repo exists but no workspace | Normal. Terraform makes the repo, `dataform_sync.sh` makes the workspace |
| A script prints the env header then stops silently | It sourced `env.sh` under `set -e`. Fixed, but look for a trailing `[[ ]] &&` if it recurs |
| `gcloud scheduler jobs describe` shows `status.code -1` | Means "no result recorded yet", not an error. Check for a Cloud Run execution instead |
| `bq` error text looks cut off when grepped | bq hard-wraps across lines. Read the whole output |
| Cannot read `constraints/gcp.resourceLocations` | Org Policy API is off. Do not enable it. The apply is the real region test |
| `hh=03` does not match `hh = '03'` | `hh` is an INTEGER from the CUSTOM hive prefix. Filter with `hh = 3` |
| Three files in one `hh=` folder | Scheduler retries plus Cloud Run retries. Free duplicates for the dedup proof, not a bug |
