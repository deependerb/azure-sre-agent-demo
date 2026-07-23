---
name: service-watchdog
description: Use when an auto-start service (IIS/W3SVC or DemoDbService) is reported stopped. Restarts it up to 3 times and escalates with an alert if it does not recover.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

# Scenario 3 — Auto-service watchdog (restart 3× then alert)

## When to use
Alert `*-s3-service-stopped` fires (Service Control Manager event 7036/7031
shows W3SVC or DemoDbService entered the stopped state).

## Procedure
1. Identify which service stopped from the alert payload / Event log.
2. Run the watchdog in-guest (restarts up to 3 times, 10s apart):
   ```
   az vm run-command invoke -g <rg> -n <vm> \
     --command-id RunPowerShellScript \
     --scripts @Service-Watchdog.ps1 \
     --parameters ServiceName=W3SVC MaxAttempts=3
   ```
   For the DB service use `ServiceName=DemoDbService`.
3. Read the returned `RESULT=` and `ACTION=` lines:
   - `ACTION=NONE` → service recovered; write a short resolution note. Done.
   - `ACTION=ESCALATE` → the service did NOT recover after 3 attempts. Send an
     alert to the on-call channel and create a work item that includes the
     service name, the 3 failed attempts, and the last error message.

## Verify
```
az vm run-command invoke -g <rg> -n <vm> \
  --command-id RunPowerShellScript \
  --scripts "Get-Service W3SVC,DemoDbService | Select Name,Status | Format-Table"
```

## Guardrails / run mode
- Retry count (3) and escalation are enforced by the watchdog script + this
  runbook, not a built-in retry engine — validate in the demo.
- Run mode recommendation: **Autonomous** (fast recovery), with escalation
  notification always on so humans hear about non-recoverable failures.
