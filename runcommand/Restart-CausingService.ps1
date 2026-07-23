<#
  Scenario 2 - Restart the service causing sustained high CPU/memory.
  Invoked in-guest by SRE Agent via:
    az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript \
      --scripts @runcommand/Restart-CausingService.ps1

  Strategy: find the top resource-consuming process, map it to a Windows
  service if one owns it, and restart that service. Falls back to reporting
  the offending process so the agent can decide/escalate.
#>
param(
    [double]$CpuMemThresholdPercent = 95
)

$ErrorActionPreference = 'Stop'

# Top process by CPU time and by working set (memory)
$topCpu = Get-Process | Sort-Object CPU -Descending | Select-Object -First 1
$topMem = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 1

Write-Output "TopCPUProcess=$($topCpu.ProcessName) (PID $($topCpu.Id))"
Write-Output "TopMemProcess=$($topMem.ProcessName) (PID $($topMem.Id)) WS=$([math]::Round($topMem.WorkingSet64/1MB))MB"

# Try to find a service whose host process is the top consumer
$targetPid = $topMem.Id
$svc = Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -eq $targetPid -and $_.State -eq 'Running' } | Select-Object -First 1

if ($svc) {
    Write-Output "Restarting service '$($svc.Name)' owning PID $targetPid ..."
    Restart-Service -Name $svc.Name -Force
    Start-Sleep -Seconds 5
    $after = Get-Service -Name $svc.Name
    Write-Output "RESULT=Restarted service $($svc.Name); Status=$($after.Status)"
}
else {
    # Common demo case: IIS app pool / w3wp under W3SVC
    if ($topMem.ProcessName -in @('w3wp','iisexpress')) {
        Write-Output "Offender is an IIS worker; restarting W3SVC ..."
        Restart-Service -Name W3SVC -Force
        Write-Output "RESULT=Restarted W3SVC; Status=$((Get-Service W3SVC).Status)"
    }
    else {
        Write-Output "RESULT=NoServiceMapped; offender=$($topMem.ProcessName); action=ESCALATE"
    }
}
