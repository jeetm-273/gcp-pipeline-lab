#!/usr/bin/env bash
# Build and push the ingest image.
#
#   ./scripts/build.sh          # uses image_tag from ex01-batch-elt.tfvars
#   ./scripts/build.sh v2       # override
#
# Run this after foundation apply and before ex01 apply. The registry lives in
# foundation, so there is no chicken and egg problem.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/env.sh"

TFVARS="$ROOT/terraform/ex01-batch-elt/ex01-batch-elt.tfvars"
TAG="${1:-$(grep -oP 'image_tag\s*=\s*"\K[^"]+' "$TFVARS" 2>/dev/null || echo v1)}"

IMAGE="${IMAGE_PREFIX}/quake-ingest:${TAG}"

echo "building $IMAGE"

gcloud builds submit "$ROOT/apps/quake-ingest" \
  --tag "$IMAGE" \
  --region "$REGION"

echo
echo "pushed $IMAGE"
echo "if the tag changed, set image_tag in $TFVARS then: scripts/tf.sh ex01 apply"
