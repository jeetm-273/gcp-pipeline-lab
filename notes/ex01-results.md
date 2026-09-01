# Exercise 01 results: Batch ELT with no processing engine

Partitioning and clustering, external vs native tables, Dataform.

| | |
|---|---|
| Lab project | `qwiklabs-gcp-02-469ea3020e10` (dead, projects are throwaway) |
| Earlier recon project | `qwiklabs-gcp-02-517617116623` |
| Date | 2026-09-01 |
| Region | `us-west1` for Cloud Run, GCS, Artifact Registry, Scheduler, Dataform |
| BigQuery location | `US` multi-region |
| Status | **12 of 13 spec items complete.** Only unattended scheduler evidence remains |
| Cost | $0. Everything used sat inside the always-free tier |

Rebuild instructions are in the repo `README.md`, Part A. This file is the
evidence.

---

## Spec scorecard

| # | Spec requirement | Status |
|---|---|---|
| 1a | Cloud Run job flattens the feed to one JSON object per line | done |
| 1b | Writes to `raw/quakes/dt=YYYY-MM-DD/hh=HH/` | done |
| 1c | Triggered hourly by Cloud Scheduler, **observed unattended** | **OPEN.** Chain proven by manual trigger, never watched firing on its own |
| 2a | External table over the prefix with Hive partitioning | done |
| 2b | Query it, note bytes billed | done |
| 3a | Native table partitioned by event date, clustered by region | done |
| 3b | Loaded with `bq load`, not CTAS | done |
| 3c | Same query, compare bytes billed | done |
| 4 | `require_partition_filter = true`, unfiltered query, read the error | done |
| 5a | `stg_quakes` deduped on event id | done |
| 5b | `daily_seismic_summary` mart | done |
| 5c | `uniqueKey` and `nonNull` assertions | done |
| 5d | Break a model, confirm the mart does not update | done, both tests |
| ✔ | Done when: predict bytes billed before running | done, 3 exact and 2 close |
| ✔ | Done when: defend external vs native | done, measured at 19.4x |

### The one open item

Spec bullet 1c. No work involved, only wall-clock time. On any future lab, after
Part A, leave it alone for two hours then run:

```bash
gcloud run jobs executions list --job quake-hourly --region "$REGION" --limit 10
```

Executions appearing on the hour that nobody triggered. Paste the output here and
this becomes 13 of 13.

---

## Shape of what was built

```
USGS all_hour / all_month GeoJSON
        |
   Cloud Run job (quake-hourly, quake-backfill)   <- Cloud Scheduler, hourly UTC
        |
   GCS  gs://PROJECT-quakes/raw/quakes/dt=DATE/hh=HH/quakes-STAMP.ndjson
        |                                    720 folders, 31 distinct days
        +--> quakes_external   Hive partitioned, CUSTOM mode, pinned schema
        |
   bq load (free, batch)
        |
   quakes_native   DAY partitioned on event_time, clustered by region
        |
   Dataform: quakes_native (declaration)
        -> stg_quakes         deduped, uniqueKey + nonNull
        -> daily_seismic_summary   dependOnDependencyAssertions
```

Measured facts about the data:

| Measure | Value |
|---|---|
| Rows in `all_month.geojson` | 10,925 |
| Same data as NDJSON in GCS | 4,236,081 bytes, 4.04 MiB, 387 bytes/row |
| GCS `dt=/hh=` folders | 720 |
| Distinct days, so native partitions | **31** |
| Rows loaded into `quakes_native` | 10,930, of which 10,923 distinct |
| `quakes_native` size in BigQuery | **1,495,263 bytes, 1.43 MB** |
| Compression, NDJSON to native | **2.8x smaller** |
| One day in native | about 46 KB, a single block |

**720 and 31 are different numbers and mixing them up breaks the predictions.**
The GCS layout is partitioned by hour, the native table only by day.

---

## 1. Bytes billed (spec bullets 2b and 3c)

`PICK_DATE = 2026-08-08`, the busiest day at 494 events.

### Predictions, written before any query ran

Reasoning used: native table 1.4 MB across 14 columns, 31 day partitions, one day
about 46 KB, billing floor 10 MiB per table per query. All three native queries
touch only `region` and `magnitude`, 2 of 14 columns.

