#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 01 - Deploy demo infrastructure
#   * Resource group
#   * Log Analytics workspace
#   * VNet / subnet / NSG (RDP restricted to your IP)
#   * Windows Server 2022 VM
#   * Azure Monitor Agent (AMA) + VM Insights (guest CPU/mem/service signals)
#   * IIS + a dummy "DemoDbService" so scenarios 2 & 3 have something to act on
# ---------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/00-variables.sh"

require VM_NAME
require VM_ADMIN_USERNAME
require VM_ADMIN_PASSWORD   # exported in your shell, never stored in .env

echo "==> Creating resource group"
az group create -n "${RESOURCE_GROUP}" -l "${LOCATION}" -o none

echo "==> Creating Log Analytics workspace"
az monitor log-analytics workspace create \
  -g "${RESOURCE_GROUP}" -n "${LAW_NAME}" -l "${LOCATION}" -o none
LAW_ID=$(az monitor log-analytics workspace show \
  -g "${RESOURCE_GROUP}" -n "${LAW_NAME}" --query id -o tsv)

echo "==> Creating network (NSG allows RDP only from your current public IP)"
MY_IP=$(curl -s https://api.ipify.org || echo "")
az network nsg create -g "${RESOURCE_GROUP}" -n "${NSG_NAME}" -l "${LOCATION}" -o none
if [[ -n "${MY_IP}" ]]; then
  az network nsg rule create -g "${RESOURCE_GROUP}" --nsg-name "${NSG_NAME}" \
    -n allow-rdp --priority 1000 --access Allow --direction Inbound \
    --protocol Tcp --destination-port-ranges 3389 \
    --source-address-prefixes "${MY_IP}/32" -o none
  echo "    RDP allowed from ${MY_IP}/32"
else
  echo "    WARNING: could not detect public IP; no RDP rule added."
fi
az network vnet create -g "${RESOURCE_GROUP}" -n "${VNET_NAME}" -l "${LOCATION}" \
  --address-prefixes 10.20.0.0/16 \
  --subnet-name "${SUBNET_NAME}" --subnet-prefixes 10.20.1.0/24 -o none

echo "==> Creating Windows VM ${VM_NAME}"
az vm create \
  -g "${RESOURCE_GROUP}" -n "${VM_NAME}" -l "${LOCATION}" \
  --image "${VM_IMAGE}" --size "${VM_SIZE}" \
  --admin-username "${VM_ADMIN_USERNAME}" --admin-password "${VM_ADMIN_PASSWORD}" \
  --vnet-name "${VNET_NAME}" --subnet "${SUBNET_NAME}" --nsg "${NSG_NAME}" \
  --public-ip-sku Standard --nic-delete-option Delete --os-disk-delete-option Delete \
  -o none
VM_ID=$(az vm show -g "${RESOURCE_GROUP}" -n "${VM_NAME}" --query id -o tsv)

echo "==> Installing Azure Monitor Agent extension"
az vm extension set \
  -g "${RESOURCE_GROUP}" --vm-name "${VM_NAME}" \
  --name AzureMonitorWindowsAgent --publisher Microsoft.Azure.Monitor \
  --enable-auto-upgrade true -o none

echo "==> Configuring the guest: install IIS + create a demo DB service"
# IIS gives us the W3SVC service. New-Service creates a stand-in "DemoDbService"
# (a paused cmd loop) so scenario 3 has a second auto-start service to watch.
az vm run-command invoke \
  -g "${RESOURCE_GROUP}" -n "${VM_NAME}" \
  --command-id RunPowerShellScript --scripts '
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    Set-Service -Name W3SVC -StartupType Automatic
    if (-not (Get-Service -Name DemoDbService -ErrorAction SilentlyContinue)) {
      New-Service -Name DemoDbService -DisplayName "Demo DB Service" `
        -BinaryPathName "C:\Windows\System32\cmd.exe /c ping -t localhost" `
        -StartupType Automatic | Out-Null
      Start-Service -Name DemoDbService
    }
    "W3SVC="   + (Get-Service W3SVC).Status
    "DemoDb="  + (Get-Service DemoDbService).Status
  ' -o table

echo ""
echo "Infra deployed."
echo "  VM resource id: ${VM_ID}"
echo "  Log Analytics : ${LAW_ID}"
echo "Next: ./scripts/02-deploy-monitoring.sh"
