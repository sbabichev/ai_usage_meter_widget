$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Provider hint and status helpers" {
    It "projects used percent at reset from elapsed pace" {
        $limit = [pscustomobject]@{
            used_percent = 40
            window_minutes = 100
            resets_at = [DateTimeOffset]::Now.AddMinutes(50).ToUnixTimeSeconds()
        }

        $projection = Get-UsageProjection $limit

        $projection.Ready | Should Be $true
        $projection.ProjectedUsedPercent | Should Be 80
    }

    It "marks exhausted usage as wait with an hourglass countdown" {
        $limit = [pscustomobject]@{
            used_percent = 100
            window_minutes = 1440
            resets_at = [DateTimeOffset]::Now.AddHours(23).AddMinutes(24).ToUnixTimeSeconds()
        }

        $status = Get-UsageStatus $limit

        $status.Label | Should Be "WAIT"
        $status.ChipText | Should Match "WAIT$"
        $status.CountdownText.StartsWith(("{0} " -f (Get-UiGlyph "hourglass"))) | Should Be $true
    }

    It "marks near-reset usage as reset soon" {
        $limit = [pscustomobject]@{
            used_percent = 41
            window_minutes = 300
            resets_at = [DateTimeOffset]::Now.AddMinutes(20).ToUnixTimeSeconds()
        }

        $status = Get-UsageStatus $limit

        $status.Label | Should Be "RESET SOON"
        $status.ChipText | Should Be ("{0} RESET SOON" -f (Get-UiGlyph "reset"))
    }

    It "builds a projection hint for grok from the weekly window" {
        $usage = [pscustomobject]@{
            ok = $true
            isStale = $false
            primary = [pscustomobject]@{
                used_percent = 20
                window_minutes = 100
                resets_at = [DateTimeOffset]::Now.AddMinutes(50).ToUnixTimeSeconds()
            }
            secondary = $null
        }

        $hint = Get-ProviderHint "grok" $usage

        $hint.Text | Should Be "Pace: OK - projected 40% used at reset"
    }

    It "surfaces stale telemetry in the pace hint" {
        $usage = [pscustomobject]@{
            ok = $true
            isStale = $true
            primary = [pscustomobject]@{
                used_percent = 86
                window_minutes = 100
                resets_at = [DateTimeOffset]::Now.AddMinutes(50).ToUnixTimeSeconds()
            }
            secondary = $null
        }

        $hint = Get-ProviderHint "grok" $usage

        $hint.Text.Contains("telemetry may be stale") | Should Be $true
    }
}
