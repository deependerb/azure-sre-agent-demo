#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 99 - Tear down all demo infrastructure (deletes the resource group).
# Does NOT delete the SRE Agent resource - remove that from the portal.
# ---------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/00-variables.sh"

read -r -p "Delete resource group '${RESOURCE_GROUP}' and ALL its resources? (yes/no) " ans
if [[ "${ans}" == "yes" ]]; then
  echo "==> Deleting ${RESOURCE_GROUP} ..."
  az group delete -n "${RESOURCE_GROUP}" --yes --no-wait
  echo "Deletion started (running in background)."
  echo "Reminder: delete the SRE Agent resource + its role assignments from the portal."
else
  echo "Aborted."
fi
