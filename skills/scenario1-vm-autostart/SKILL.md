---
name: vm-autostart-nightly
description: Use when a VM is reported powered off/deallocated. Starts the VM only during the nightly window 17:00-07:00 local; otherwise notifies only.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

# Scenario 1 — Auto-start a VM if it shuts down between 5 PM and 7 AM

## When to use
An alert or investigation shows a target VM in a stopped/deallocated state.

## Time-window rule (hard requirement)
Only start the VM automatically when the **current local time is between 17:00
and 07:00**. Outside that window, DO NOT start it — post a notification and
create a work item for a human to review instead.

## Procedure
1. Confirm current power state:
   ```
   az vm get-instance-view -g <rg> -n <vm> \
     --query "instanceView.statuses[?starts_with(code,'PowerState')].code" -o tsv
   ```
2. If it is NOT `PowerState/running`, evaluate the time window.
   - If **inside 17:00–07:00**: start it.
     ```
     az vm start -g <rg> -n <vm>
     ```
   - If **outside** the window: notify + create work item, then stop.
3. Verify:
   ```
   az vm get-instance-view -g <rg> -n <vm> \
     --query "instanceView.statuses[?starts_with(code,'PowerState')].code" -o tsv
   ```
   Confirm `PowerState/running`. Report start time, who/what triggered it,
   and the verified state.

## Notes / guardrails
- `az vm start` is an allowed write command.
- For guaranteed enforcement of the window, this scenario is ALSO wired as a
  **scheduled task** that runs every 15 min from 17:00–07:00 and starts the VM
  if stopped. Prefer the scheduled task for reliability; use this runbook when
  the power-off alert fires between checks.
- Run mode recommendation: **Autonomous** for this response plan (unattended
  overnight), scoped to the demo resource group only.