| Query | Reasoning | Predicted processed | Predicted billed |
|---|---|---|---|
| Q3 native, no filter | 2 cols x 31 partitions | 150-250 KB | 10 MiB (floor) |
| Q4 native, 1 day | 2 cols x 1 partition | 5-8 KB | 10 MiB (floor) |
| Q5 native, 1 day + region | same as Q4, single block | same as Q4 | 10 MiB (floor) |

### Measured

| Q | Table | Filter / select | Dry run est | Processed | Billed | MiB billed | ms |
|---|---|---|---|---|---|---|---|
| Q1 | external | none, 2 cols | 0 | 4,240,598 | 10,485,760 | 10.0 | 1229 |
| Q2 | external | dt filter, 2 cols | 0 | 191,047 | 10,485,760 | 10.0 | 825 |
| Q3 | native | none, 2 cols | 131,144 | 131,144 | 10,485,760 | 10.0 | 433 |
| Q4 | native | 1 day, 2 cols | 9,872 | 9,872 | 10,485,760 | 10.0 | 1404 |
| Q5 | native | 1 day + `region='ak'` | 9,872 | 9,872 | 10,485,760 | 10.0 | 355 |
| Q6 | native | 1 day, `SELECT *` | 67,734 | 67,734 | 10,485,760 | 10.0 | 407 |
| Q7 | external | dt filter, 2 cols raw | 0 | 191,047 | 10,485,760 | 10.0 | 916 |

### How the predictions did

| Prediction | Actual | Verdict |
|---|---|---|
| Q3 processed 150-250 KB | 128 KB | close, slightly over |
| Q4 processed 5-8 KB | 9.6 KB | close, slightly under |
| Q5 identical to Q4 | 9,872 vs 9,872, byte for byte | EXACT |
| Billed = 10 MiB floor on every query | 10,485,760 on all seven | EXACT |
| External dry run cannot estimate | Q1, Q2, Q7 all returned 0 | EXACT |

### Conclusion

**Which pruning reduced processed bytes.** Partition pruning did the heavy
lifting on native: Q3 to Q4 is 131,144 down to 9,872, a **13x cut**. Column
pruning also works on native: Q6 `SELECT *` reads 67,734 against Q4's 9,872 for
the same partition, so asking for 14 columns instead of 2 costs **6.9x**. Hive
partition pruning works on the external table too: Q1 to Q2 is 4,240,598 down to
191,047, a **22x cut**.

**Clustering did nothing, exactly as predicted.** Q5 read the same 9,872 bytes as
Q4. One day is about 46 KB, which is a single BigQuery block, so a `region` filter
has nothing to skip. Clustering starts paying once one partition spans many
blocks, somewhere in the millions of rows for this schema.

**Why billed did not move.** Every query billed exactly 10,485,760 bytes, which is
10 MiB, the on-demand minimum per table referenced per query. The whole native
table is 1.4 MB, so no amount of pruning can get under the floor:

```
bytes billed = max(10 MiB per table referenced, bytes actually scanned)
```

**When billed starts tracking processed.** Once a single query's real scan exceeds
10 MiB. At roughly 137 bytes per row in native storage, that is about 76,000 rows
in the columns actually selected. At 350 events a day, roughly seven months of
data, or immediately if you scan all 14 columns over about 150 days.

**External vs native, the decisive number.** Q7 and Q4 are the same logical query
over the same day, one against each table:

```
Q7  external, 2 columns, 1 day  = 191,047 bytes
Q4  native,   2 columns, 1 day  =   9,872 bytes      19.4x less
```

Two effects stack. First, columnar storage plus compression: native is 1.43 MB
where the same data as NDJSON is 4.04 MiB, so 2.8x smaller before anything else.
Second and larger, column pruning: **Q2 and Q7 read the identical 191,047 bytes**
even though Q2 aggregates two columns and Q7 selects two columns raw. NDJSON is
row-oriented text, so BigQuery reads and parses every byte of every line no matter
how few fields you name. Native reads only the columns asked for.

The sharpest way to say it: **a full scan of the entire native table across all 31
days, 131,144 bytes, is cheaper than reading one single day of the external table,
191,047 bytes.**

**Would I keep the external table?** Yes, but only as a landing zone. It is the
right tool for querying whatever just arrived in GCS with no load step, which is
what makes the hourly ingest immediately visible. It is the wrong tool for
anything repeated or analytical, because it cannot prune columns and it bills GCS
bytes on every query. Load into native and query that. That is the ELT shape this
exercise teaches.

---

