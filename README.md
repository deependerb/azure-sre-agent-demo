# Azure SRE Agent — 4-Scenario Demo Kit

A ready-to-run demo that provisions a Windows VM with monitoring, then configures
**Azure SRE Agent** to detect and **act** on four operational scenarios:

| # | Scenario | Trigger | Agent action |
|---|----------|---------|--------------|
| 1 | Start VM if it shut down between **5 PM–7 AM** | VM power-off alert / 15-min scheduled sweep | `az vm start` (only inside the window) |
| 2 | **CPU/memory > 95% for 15 min** → restart causing service | Metric + guest-metric alert | run-command → restart offending Windows service |
| 3 | **Auto service (IIS/DB) stopped** → restart 3×, then alert | Service Control Manager event alert | run-command watchdog (3 retries) → escalate |
| 4 | **Delete Windows temp files** / free disk | Daily schedule (or low-disk alert) | run-command PowerShell cleanup |

> Design reality: the SRE Agent has **no pre-built scenario templates**. Each
> scenario is built from Azure Monitor triggers + an SRE Agent **skill/runbook**
> + **response plan/scheduled task** + scoped **RBAC**. This kit provides all of
> those. See `response-plans/configuration-guide.md` for the portal steps that
> can't be scripted.

## What gets deployed
- Resource group, VNet/NSG (RDP locked to your IP), **Windows Server 2022 VM**
- **Azure Monitor Agent** + a **Data Collection Rule** (guest CPU/mem + service events)
- IIS (`W3SVC`) and a stand-in `DemoDbService` to act on
- Alerts for scenarios 1–3, plus an action group to route into the agent

## Prerequisites
- Azure CLI (`az`) logged in: `az login`
- `envsubst`, `curl` (usually preinstalled on Linux/macOS)
- Rights to create resources + assign roles in the target subscription
- Access to create an **SRE Agent** in the portal (GA)

## Deploy — step by step
```bash
git clone https://github.com/<your-user>/sre-agent-demo.git
cd sre-agent-demo
cp .env.example .env          # edit SUBSCRIPTION_ID, LOCATION, etc.
read -s -p "VM admin password: " VM_ADMIN_PASSWORD && export VM_ADMIN_PASSWORD && echo

chmod +x scripts/*.sh
./scripts/01-deploy-infra.sh        # VM + AMA + IIS + demo DB service
./scripts/02-deploy-monitoring.sh   # DCR + alerts (S1-S3) + action group
```

### Create + wire the SRE Agent
The agent is an ARM resource (`Microsoft.App/agents`, api `2025-05-01-preview`).
Prerequisites (managed identity + App Insights) and an attempted create are
scripted; the create body uses a preview-only `agentAppEnvelope` schema that
isn't publicly documented, so the portal wizard is the reliable path for that
single step.

1. Run the prereqs + attempt automated create:
   ```bash
   ./scripts/05-create-agent.sh
   ```
   If it reports the preview-API 400, create the agent once at
   **https://sre.azure.com** (subscription/RG/name/region + model = Anthropic),
   which takes 2-5 min.
2. Copy the agent's **managed-identity object id** into `.env` as
   `SRE_AGENT_MI_PRINCIPAL_ID`, then grant RBAC:
   ```bash
   ./scripts/03-assign-rbac.sh       # VM Contributor + Log Analytics Reader (RG scope)
   ```
3. Follow **`response-plans/configuration-guide.md`** to:
   - connect **Azure Monitor** as the incident platform,
   - upload the **4 skills** (`skills/*/SKILL.md`) + their `runcommand/*.ps1`,
   - create the **response plans** (S1–S3) and **scheduled tasks** (S1, S4),
   - set **run modes** per scenario.

## Run the demo
Trigger each scenario and watch the agent investigate + act:
```bash
./scripts/04-simulate.sh 1   # deallocate VM        -> agent starts it (if in window)
./scripts/04-simulate.sh 2   # peg CPU ~16 min      -> agent restarts offending service
./scripts/04-simulate.sh 3   # stop IIS + DB svc    -> watchdog restarts / escalates
./scripts/04-simulate.sh 4   # seed junk temp files -> cleanup task reclaims space
```
Show the audience: the incident thread, the proposed/executed `az` action, the
verification step, and the audit event (`AgentAzCliExecution`) in Application Insights.

## Tear down
```bash
./scripts/99-cleanup.sh      # deletes the resource group
# then delete the SRE Agent resource + role assignments from the portal
```

## Key guardrails to mention in the demo
- Agent **won't run `az delete/remove`** on Azure resources, and **blocks
  `az keyvault`**. Scenario 4 deletes *files inside the guest* via run-command,
  a permitted path — call this out explicitly.
- Agent starts at **Reader**; it only acts after you grant RBAC (script 03),
  scoped to the resource group (least privilege).
- **ReadOnly management locks** block writes regardless of run mode.

## File map
```
sre-agent-demo/
  .env.example                       # copy to .env and edit
  scripts/
    00-variables.sh                  # shared vars + guards (sourced)
    01-deploy-infra.sh               # VM, AMA, IIS, demo DB service
    02-deploy-monitoring.sh          # DCR + alerts + action group
    03-assign-rbac.sh                # RBAC for the agent's managed identity
    04-simulate.sh <1|2|3|4>         # trigger each scenario
    99-cleanup.sh                    # tear down
  dcr/guest-dcr.template.json        # perf counters + service events
  runcommand/
    Restart-CausingService.ps1       # scenario 2 action
    Service-Watchdog.ps1             # scenario 3 action (3 retries + escalate)
    Cleanup-TempFiles.ps1            # scenario 4 action
  skills/
    scenario1-vm-autostart/SKILL.md
    scenario2-high-cpu-restart/SKILL.md
    scenario3-service-watchdog/SKILL.md
    scenario4-temp-cleanup/SKILL.md
  response-plans/
    configuration-guide.md           # portal steps for response plans/tasks/run modes
    kql-queries.md                   # KQL + alert fallbacks
```

## Security & secrets
- `.env` (subscription id, resource names) and any `*.env` are **git-ignored**.
  Only `.env.example` is committed — it contains no secrets.
- The VM admin password is **never** written to a file; you export it into the
  shell at deploy time only.
- Do not commit RBAC principal ids or credentials.

## License
MIT — see [LICENSE](LICENSE).

