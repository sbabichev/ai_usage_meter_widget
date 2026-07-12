[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $env:LOCALAPPDATA "CodexUsageMeter\antigravity-quota.json")
)

$ErrorActionPreference = "Stop"

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $quota = $payload.quota
    if ($null -eq $quota) { exit 0 }

    $snapshot = [pscustomobject]@{
        schema_version = 1
        captured_at = (Get-Date).ToUniversalTime().ToString("o")
        plan_tier = $payload.plan_tier
        model = $payload.model.display_name
        pools = [ordered]@{}
    }
    foreach ($poolName in @("gemini", "3p")) {
        $fiveHour = $quota."$poolName-5h"
        $weekly = $quota."$poolName-weekly"
        if ($fiveHour -and $weekly) {
            $snapshot.pools[$poolName] = [pscustomobject]@{
                current = [pscustomobject]@{ remaining_fraction = $fiveHour.remaining_fraction; resets_at = $fiveHour.reset_time }
                weekly = [pscustomobject]@{ remaining_fraction = $weekly.remaining_fraction; resets_at = $weekly.reset_time }
            }
        }
    }
    if ($snapshot.pools.Count -eq 0) { exit 0 }

    $directory = Split-Path -Parent $OutputPath
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = "$OutputPath.$([guid]::NewGuid().ToString('N')).tmp"
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $OutputPath -Force
} catch {
    # Statusline failures must not reveal payload data or interrupt AGY.
}

exit 0
