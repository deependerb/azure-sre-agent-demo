#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 06 - Configure the agent: create an incident response plan (best-effort)
#
# Discovered API (from the portal bundle):
#   PUT {agentEndpoint}/api/v1/incidentPlayground/filters/{id}
#   body: { id, filterName, priority:[Sev0..Sev4], agentMode, instructions }
#   headers: Content-Type: application/json  (+ azuresre.dev bearer token)
#
# NOTE (verified 2026-07): the live endpoint returns a contradictory 405 to
# server-side calls - the portal SPA relies on a browser session the CLI does
# not reproduce. If this script's PUT fails, create the plan in the portal:
#   sre.azure.com -> sredemo-agent -> Incidents -> "Add a response plan"
#   (All severity, Autonomous). To fully script it, open the browser Network
#   tab while saving one plan, copy the exact request, and paste it here.
# ---------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/00-variables.sh"

AGENT_NAME="${AGENT_NAME:-${PREFIX}-agent}"
API="2025-05-01-preview"
RG_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

echo "==> Resolving agent data-plane endpoint"
EP=$(az rest -m GET \
  --url "https://management.azure.com${RG_ID}/providers/Microsoft.App/agents/${AGENT_NAME}?api-version=${API}" \
  --query "properties.agentEndpoint" -o tsv)
[[ -z "${EP}" ]] && { echo "Could not resolve agent endpoint."; exit 1; }

TOKEN=$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv)
FID=$(cat /proc/sys/kernel/random/uuid)

read -r -d '' BODY <<JSON || true
{
  "id": "${FID}",
  "filterName": "all-incidents",
  "priority": ["Sev0","Sev1","Sev2","Sev3","Sev4"],
  "agentMode": "Autonomous",
  "instructions": "Investigate and remediate infrastructure alerts for resource group ${RESOURCE_GROUP}: start a deallocated VM (az vm start), restart the offending Windows service on sustained high CPU/memory, and restart stopped IIS/DB services. Verify the fix and report."
}
JSON

echo "==> Attempting to create response plan 'all-incidents' (Autonomous)"
HTTP=$(curl -s -o /tmp/rp-resp.json -w "%{http_code}" -X PUT \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d "${BODY}" "${EP}/api/v1/incidentPlayground/filters/${FID}")

if [[ "${HTTP}" == "200" || "${HTTP}" == "201" ]]; then
  echo "Response plan created."; cat /tmp/rp-resp.json
else
  echo "!! Automated create returned HTTP ${HTTP} (expected on current preview API)."
  sed 's/^/     /' /tmp/rp-resp.json 2>/dev/null
  echo ""
  echo "   FALLBACK (1 min): sre.azure.com -> ${AGENT_NAME} -> Incidents ->"
  echo "   'Add a response plan' -> name=all-incidents, severity=All, mode=Autonomous -> Save."
fi
