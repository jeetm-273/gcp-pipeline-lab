import json
import urllib.request
from datetime import datetime, timezone

USGS_URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson"
OUTPUT_FILE = "quakes.ndjson"


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
    data = fetch_usgs()

    features = data["features"]

    with open(OUTPUT_FILE, "w", encoding="utf-8") as output:
        for feature in features:
            record = flatten_feature(feature)
            output.write(json.dumps(record, ensure_ascii=False) + "\n")

    print(f"Wrote {len(features)} records to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()