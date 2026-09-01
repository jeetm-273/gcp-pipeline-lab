#!/usr/bin/env bash
# Terraform wrapper so you never retype the var file flags.
#
#   scripts/tf.sh foundation apply
#   scripts/tf.sh ex01 plan
#
# Equivalent to:
#   terraform -chdir=terraform/ex01-batch-elt plan \
#     -var-file=../lab.tfvars -var-file=ex01-batch-elt.tfvars

set -euo pipefail

STACK="${1:?usage: tf.sh <stack> <terraform args...>}"
shift

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR=$(compgen -G "$ROOT/terraform/${STACK}*" 2>/dev/null | head -1 || true)

if [[ -z "${DIR:-}" || ! -d "$DIR" ]]; then
  echo "no such stack: $STACK" >&2
  echo "available:" >&2
  find "$ROOT/terraform" -maxdepth 1 -mindepth 1 -type d -printf '  %f\n' >&2
  exit 1
fi

LAB_VARS="$ROOT/terraform/lab.tfvars"

VARS=()
case "${1:-}" in
  init | fmt | validate | output | providers | version | state | show) ;;
  *)
    if [[ ! -f "$LAB_VARS" ]]; then
      echo "missing $LAB_VARS" >&2
      echo "run: cp terraform/lab.tfvars.example terraform/lab.tfvars" >&2
      exit 1
    fi
    VARS+=(-var-file="$LAB_VARS")

    LOCAL_VARS="$DIR/$(basename "$DIR").tfvars"
    if [[ -f "$LOCAL_VARS" ]]; then
      VARS+=(-var-file="$LOCAL_VARS")
    fi
    ;;
esac

echo "==> $(basename "$DIR") : $*"
terraform -chdir="$DIR" "$@" ${VARS[@]+"${VARS[@]}"}
