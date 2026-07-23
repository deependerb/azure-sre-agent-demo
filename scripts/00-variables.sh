#!/usr/bin/env bash
# Common variables + guards. Source this from the numbered scripts:
#   source ./scripts/00-variables.sh
set -euo pipefail

# Load .env if present (repo root of the demo kit)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${DEMO_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${DEMO_ROOT}/.env"
else
  echo "ERROR: ${DEMO_ROOT}/.env not found. Copy .env.example to .env and edit it." >&2
  exit 1
fi

# Fail fast if required vars are unset/placeholder
require() {
  local name="$1" val="${!1:-}"
  if [[ -z "${val}" || "${val}" == "<"*">" ]]; then
    echo "ERROR: required variable ${name} is not set (edit .env)." >&2
    exit 1
  fi
}
require SUBSCRIPTION_ID
require LOCATION
require RESOURCE_GROUP
require PREFIX

# Derived names (kept here so every script agrees)
export LAW_NAME="${LAW_NAME:-${PREFIX}-law}"
export DCR_NAME="${DCR_NAME:-${PREFIX}-dcr-guest}"
export VNET_NAME="${PREFIX}-vnet"
export SUBNET_NAME="default"
export NSG_NAME="${PREFIX}-nsg"

echo "Using subscription ${SUBSCRIPTION_ID} / RG ${RESOURCE_GROUP} / ${LOCATION}"
az account set --subscription "${SUBSCRIPTION_ID}"