## 2. require_partition_filter (spec bullet 4)

Set with one line in `terraform/ex01-batch-elt/ex01-batch-elt.tfvars` then apply.
Terraform plan showed `~ update in-place` and
`require_partition_filter = false -> true` with **0 to destroy**, so no data was
at risk. Doing it through Terraform rather than `ALTER TABLE` means the change is
a one line `git diff`.

Verbatim error from the unfiltered query:

```
Error in query string: Error processing job
'qwiklabs-gcp-02-469ea3020e10:bqjob_r3041e354b014f307_000001a05d105ec2_1':
Cannot query over table 'qwiklabs-gcp-02-469ea3020e10.quakes.quakes_native'
without a filter over column(s) 'event_time' that can be used for partition
elimination
```

What it told me to do: put a filter on `event_time`, the partitioning column. The
message names the exact column, which is what makes the setting usable rather
than merely annoying.

| Action | Expected | Actual |
|---|---|---|
| `SELECT COUNT(*)`, no filter | fails | fails, error above |
| One day `event_time` filter | works | works, returned 494 |
| `bq load --replace` | works | works. Loads are not queries |
| Does the load reset the flag? | unknown | **No.** Flag stayed `True` and `tf.sh ex01 plan` reported `No changes` |

The last row was an open question (R6) and is now settled. WRITE_TRUNCATE
preserves the option when the partitioning flags are passed explicitly, which
`load_native.sh` does. Running `tf.sh ex01 apply` after a load is precautionary,
not required.

The real consequence is downstream: turning this on forces every Dataform model
to declare how much history it wants. That is why `stg_quakes` carries a 90 day
`WHERE` clause. The constraint is the feature.

---

## 3. Dedup (spec bullet 5a)

| Measure | Value |
|---|---|
| `quakes_native` rows | 10,930 |
| `quakes_native` distinct `event_id` | 10,923 |
| `stg_quakes` rows | **10,923** |

7 duplicates in the source, 0 in staging. The `QUALIFY ROW_NUMBER()` window kept
exactly one row per `event_id` and the `uniqueKey` assertion passed.

The duplicates arose on their own, which is the point. The hourly scheduler run
and the month backfill both covered the same hours, and because filenames carry
an ingest timestamp neither overwrote the other. At-least-once behaviour appears
without anyone asking for it, so dedup is not optional.

---

## 4. Break tests (spec bullet 5d)

### Test A, the compilation gate

Broke the source reference from `${ref("quakes_native")}` to
`${ref("quakes_nativeee")}` and ran the sync.

```
[5/8] COMPILATION FAILED
  definitions/staging/stg_quakes.sqlx: Could not resolve "quakes_nativeee"
  definitions/staging/stg_quakes.sqlx: Missing dependency detected: Action
  "...quakes_staging.stg_quakes" depends on "quakes_nativeee" which does not exist

Nothing was executed. BigQuery is untouched.
```

The sync script stopped before creating a workflow invocation, so no BigQuery job
ran at all.

Two things worth noting. This only works because the model uses `${ref()}` rather
than a hard coded table string; a raw string would have compiled fine and failed
later at execution. And breaking a *column name* would not have produced a
compilation error either, because Dataform translates SQLX to SQL without
validating columns against BigQuery. The dependency graph is the thing
compilation can actually check.

### Test B, an assertion failure blocking the mart

Removed the `QUALIFY` block so duplicates survive into staging. The model is
valid SQL, so it compiles and runs.

```
SUCCEEDED    quakes_staging.stg_quakes
SUCCEEDED    dataform_assertions.quakes_staging_stg_quakes_assertions_rowConditions
FAILED       dataform_assertions.quakes_staging_stg_quakes_assertions_uniqueKey_0
SKIPPED      quakes_marts.daily_seismic_summary
SKIPPED      dataform_assertions.quakes_marts_daily_seismic_summary_assertions_uniqueKey_0
SKIPPED      dataform_assertions.quakes_marts_daily_seismic_summary_assertions_rowConditions
```

Staging built. Its uniqueness assertion caught the duplicates and failed. The mart
and both of its own assertions were SKIPPED.

Proof the mart genuinely did not update:

```
lastModifiedTime before break: 1788266748154
lastModifiedTime after  break: 1788266748154      UNCHANGED
```

The assertion view held **7 rows**, one per duplicated `event_id`, matching the 7
duplicates above. An assertion is just a view selecting the offending rows.

