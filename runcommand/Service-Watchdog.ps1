<#
  Scenario 3 - Auto-start service watchdog.
  Restarts a stopped service up to N times; emits a clear success/failure
  marker the SRE Agent uses to decide whether to escalate (alert).

  Invoked in-guest by SRE Agent via:
    az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript \
      --scripts @runcommand/Service-Watchdog.ps1 \
      --parameters ServiceName=W3SVC MaxAttempts=3
#>
param(
    [string[]]$ServiceName = @('W3SVC','DemoDbService'),
    [int]$MaxAttempts = 3,
    [int]$DelaySeconds = 10
)

$ErrorActionPreference = 'Continue'
$overall = @()

foreach ($name in $ServiceName) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) { $overall += "MISSING:$name"; continue }
    if ($svc.Status -eq 'Running') { $overall += "OK:$name"; continue }

    $recovered = $false
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Write-Output "Attempt $i/$MaxAttempts to start '$name'..."
        try { Start-Service -Name $name -ErrorAction Stop } catch { Write-Output "  start failed: $($_.Exception.Message)" }
        Start-Sleep -Seconds $DelaySeconds
        if ((Get-Service -Name $name).Status -eq 'Running') {
            Write-Output "  '$name' is now Running."
            $recovered = $true
            break
        }
    }
    if ($recovered) { $overall += "RECOVERED:$name" } else { $overall += "FAILED:$name" }
}

$result = $overall -join '; '
Write-Output "RESULT=$result"

# Non-zero-style marker for the agent: if anything FAILED, signal escalation.
if ($result -match 'FAILED:') {
    Write-Output "ACTION=ESCALATE - one or more services did not recover after $MaxAttempts attempts. Send alert."
} else {
    Write-Output "ACTION=NONE - all watched services healthy."
}
