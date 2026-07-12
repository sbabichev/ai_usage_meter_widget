$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Antigravity quota provider" {
    It "converts AGY decimal remaining fractions into used percentages" {
        $snapshotPath = Join-Path $env:TEMP ("antigravity-quota-{0}.json" -f [guid]::NewGuid().ToString("N"))
        $originalConfigPath = $script:ConfigPath
        try {
            @'
{"schema_version":1,"captured_at":"2026-07-10T20:17:25Z","plan_tier":"Google AI Pro","pools":{"gemini":{"current":{"remaining_fraction":0.9684408,"resets_at":"2026-07-10T21:25:04Z"},"weekly":{"remaining_fraction":0.9947401,"resets_at":"2026-07-17T16:25:04Z"}}}}
'@ | Set-Content -LiteralPath $snapshotPath -Encoding UTF8
            $configPath = Join-Path $env:TEMP ("antigravity-config-{0}.json" -f [guid]::NewGuid().ToString("N"))
            ('{"antigravity":{"enabled":true,"pool":"gemini","snapshotPath":"' + ($snapshotPath -replace '\\', '\\') + '"}}') | Set-Content -LiteralPath $configPath -Encoding UTF8
            $script:ConfigPath = $configPath

            $result = Invoke-AntigravityLiveFetch

            $result.Status | Should Be "success"
            $result.Usage.primary.used_percent | Should Be 3.2
            $result.Usage.secondary.used_percent | Should Be 0.5
            $result.Usage.primary.resets_at | Should Be 1783718704
            $result.Usage.secondary.resets_at | Should Be 1784305504
            $result.Usage.primary.window_minutes | Should Be 300
            $result.Usage.secondary.window_minutes | Should Be 10080
        } finally {
            $script:ConfigPath = $originalConfigPath
            Remove-Item -LiteralPath $snapshotPath -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $configPath -ErrorAction SilentlyContinue
        }
    }

    It "reloads a newer local AGY snapshot on the next widget refresh" {
        $snapshotPath = Join-Path $env:TEMP ("antigravity-refresh-{0}.json" -f [guid]::NewGuid().ToString("N"))
        $originalConfigPath = $script:ConfigPath
        $originalUsage = $script:AntigravityRemoteState.Usage
        try {
            $configPath = Join-Path $env:TEMP ("antigravity-config-{0}.json" -f [guid]::NewGuid().ToString("N"))
            ('{"antigravity":{"enabled":true,"pool":"gemini","snapshotPath":"' + ($snapshotPath -replace '\\', '\\') + '"}}') | Set-Content -LiteralPath $configPath -Encoding UTF8
            $script:ConfigPath = $configPath
            $script:AntigravityRemoteState.Usage = $null
            @'
{"captured_at":"2026-07-10T20:00:00Z","pools":{"gemini":{"current":{"remaining_fraction":0.97},"weekly":{"remaining_fraction":0.99}}}}
'@ | Set-Content -LiteralPath $snapshotPath -Encoding UTF8
            (Get-AntigravityUsage).primary.used_percent | Should Be 3
            @'
{"captured_at":"2026-07-10T20:01:00Z","pools":{"gemini":{"current":{"remaining_fraction":0.88},"weekly":{"remaining_fraction":0.97}}}}
'@ | Set-Content -LiteralPath $snapshotPath -Encoding UTF8
            (Get-AntigravityUsage).primary.used_percent | Should Be 12
        } finally {
            $script:ConfigPath = $originalConfigPath
            $script:AntigravityRemoteState.Usage = $originalUsage
            Remove-Item -LiteralPath $snapshotPath -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $configPath -ErrorAction SilentlyContinue
        }
    }
}
