#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 04 - Trigger the scenarios so the SRE Agent has something to react to.
# Usage: ./scripts/04-simulate.sh <1|2|3|4>
# ---------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/00-variables.sh"
CASE="${1:-}"

run_ps() {
  az vm run-command invoke -g "${RESOURCE_GROUP}" -n "${VM_NAME}" \
    --command-id RunPowerShellScript --scripts "$1" -o table
}

case "${CASE}" in
  1)
    echo "==> Scenario 1: stopping (deallocating) the VM to simulate a shutdown"
    az vm deallocate -g "${RESOURCE_GROUP}" -n "${VM_NAME}" -o none
    echo "VM deallocated. Activity-log alert should fire; agent/scheduled task starts it if within 17:00-07:00."
    ;;
  2)
    echo "==> Scenario 2: driving CPU to ~100% for ~16 minutes inside the guest"
    run_ps '
      $end=(Get-Date).AddMinutes(16)
      1..([Environment]::ProcessorCount) | ForEach-Object {
        Start-Job { param($e) while((Get-Date) -lt $e){ 1 } } -ArgumentList $end | Out-Null
      }
      "Started CPU load until $end"
    '
    echo "CPU alert (>95% / 15 min) should fire; agent restarts the offending service."
    ;;
  3)
    echo "==> Scenario 3: stopping W3SVC and DemoDbService to simulate service failure"
    run_ps 'Stop-Service -Name W3SVC -Force; Stop-Service -Name DemoDbService -Force; Get-Service W3SVC,DemoDbService | Format-Table Name,Status'
    echo "Service-stopped alert should fire; watchdog restarts up to 3x, else escalates."
    ;;
  4)
    echo "==> Scenario 4: seeding junk files in Windows temp to reclaim later"
    run_ps '
      1..200 | ForEach-Object {
        fsutil file createnew "$env:WINDIR\Temp\junk_$_.tmp" 5242880 | Out-Null
      }
      (Get-ChildItem "$env:WINDIR\Temp\junk_*.tmp").Count.ToString() + " junk files created"
    '
    echo "Run the temp-cleanup scheduled task (or invoke Cleanup-TempFiles.ps1) to reclaim."
    ;;
  *)
    echo "Usage: $0 <1|2|3|4>"; exit 1 ;;
esac
