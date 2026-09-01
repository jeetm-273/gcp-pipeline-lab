import json
import os
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone

from google.cloud import storage

FEEDS = {
    "hour": "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson",
    "month": "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_month.geojson",
}


def fetch_usgs(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return json.load(response)


def epoch_ms_to_dt(milliseconds):
    if milliseconds is None:
        return None

    return datetime.fromtimestamp(milliseconds / 1000, tz=timezone.utc)


def iso(value):
    if value is None:
        return None

    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def flatten_feature(feature, ingested_at):
    properties = feature["properties"]

    coordinates = (feature.get("geometry") or {}).get("coordinates") or []
    longitude, latitude, depth = (list(coordinates) + [None] * 3)[:3]

    return {
        "event_id": feature["id"],
        "event_time": epoch_ms_to_dt(properties.get("time")),
        "updated_time": epoch_ms_to_dt(properties.get("updated")),
        "region": properties.get("net"),
        "event_type": properties.get("type"),
        "magnitude": properties.get("mag"),
        "magnitude_type": properties.get("magType"),
        "place": properties.get("place"),
        "latitude": latitude,
        "longitude": longitude,
        "depth": depth,
        "status": properties.get("status"),
        "tsunami": properties.get("tsunami"),
        "ingested_at": ingested_at,
    }


def group_by_partition(records):
    """Group by the event's own hour, not by ingestion time.

    A month backfill then spreads across ~720 dt=/hh= folders instead of
    landing in one, and dt means the same thing as DATE(event_time) on the
    native table.
    """
    groups = defaultdict(list)

    for record in records:
        event_time = record["event_time"]
        key = (event_time.strftime("%Y-%m-%d"), event_time.strftime("%H"))
        groups[key].append(record)

    return groups


def to_json_line(record):
    row = {
        key: iso(value) if isinstance(value, datetime) else value
        for key, value in record.items()
    }

    return json.dumps(row, ensure_ascii=False)


def main():
    bucket_name = os.environ["BUCKET"]
    mode = os.environ.get("MODE", "hour")

    if mode not in FEEDS:
        raise SystemExit(f"MODE must be one of {sorted(FEEDS)}, got {mode!r}")

    ingested_at = datetime.now(timezone.utc)
    data = fetch_usgs(FEEDS[mode])

    records = [flatten_feature(f, ingested_at) for f in data["features"]]

    # USGS occasionally emits an event with no time. It has nowhere to go in a
    # time partitioned layout, so count it and move on.
    dropped = sum(1 for r in records if r["event_time"] is None)
    records = [r for r in records if r["event_time"] is not None]

    groups = group_by_partition(records)

    # Timestamped filename so reruns do not overwrite each other. Two runs in
    # one hour leave two files with overlapping event ids, which is what
    # stg_quakes has to dedup.
    stamp = ingested_at.strftime("%Y%m%dT%H%M%SZ")

    bucket = storage.Client().bucket(bucket_name)

    for (dt, hh), rows in sorted(groups.items()):
        path = f"raw/quakes/dt={dt}/hh={hh}/quakes-{stamp}.ndjson"
        body = "\n".join(to_json_line(r) for r in rows) + "\n"

        bucket.blob(path).upload_from_string(
            body,
            content_type="application/x-ndjson",
        )

        print(f"{len(rows):6d} rows -> gs://{bucket_name}/{path}")

    print(
        f"mode={mode} records={len(records)} "
        f"partitions={len(groups)} dropped={dropped}"
    )


if __name__ == "__main__":
    main()
