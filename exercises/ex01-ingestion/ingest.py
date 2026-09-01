import json
import os
import urllib.request
from datetime import datetime, timezone

from google.cloud import storage


USGS_URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson"


def fetch_usgs():
    with urllib.request.urlopen(USGS_URL, timeout=30) as response:
        return json.load(response)


def epoch_ms_to_iso(milliseconds):
    if milliseconds is None:
        return None

    return datetime.fromtimestamp(
        milliseconds / 1000,
        tz=timezone.utc
    ).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def flatten_feature(feature):
    properties = feature["properties"]
    coordinates = feature["geometry"]["coordinates"]

    return {
        "event_id": feature["id"],
        "magnitude": properties.get("mag"),
        "place": properties.get("place"),
        "event_time": epoch_ms_to_iso(properties.get("time")),
        "updated_time": epoch_ms_to_iso(properties.get("updated")),
        "longitude": coordinates[0],
        "latitude": coordinates[1],
        "depth": coordinates[2],
        "magnitude_type": properties.get("magType"),
        "status": properties.get("status"),
        "tsunami": properties.get("tsunami"),
        "region": properties.get("net"),
    }


def main():
    bucket_name = os.environ["BUCKET"]

    data = fetch_usgs()

    records = [
        flatten_feature(feature)
        for feature in data["features"]
    ]

    ndjson = "\n".join(
        json.dumps(record, ensure_ascii=False)
        for record in records
    ) + "\n"

    now = datetime.now(timezone.utc)

    object_path = (
        f"raw/quakes/"
        f"dt={now:%Y-%m-%d}/"
        f"hh={now:%H}/"
        f"quakes.ndjson"
    )

    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(object_path)

    blob.upload_from_string(
        ndjson,
        content_type="application/x-ndjson"
    )

    print(
        f"Wrote {len(records)} records to "
        f"gs://{bucket_name}/{object_path}"
    )


if __name__ == "__main__":
    main()