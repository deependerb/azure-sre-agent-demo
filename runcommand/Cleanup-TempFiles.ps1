<#
  Scenario 4 - Windows temp cleanup / free disk space.
  Deletes files under the Windows temp locations and reports space reclaimed.
  Runs INSIDE the guest via run-command (NOT an Azure resource delete, so it
  does not hit the agent's 'az delete/remove' guardrail).

  Invoked in-guest by SRE Agent via:
    az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript \
      --scripts @runcommand/Cleanup-TempFiles.ps1 \
      --parameters OlderThanDays=1

  SAFETY: only touches well-known temp folders and files older than N days.
#>
param(
    [int]$OlderThanDays = 1
)

$ErrorActionPreference = 'Continue'
$cutoff = (Get-Date).AddDays(-$OlderThanDays)
$targets = @(
    "$env:WINDIR\Temp",
    "$env:TEMP",
    "C:\Users\*\AppData\Local\Temp"
)

function Get-FreeGB { (Get-PSDrive C).Free / 1GB }
$before = Get-FreeGB
$deleted = 0

foreach ($path in $targets) {
    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            try { Remove-Item $_.FullName -Force -ErrorAction Stop; $deleted++ }
            catch { }  # skip locked/in-use files
        }
}

# Optional: run the built-in Disk Cleanup silently if configured
# cleanmgr /sagerun:1 | Out-Null

$after = Get-FreeGB
Write-Output ("RESULT=Deleted {0} files; FreeBefore={1:N2}GB FreeAfter={2:N2}GB Reclaimed={3:N2}GB" -f `
    $deleted, $before, $after, ($after - $before))
