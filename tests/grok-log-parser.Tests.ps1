$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Grok billing log parsing" {
    It "converts a weekly billing record into the shared usage shape" {
        $record = [pscustomobject]@{
            ts = "2026-07-05T15:27:27.816Z"
            msg = "billing: fetched credits config"
            ctx = [pscustomobject]@{
                subscriptionTier = "X Premium"
                config = [pscustomobject]@{
                    creditUsagePercent = 100
                    currentPeriod = [pscustomobject]@{
                        type = "USAGE_PERIOD_TYPE_WEEKLY"
                        start = "2026-06-30T06:58:46.185671+00:00"
                        end = "2026-07-07T06:58:46.185671+00:00"
                    }
                }
            }
        }

        $usage = Convert-GrokBillingLogRecord $record

        $usage.ok | Should Be $true
        $usage.plan | Should Be "X Premium"
        $usage.primary.used_percent | Should Be 100
        $usage.secondary | Should Be $null
        $usage.primary.window_minutes -gt 0 | Should Be $true
    }

    It "reads the newest valid billing line even with malformed trailing lines" {
        $tempPath = Join-Path $env:TEMP ("grok-log-test-{0}.jsonl" -f [guid]::NewGuid().ToString("N"))
        @(
            '{"ts":"2026-07-05T15:20:00.000Z","msg":"billing: fetched credits config","ctx":{"subscriptionTier":"X Premium","config":{"creditUsagePercent":36,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-06-30T06:58:46.185671+00:00","end":"2026-07-07T06:58:46.185671+00:00"}}}}',
            'not-json-at-all',
            '{"ts":"2026-07-05T15:25:00.000Z","msg":"other message","ctx":{}}',
            '{"ts":"2026-07-05T15:30:00.000Z","msg":"billing: fetched credits config","ctx":{"subscriptionTier":"X Premium","config":{"creditUsagePercent":77,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-06-30T06:58:46.185671+00:00","end":"2026-07-07T06:58:46.185671+00:00"}}}}'
        ) | Set-Content -Path $tempPath -Encoding UTF8

        try {
            $usage = Read-GrokBillingUsageFromLog $tempPath
            $usage.primary.used_percent | Should Be 77
        } finally {
            Remove-Item $tempPath -ErrorAction SilentlyContinue
        }
    }
}
