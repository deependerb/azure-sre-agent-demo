#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 03 - Grant the SRE Agent's managed identity permission to act
#
# The SRE Agent runs as a managed identity created when you provision the
# agent in the portal (Builder). By default it has Reader and CANNOT act.
# This script grants the roles required for the 4 demo scenarios, scoped
# to the demo resource group only (least privilege for a demo).
#
# Roles granted:
#   * Virtual Machine Contributor  -> start/restart/deallocate the VM (S1, S2)
#   * Virtual Machine Contributor also allows run-command invoke used for
#     in-guest actions (restart Windows service, cleanup temp) (S2, S3, S4)
#   * Log Analytics Reader         -> query signals during investigation
#
# Prereq: set SRE_AGENT_MI_PRINCIPAL_ID in .env (from the portal).
# ---------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/00-variables.sh"
require SRE_AGENT_MI_PRINCIPAL_ID
require SRE_AGENT_RBAC_SCOPE

echo "==> Assigning Virtual Machine Contributor at ${SRE_AGENT_RBAC_SCOPE}"
az role assignment create \
  --assignee-object-id "${SRE_AGENT_MI_PRINCIPAL_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "Virtual Machine Contributor" \
  --scope "${SRE_AGENT_RBAC_SCOPE}" -o none

echo "==> Assigning Log Analytics Reader at ${SRE_AGENT_RBAC_SCOPE}"
az role assignment create \
  --assignee-object-id "${SRE_AGENT_MI_PRINCIPAL_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "Log Analytics Reader" \
  --scope "${SRE_AGENT_RBAC_SCOPE}" -o none

echo ""
echo "RBAC assigned. Remember the built-in guardrails:"
echo "  * The agent will NOT run 'az ... delete/remove' on Azure resources."
echo "  * The agent blocks all 'az keyvault' commands."
echo "  * ReadOnly management locks still block writes regardless of role."
echo "Scenario 4 (file cleanup) runs INSIDE the guest via run-command PowerShell,"
echo "which is a separate path from resource deletes - see the scenario 4 skill."
