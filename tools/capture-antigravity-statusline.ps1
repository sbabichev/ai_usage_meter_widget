[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $env:LOCALAPPDATA "CodexUsageMeter\antigravity-statusline-shape.json")
)

$ErrorActionPreference = "Stop"

function Get-StatuslineShapeEntries($Value, [string]$Path = "$") {
    if ($null -eq $Value) {
        return @([pscustomobject]@{ path = $Path; type = "null" })
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [pscustomobject])) {
        return @([pscustomobject]@{ path = $Path; type = "array" })
    }

    if ($Value -isnot [pscustomobject]) {
        return @([pscustomobject]@{ path = $Path; type = $Value.GetType().Name })
    }

    $entries = @()
    foreach ($property in $Value.PSObject.Properties) {
        $propertyPath = "$Path.$($property.Name)"
        $entries += Get-StatuslineShapeEntries $property.Value $propertyPath
    }
    return $entries
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $payload = $raw | ConvertFrom-Json
    $shape = Get-StatuslineShapeEntries $payload | Where-Object {
        $_.path -match '(?i)(quota|credit|usage|remaining|reset|limit|model|tier)'
    } | Sort-Object path -Unique

    $directory = Split-Path -Parent $OutputPath
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    [pscustomobject]@{
        captured_at = (Get-Date).ToUniversalTime().ToString("o")
        candidates = @($shape)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
} catch {
    # This recorder intentionally emits no input, exception, or status text.
}

exit 0
