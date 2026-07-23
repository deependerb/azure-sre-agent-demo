---
name: temp-cleanup
description: Use to reclaim disk space by clearing Windows temp folders. Runs on a schedule or when a low-disk-space alert fires. Runs in-guest via PowerShell, not an Azure resource delete.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

# Scenario 4 — Clean up Windows temp files / free disk space

## Important design note (read first)
The SRE Agent **blocks `az ... delete` / `remove` on Azure resources** by
design. Deleting *files inside the guest OS* is a different path: it runs as a
PowerShell `Remove-Item` through `az vm run-command`, which is permitted. This
scenario is best driven as a **scheduled task** (housekeeping), not an incident.

## When to use
- On a schedule (e.g., daily 02:00), OR
- When a low-disk-space alert fires on the VM's OS drive.

## Procedure
1. (Optional) Check free space before:
   ```
   az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript \
     --scripts "[math]::Round((Get-PSDrive C).Free/1GB,2)"
   ```
2. Run the cleanup (files older than 1 day in Windows temp locations):
   ```
   az vm run-command invoke -g <rg> -n <vm> \
     --command-id RunPowerShellScript \
     --scripts @Cleanup-TempFiles.ps1 \
     --parameters OlderThanDays=1
   ```
3. Read the `RESULT=` line: files deleted + GB reclaimed. Report it.

## Guardrails / run mode
- Only well-known temp paths are touched; locked/in-use files are skipped.
- Run mode recommendation: **Review** for the demo (approve the cleanup) so the
  audience sees the human-in-the-loop step given this is a destructive action;
  move to **Autonomous** on a schedule once trusted.
