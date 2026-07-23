# KQL queries + alert definitions (portal fallback)

If any alert in `scripts/02-deploy-monitoring.sh` fails due to CLI syntax
differences, create it in the portal (Monitor → Alerts → Create) using these.

## S2b — committed memory > 95% for 15 min (scheduled query, scope = Log Analytics)
```kusto
Perf
| where ObjectName == "Memory" and CounterName == "% Committed Bytes In Use"
| where Computer == "<VM_NAME>"
| summarize avgUsed = avg(CounterValue) by bin(TimeGenerated, 5m)
| where avgUsed > 95
```
Window 15 min, frequency 5 min, threshold: count > 0, severity 2.

## S3 — auto-start service entered stopped state (scheduled query)
```kusto
Event
| where Source == "Service Control Manager" and EventID == 7036
| where Computer == "<VM_NAME>"
| where RenderedDescription has_any ("World Wide Web Publishing", "W3SVC", "Demo DB Service")
| where RenderedDescription has "stopped state"
```
Window 5 min, frequency 5 min, threshold: count > 0, severity 1.

## S1 — VM powered off (Activity Log alert)
- Signal type: Activity Log
- Category: Administrative
- Operation: `Microsoft.Compute/virtualMachines/deallocate/action`
  (add `.../powerOff/action` as a second alert if you shut down from the guest)
- Scope: the VM. Action group: `<prefix>-ag-sre`.

## S2a — Percentage CPU > 95% for 15 min (platform metric alert)
- Signal: Percentage CPU, Average, threshold 95, aggregation granularity 15 min,
  evaluation frequency 5 min, severity 2.
