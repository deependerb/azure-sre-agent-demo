---
name: high-cpu-mem-restart
description: Use when CPU or committed memory stays above 95% for 15 minutes on the demo VM. Identifies the offending service and restarts it in-guest.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

# Scenario 2 — Restart the causing service on sustained high CPU/memory

## When to use
Alert `*-s2a-cpu-high` (Percentage CPU > 95% for 15 min) or `*-s2b-mem-high`
(committed memory > 95% for 15 min) fires for the demo VM.

## Investigate first
1. Confirm the sustained condition from metrics (do not act on a brief spike):
   ```
   az monitor metrics list --resource <vm-id> --metric "Percentage CPU" \
     --interval PT5M --aggregation Average
   ```
2. Identify the offending process/service inside the guest by running
   `runcommand/Restart-CausingService.ps1` via run-command.

## Act — restart the offending service (in-guest)
```
az vm run-command invoke -g <rg> -n <vm> \
  --command-id RunPowerShellScript \
  --scripts @Restart-CausingService.ps1
```
The script maps the top consumer to its owning Windows service and restarts it
(special-cases IIS `w3wp` -> `W3SVC`). Read the `RESULT=` line it returns.

## Verify
- Re-check CPU/memory after ~3–5 minutes; confirm it dropped below threshold.
- If `RESULT=NoServiceMapped ... action=ESCALATE`, do NOT force a restart —
  create a work item and notify the on-call channel with the offending
  process name.

## Guardrails / run mode
- Uses run-command write path (allowed). No resource deletion involved.
- Run mode recommendation: **Review** during the demo (approve the restart),
  switch to **Autonomous** once the pattern is trusted.
