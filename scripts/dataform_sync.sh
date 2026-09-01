#!/usr/bin/env bash
# Upload the local dataform/ folder, compile it, run it, report per action state.
#
#   ./scripts/dataform_sync.sh
#   RECREATE=1 ./scripts/dataform_sync.sh    # wipe the workspace first
#
# Replaces the old setup_dataform.sh, which built the SQLX from inline
# heredocs and never read the dataform/ folder. This reads your actual files,
# so what you edit is what runs.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/env.sh"

BASE="https://dataform.googleapis.com/v1"
REPO_NAME="projects/${PROJECT_ID}/locations/${REGION}/repositories/${DATAFORM_REPO}"
REPO_URL="${BASE}/${REPO_NAME}"
WS_NAME="${REPO_NAME}/workspaces/dev"
WS_URL="${BASE}/${WS_NAME}"

TOKEN="$(gcloud auth print-access-token)"

api() {
  local method="$1" url="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      "$url" -d "$body"
  else
    curl -fsS -X "$method" -H "Authorization: Bearer ${TOKEN}" "$url"
  fi
}

jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }

# ---------------------------------------------------------------- 1. settings
echo "[1/8] rendering workflow_settings.yaml"
sed -e "s|__PROJECT_ID__|${PROJECT_ID}|g" \
  -e "s|__LOCATION__|${BQ_LOCATION}|g" \
  "$DATAFORM_DIR/workflow_settings.yaml.template" \
  > "$DATAFORM_DIR/workflow_settings.yaml"

# --------------------------------------------------------------- 2. workspace
if [[ "${RECREATE:-0}" == "1" ]]; then
  echo "[2/8] deleting workspace dev"
  api DELETE "$WS_URL" >/dev/null 2>&1 || true
fi

if api GET "$WS_URL" >/dev/null 2>&1; then
  echo "[2/8] workspace dev exists"
else
  echo "[2/8] creating workspace dev"
  # If this 400s, put workspaceId in the body instead of the query string.
  api POST "${REPO_URL}/workspaces?workspaceId=dev" '{}' >/dev/null
fi

# ------------------------------------------------------------------ 3. upload
echo "[3/8] uploading files"
cd "$DATAFORM_DIR"

while IFS= read -r rel; do
  body=$(python3 -c '
import base64, json, sys
p = sys.argv[1]
print(json.dumps({
    "path": p,
    "contents": base64.b64encode(open(p, "rb").read()).decode(),
}))' "$rel")
  api POST "${WS_URL}:writeFile" "$body" >/dev/null
  echo "      $rel"
done < <(
  find . -type f \
    \( -name '*.sqlx' -o -name 'package.json' -o -name 'workflow_settings.yaml' \) \
    ! -name '*.template' \
    | sed 's|^\./||' | sort
)

# ----------------------------------------------------------------- 4. compile
echo "[4/8] compiling"
COMPILE_JSON=$(api POST "${REPO_URL}/compilationResults" \
  "{\"workspace\":\"${WS_NAME}\"}")

COMPILATION_NAME=$(jget '["name"]' <<<"$COMPILE_JSON")

# ------------------------------------------------------- 5. compilation gate
# The old script skipped this, so a broken model looked like a successful run
# right up until the invocation failed with a confusing message.
ERRORS=$(python3 -c '
import json, sys
d = json.load(sys.stdin)
errs = d.get("compilationErrors") or []
for e in errs:
    target = e.get("actionTarget") or {}
    where = e.get("path") or target.get("name") or "?"
    msg = (e.get("message") or "").strip()
    print("  " + where + ": " + msg)
print("COUNT=" + str(len(errs)))
' <<<"$COMPILE_JSON")

if [[ "${ERRORS##*COUNT=}" != "0" ]]; then
  echo
  echo "[5/8] COMPILATION FAILED"
  echo "${ERRORS%COUNT=*}"
  echo "Nothing was executed. BigQuery is untouched."
  exit 1
fi
echo "[5/8] compilation clean"

# ---------------------------------------------------------------- 6. invoke
echo "[6/8] invoking"
INVOKE_JSON=$(api POST "${REPO_URL}/workflowInvocations" \
  "{\"compilationResult\":\"${COMPILATION_NAME}\"}")

INVOCATION_NAME=$(jget '["name"]' <<<"$INVOKE_JSON")
INVOCATION_URL="${BASE}/${INVOCATION_NAME}"

# ------------------------------------------------------------------- 7. poll
echo "[7/8] waiting"
STATE=""
for _ in $(seq 1 60); do
  STATE=$(api GET "$INVOCATION_URL" | jget '["state"]')
  case "$STATE" in
    SUCCEEDED | FAILED | CANCELLED | CANCELED) break ;;
  esac
  sleep 3
done
echo "      state: $STATE"

# ---------------------------------------------------------------- 8. actions
echo "[8/8] per action state"
api GET "${INVOCATION_URL}:query" | python3 -c '
import json, sys
for a in json.load(sys.stdin).get("workflowInvocationActions", []):
    t = a.get("target") or {}
    schema = t.get("schema") or ""
    name = t.get("name") or ""
    state = a.get("state") or "?"
    print("      " + state.ljust(12) + " " + schema + "." + name)
'

echo
if [[ "$STATE" != "SUCCEEDED" ]]; then
  echo "Invocation did not succeed. A FAILED assertion with a SKIPPED mart"
  echo "downstream is the expected result of break test B."
  exit 1
fi
echo "done. tables in ${DATASET_STAGING} and ${DATASET_MARTS}"