The mechanism is `dependOnDependencyAssertions: true` on the mart. Without it the
mart depends on the staging *table* only, and would happily rebuild from a table
whose assertions had just failed.

Restored the `QUALIFY` and re-ran: all 6 actions SUCCEEDED.

---

## 5. What the assertions do not catch

```
10687  earthquake
  165  quarry blast
   64  explosion
    7  ice quake
    5  landslide
```

241 non-earthquake rows out of 10,928, so 2.2 percent. Every one passed
`uniqueKey` and `nonNull` without complaint, because both check **shape** and
neither checks **meaning**. `all_month.geojson` is not all earthquakes.

`landslide` was in nobody's expected list. That is the argument for Exercise 05's
Dataplex scan asserting `event_type` against a known set: the categories change
and nobody tells you.

The mart groups by `event_type` rather than filtering to earthquakes, so the
blasts stay visible instead of being quietly folded into a "seismic" average.

---

## 6. Impersonation

`roles/iam.serviceAccountTokenCreator` on `pipeline-runner` applied cleanly, and
impersonation works. Both stacks report `No changes` when Terraform runs as the
service account.

**But not immediately.** The first attempt returned:

```
PERMISSION_DENIED: Failed to impersonate [pipeline-runner@...]
Permission 'iam.serviceAccounts.getAccessToken' denied on resource
```

while `gcloud iam service-accounts get-iam-policy` showed the binding present and
correct. It started working about four minutes later. **It was IAM propagation
lag, not a lab restriction.** Reading the first denial as a policy block would
mean skipping the impersonation half of the exercise for no reason.

---

## 7. Two bugs found in my own tooling

Worth recording because both were silent.

**`scripts/env.sh` killed every script that sourced it.** The last line was
`[[ -z "$NATIVE_TABLE" ]] && echo "..."`. Once ex01 is applied that test is false,
so the line returns exit 1, and as the last line of a *sourced* file that became
the `source` builtin's exit status, which tripped `set -e` in the caller.
`load_native.sh` printed its header and died with no error. Fixed by using an
`if` block. The same shape inline is safe, because bash exempts the left side of
a `&&` list from `set -e`.

**`scripts/dataform_sync.sh` crashed on escaped quotes inside f-strings.** Two
Python blocks used `\"` inside an f-string, a syntax error. Rewritten with plain
concatenation.

Also seen once: a transient `curl: (22) 502` from the Dataform writeFile API. A
straight retry worked.

---

## 8. Deliberate gaps, not oversights

| Not done | Why |
|---|---|
| `quakes_native` is not reloaded automatically after each hourly ingest | Exercise 04 is the orchestration exercise and chaining ingest, load, Dataform and validation is its content. Leaving the seam visible gives it something real to fix |
| Dataform is not scheduled | Same reason |
| No budget alert at $5 | Qwiklabs student accounts cannot see the billing account. The real guardrail is the Ex03 and Ex04 teardown discipline |
| Not one region everywhere | `us-west1` for everything except BigQuery in `US` multi-region. A US multi-region dataset reads any US single-region bucket fine. Confirmed Composer 3 and Dataplex both cover us-west1, so the choice holds for all five exercises |
| No data quality scan, policy tags or row access policy | Exercise 05 |
| No incremental Dataform models | `type: "table"` full refresh is correct at this size |
| No Terraform modules | Every candidate had one caller. `pubsub-bq-sink` gets extracted at Exercise 02, from code that already works |
| No CI | Deferred by choice until all five exercises are done |

---

## 9. Things learned that are worth keeping

1. `bq load` is free; `CREATE TABLE AS SELECT` from an external table is a query
   and bills every GCS byte. Same table at the end. This is the single most
   practical fact in the exercise.
2. Bytes billed has a 10 MiB per-table floor, so pruning is invisible in the bill
   at small scale even when it is working perfectly.
3. External tables cannot prune columns. Q2 and Q7 reading identical bytes proves
   it in one line.
4. Dry run gives real numbers for native tables and nothing at all for external
   ones, because BigQuery has not opened the GCS files yet.
5. `require_partition_filter` names the offending column in its error, which is
   what makes it a usable guardrail rather than a blunt one.
6. Structural assertions do not check meaning. 241 quarry blasts passed every one.
7. IAM bindings apply instantly but take minutes to be honoured.
8. Terraform creates a Dataform repository; only the API can create a workspace.
