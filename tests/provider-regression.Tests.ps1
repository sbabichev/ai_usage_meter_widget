$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Shared provider rendering regressions" {
    It "keeps Codex mapped to two limit windows" {
        $metadata = Get-ProviderMetadata "codex"
        $usage = [pscustomobject]@{
            ok = $true
            primary = [pscustomobject]@{
                used_percent = 11
            }
            secondary = [pscustomobject]@{
                used_percent = 33
            }
        }

        $windows = @(Get-ProviderUsageWindows $metadata $usage)

        $windows.Count | Should Be 2
        $windows[0].title | Should Be "Session"
        $windows[1].title | Should Be "Weekly"
    }

    It "keeps Grok mapped to a single weekly window" {
        $metadata = Get-ProviderMetadata "grok"
        $usage = [pscustomobject]@{
            ok = $true
            primary = [pscustomobject]@{
                used_percent = 55
            }
            secondary = $null
        }

        $windows = @(Get-ProviderUsageWindows $metadata $usage)

        $windows.Count | Should Be 1
        $windows[0].title | Should Be "Weekly"
    }

    It "uses a single weekly Codex limit when the session window is absent" {
        $metadata = Get-ProviderMetadata "codex"
        $usage = [pscustomobject]@{
            ok = $true
            primary = [pscustomobject]@{
                used_percent = 8
                window_minutes = 10080
                resets_at = 1784487810
            }
            secondary = $null
        }

        $windows = @(Get-ProviderUsageWindows $metadata $usage)

        $windows.Count | Should Be 1
        $windows[0].title | Should Be "Weekly"
    }

    It "accepts current Codex telemetry with only the weekly limit" {
        $limits = [pscustomobject]@{
            limit_id = "codex"
            primary = [pscustomobject]@{
                used_percent = 8
                window_minutes = 10080
                resets_at = 1784487810
            }
            secondary = $null
        }

        (Test-UsableCodexRateLimits $limits) | Should Be $true
    }
}
