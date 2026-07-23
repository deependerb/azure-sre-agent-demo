# SRE Agent — portal configuration (response plans, scheduled tasks, run modes)

These steps are done in the **Azure portal → SRE Agent → Builder**. They are
UI-driven and cannot be scripted with `az`. Do them after infra + monitoring
are deployed and the agent's managed identity has RBAC (script 03).

## 0. Create the agent + connect environment
1. Portal → search **SRE Agent** → **Create**. Pick the demo subscription/RG.
   The wizard also creates App Insights, a Log Analytics workspace, and a
   **managed identity** — copy that identity's object id into `.env`
   (`SRE_AGENT_MI_PRINCIPAL_ID`) and run `scripts/03-assign-rbac.sh`.
2. **Builder → Incident platform** → choose **Azure Monitor** → Save.
   Repoint the demo action group (`<prefix>-ag-sre`) so its alerts reach the
   agent (Azure Monitor alerts flow to the agent once the platform is set).
3. **Builder → Skills** → create four skills, uploading the matching `SKILL.md`
   and attaching the tools `RunAzCliReadCommands` + `RunAzCliWriteCommands`.
   Also upload the corresponding `runcommand/*.ps1` as a supporting file.
   | Skill | File |
   |-------|------|
   | vm-autostart-nightly | skills/scenario1-vm-autostart/SKILL.md |
   | high-cpu-mem-restart | skills/scenario2-high-cpu-restart/SKILL.md |
   | service-watchdog | skills/scenario3-service-watchdog/SKILL.md |
   | temp-cleanup | skills/scenario4-temp-cleanup/SKILL.md |

## 1. Scenario 1 — VM auto-start (time window)
Two complementary pieces:
- **Scheduled task** (primary, reliable window enforcement):
  Builder → **Scheduled tasks** → New.
  - Schedule: every 15 minutes.
  - Instruction: *"If VM `<vm>` in RG `<rg>` is not running AND the current
    local time is between 17:00 and 07:00, start it with `az vm start` and
    verify PowerState=running. Outside that window, do nothing."*
- **Response plan** (reacts to the power-off alert between checks):
  Builder → **Incident response plans** → New.
  - Filter: alert name contains `s1-vm-stopped`.
  - Run mode: **Autonomous**.
  - Instruction: reference the `vm-autostart-nightly` skill.

## 2. Scenario 2 — high CPU/mem → restart service
Builder → **Incident response plans** → New.
- Filter: alert name contains `s2a-cpu-high` OR `s2b-mem-high`.
- Run mode: **Review** (demo) → later **Autonomous**.
- Instruction: *"Follow the `high-cpu-mem-restart` skill: confirm the sustained
  condition, run `Restart-CausingService.ps1` in-guest, verify utilization
  dropped, escalate if no service maps to the offender."*

## 3. Scenario 3 — service watchdog (3 retries, then alert)
Builder → **Incident response plans** → New.
- Filter: alert name contains `s3-service-stopped`.
- Run mode: **Autonomous** (fast recovery) + escalation notification ON.
- Instruction: *"Follow the `service-watchdog` skill: run `Service-Watchdog.ps1`
  with MaxAttempts=3 for the stopped service; if ACTION=ESCALATE, send an alert
  and open a work item."*

## 4. Scenario 4 — temp cleanup
Builder → **Scheduled tasks** → New.
- Schedule: daily 02:00.
- Run mode: **Review** (demo) → later **Autonomous**.
- Instruction: *"Follow the `temp-cleanup` skill: run `Cleanup-TempFiles.ps1`
  with OlderThanDays=1 on VM `<vm>`; report files deleted and GB reclaimed."*

## Run-mode summary
| Scenario | Recommended demo run mode | Why |
|----------|---------------------------|-----|
| 1 VM autostart | Autonomous | unattended overnight |
| 2 CPU/mem restart | Review → Autonomous | show approval, then trust |
| 3 service watchdog | Autonomous + alert | fast recovery, humans hear failures |
| 4 temp cleanup | Review → Autonomous | destructive; show human-in-the-loop |
