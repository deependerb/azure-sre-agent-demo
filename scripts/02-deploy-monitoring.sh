#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 02 - Deploy monitoring signals + alert rules
#   DCR: guest CPU/memory + Windows Service Control Manager events
#   Alert S1: VM powered off (Activity Log)           -> Scenario 1 trigger
#   Alert S2a: Percentage CPU > 95% for 15 min         -> Scenario 2 trigger
#   Alert S2b: Committed memory > 95% for 15 min       -> Scenario 2 trigger
#   Alert S3: IIS (W3SVC) / DemoDbService stopped      -> Scenario 3 trigger
#
# All alerts fire into an Action Group that you will point at the SRE
# Agent (Azure Monitor incident platform). Create the action group in the
# portal after the agent exists, or wire alerts to the agent's webhook.
# ---------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/00-variables.sh"

VM_ID=$(az vm show -g "${RESOURCE_GROUP}" -n "${VM_NAME}" --query id -o tsv)
LAW_ID=$(az monitor log-analytics workspace show -g "${RESOURCE_GROUP}" -n "${LAW_NAME}" --query id -o tsv)
export LAW_ID LOCATION

# --- Data Collection Rule (guest perf + events) ---
echo "==> Creating Data Collection Rule ${DCR_NAME}"
TMP_DCR="$(mktemp)"
envsubst < "$(dirname "${BASH_SOURCE[0]}")/../dcr/guest-dcr.template.json" > "${TMP_DCR}"
az monitor data-collection rule create \
  -g "${RESOURCE_GROUP}" -n "${DCR_NAME}" -l "${LOCATION}" \
  --rule-file "${TMP_DCR}" -o none
DCR_ID=$(az monitor data-collection rule show -g "${RESOURCE_GROUP}" -n "${DCR_NAME}" --query id -o tsv)

echo "==> Associating DCR with the VM"
az monitor data-collection rule association create \
  --name "${DCR_NAME}-assoc" --rule-id "${DCR_ID}" --resource "${VM_ID}" -o none
rm -f "${TMP_DCR}"

# --- Action group (placeholder; connect to SRE Agent afterwards) ---
AG_NAME="${PREFIX}-ag-sre"
echo "==> Creating action group ${AG_NAME} (email placeholder - repoint to SRE Agent)"
az monitor action-group create \
  -g "${RESOURCE_GROUP}" -n "${AG_NAME}" --short-name sredemo \
  --action email demo ops@example.com -o none
AG_ID=$(az monitor action-group show -g "${RESOURCE_GROUP}" -n "${AG_NAME}" --query id -o tsv)

# --- Scenario 2a: platform CPU metric alert ---
echo "==> Alert S2a: Percentage CPU > ${CPU_THRESHOLD}% for ${CPU_WINDOW_MIN} min"
az monitor metrics alert create \
  -g "${RESOURCE_GROUP}" -n "${PREFIX}-s2a-cpu-high" \
  --scopes "${VM_ID}" \
  --condition "avg Percentage CPU > ${CPU_THRESHOLD}" \
  --window-size "${CPU_WINDOW_MIN}m" --evaluation-frequency 5m \
  --severity 2 --action "${AG_ID}" \
  --description "CPU sustained above ${CPU_THRESHOLD}% - SRE Agent scenario 2" -o none

# --- Scenario 2b: guest memory scheduled query alert ---
echo "==> Alert S2b: Committed memory > ${MEM_USED_THRESHOLD}% for ${CPU_WINDOW_MIN} min (guest)"
az monitor scheduled-query create \
  -g "${RESOURCE_GROUP}" -n "${PREFIX}-s2b-mem-high" \
  --scopes "${LAW_ID}" --severity 2 \
  --window-size "${CPU_WINDOW_MIN}m" --evaluation-frequency 5m \
  --action-groups "${AG_ID}" \
  --condition "count 'placeholder' > 0" \
  --condition-query placeholder="Perf | where ObjectName == 'Memory' and CounterName == '% Committed Bytes In Use' | where Computer == '${VM_NAME}' | summarize avgUsed = avg(CounterValue) by bin(TimeGenerated, 5m) | where avgUsed > ${MEM_USED_THRESHOLD}" \
  --description "Committed memory sustained above ${MEM_USED_THRESHOLD}% - SRE Agent scenario 2" -o none || \
  echo "    (If this errored on syntax, create S2b in the portal using the KQL in response-plans/kql-queries.md)"

# --- Scenario 3: service stopped scheduled query alert ---
echo "==> Alert S3: W3SVC or DemoDbService entered stopped state"
az monitor scheduled-query create \
  -g "${RESOURCE_GROUP}" -n "${PREFIX}-s3-service-stopped" \
  --scopes "${LAW_ID}" --severity 1 \
  --window-size 5m --evaluation-frequency 5m \
  --action-groups "${AG_ID}" \
  --condition "count 'placeholder' > 0" \
  --condition-query placeholder="Event | where Source == 'Service Control Manager' and EventID == 7036 | where Computer == '${VM_NAME}' | where RenderedDescription has_any ('W3SVC','World Wide Web Publishing','Demo DB Service') and RenderedDescription has 'stopped state'" \
  --description "IIS/DB service stopped - SRE Agent scenario 3" -o none || \
  echo "    (If this errored on syntax, create S3 in the portal using the KQL in response-plans/kql-queries.md)"

# --- Scenario 1: VM powered off (Activity Log alert) ---
echo "==> Alert S1: VM deallocate/power-off activity"
az monitor activity-log alert create \
  -g "${RESOURCE_GROUP}" -n "${PREFIX}-s1-vm-stopped" \
  --scope "${VM_ID}" \
  --condition category=Administrative and operationName=Microsoft.Compute/virtualMachines/deallocate/action \
  --action-group "${AG_ID}" \
  --description "VM powered off - SRE Agent scenario 1 (time-window logic handled in the runbook)" -o none || \
  echo "    (Activity-log alert syntax varies by CLI version; see response-plans/kql-queries.md)"

echo ""
echo "Monitoring deployed. Action group: ${AG_ID}"
echo "IMPORTANT: after the SRE Agent exists, connect Azure Monitor as its"
echo "incident platform (Builder > Incident platform) so these alerts reach it."
echo "Next: ./scripts/03-assign-rbac.sh"
