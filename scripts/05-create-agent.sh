#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 05 - Create the SRE Agent (best-effort automation)
#
# The SRE Agent is an ARM resource:
#   type:        Microsoft.App/agents
#   api-version: 2025-05-01-preview   (PREVIEW)
#
# This script automates the PREREQUISITES (managed identity + App Insights)
# and creates the agent via the control-plane PUT.
#
# KEY (verified working 2026-07): properties.actionConfiguration.identity MUST
# be set to the user-assigned managed identity resource id, and the same MI must
# appear in the top-level identity block. If the PUT still returns a preview-API
# error in your tenant, create the agent once in the portal (https://sre.azure.com,
# 2-5 min) then run scripts 03 (RBAC) and 06 (config).
# ---------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/00-variables.sh"

AGENT_NAME="${AGENT_NAME:-${PREFIX}-agent}"
MI_NAME="${PREFIX}-agent-mi"
APPI_NAME="${PREFIX}-appi"
API="2025-05-01-preview"

echo "==> Creating user-assigned managed identity ${MI_NAME}"
az identity create -g "${RESOURCE_GROUP}" -n "${MI_NAME}" -l "${LOCATION}" -o none
MI_ID=$(az identity show -g "${RESOURCE_GROUP}" -n "${MI_NAME}" --query id -o tsv)
MI_PRINCIPAL=$(az identity show -g "${RESOURCE_GROUP}" -n "${MI_NAME}" --query principalId -o tsv)

echo "==> Ensuring workspace-based Application Insights ${APPI_NAME}"
az extension add -n application-insights -y >/dev/null 2>&1 || true
LAW_ID=$(az monitor log-analytics workspace show -g "${RESOURCE_GROUP}" -n "${LAW_NAME}" --query id -o tsv)
az monitor app-insights component create -g "${RESOURCE_GROUP}" -a "${APPI_NAME}" \
  -l "${LOCATION}" --workspace "${LAW_ID}" -o none 2>/dev/null || true

RG_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

echo "==> Attempting control-plane PUT for agent ${AGENT_NAME} (preview API)"
# App Insights details so Operations Hub analytics work out of the box
APPI_APPID=$(az monitor app-insights component show -g "${RESOURCE_GROUP}" -a "${APPI_NAME}" --query appId -o tsv 2>/dev/null)
APPI_CONN=$(az monitor app-insights component show -g "${RESOURCE_GROUP}" -a "${APPI_NAME}" --query connectionString -o tsv 2>/dev/null)
APPI_ID=$(az monitor app-insights component show -g "${RESOURCE_GROUP}" -a "${APPI_NAME}" --query id -o tsv 2>/dev/null)
cat > /tmp/${AGENT_NAME}-body.json <<JSON
{
  "location": "${LOCATION}",
  "identity": { "type": "UserAssigned", "userAssignedIdentities": { "${MI_ID}": {} } },
  "properties": {
    "actionConfiguration": { "mode": "Review", "accessLevel": "High", "identity": "${MI_ID}" },
    "defaultModel": { "provider": "Anthropic", "name": "Automatic" },
    "knowledgeGraphConfiguration": { "identity": "${MI_ID}", "managedResources": [ "${RG_ID}" ] },
    "incidentManagementConfiguration": { "type": "AzMonitor" },
    "logConfiguration": { "applicationInsightsConfiguration": {
      "appId": "${APPI_APPID}",
      "connectionString": "${APPI_CONN}",
      "applicationInsightsResourceId": "${APPI_ID}"
    }},
    "upgradeChannel": "Stable"
  }
}
JSON

if az rest -m PUT \
     --url "https://management.azure.com${RG_ID}/providers/Microsoft.App/agents/${AGENT_NAME}?api-version=${API}" \
     --body @/tmp/${AGENT_NAME}-body.json 2>/tmp/${AGENT_NAME}-err.json; then
  echo "Agent created. Fetching endpoint..."
  az rest -m GET \
    --url "https://management.azure.com${RG_ID}/providers/Microsoft.App/agents/${AGENT_NAME}?api-version=${API}" \
    --query "properties.agentEndpoint" -o tsv
else
  echo ""
  echo "!! Automated create failed (expected on current preview API)."
  echo "   Error:"; sed 's/^/     /' /tmp/${AGENT_NAME}-err.json
  echo ""
  echo "   FALLBACK - create the agent once in the portal:"
  echo "     1. Go to https://sre.azure.com"
  echo "     2. Basics: subscription=${SUBSCRIPTION_ID}, resource group=${RESOURCE_GROUP},"
  echo "        name=${AGENT_NAME}, region=${LOCATION}, model provider=Anthropic (Automatic)"
  echo "     3. Review > Create (2-5 min)"
  echo "     4. Copy the agent's managed-identity object id into .env as"
  echo "        SRE_AGENT_MI_PRINCIPAL_ID, then run ./scripts/03-assign-rbac.sh"
fi

echo ""
echo "Prereqs ready:"
echo "  Managed identity : ${MI_ID}"
echo "  MI principal id  : ${MI_PRINCIPAL}"
echo "  App Insights     : ${APPI_NAME}"
