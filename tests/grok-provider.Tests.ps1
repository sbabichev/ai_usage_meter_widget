$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Grok provider helpers" {
    It "keeps the fresher usage snapshot" {
        $olderUsage = [pscustomobject]@{
            ok = $true
            updated = [datetime]"2026-07-05T10:00:00Z"
            primary = [pscustomobject]@{
                used_percent = 44
            }
        }
        $newerUsage = [pscustomobject]@{
            ok = $true
            updated = [datetime]"2026-07-05T10:05:00Z"
            primary = [pscustomobject]@{
                used_percent = 12
            }
        }

        $selected = Get-NewerUsage $olderUsage $newerUsage

        $selected.primary.used_percent | Should Be 12
    }

    It "keeps the previous plan when the api response omits tier metadata" {
        $response = [pscustomobject]@{
            config = [pscustomobject]@{
                creditUsagePercent = 61
                currentPeriod = [pscustomobject]@{
                    type = "USAGE_PERIOD_TYPE_WEEKLY"
                    start = "2026-06-30T06:58:46.185671+00:00"
                    end = "2026-07-07T06:58:46.185671+00:00"
                }
            }
        }
        $existingUsage = [pscustomobject]@{
            plan = "X Premium"
        }

        $usage = Convert-GrokBillingApiResponse $response $existingUsage

        $usage.plan | Should Be "X Premium"
        $usage.source | Should Be "api"
        $usage.primary.used_percent | Should Be 61
    }
}
