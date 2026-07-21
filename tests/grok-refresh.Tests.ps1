$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Grok refresh helpers" {
    It "replaces the previous snapshot when api refresh succeeds" {
        $existingUsage = [pscustomobject]@{
            ok = $true
            plan = "X Premium"
            primary = [pscustomobject]@{
                used_percent = 88
            }
        }
        $freshUsage = [pscustomobject]@{
            ok = $true
            plan = "X Premium"
            primary = [pscustomobject]@{
                used_percent = 21
            }
        }

        $result = Invoke-GrokRefreshCore { $freshUsage } $existingUsage

        $result.Status.state | Should Be "success"
        $result.Error | Should Be $null
        $result.Usage.primary.used_percent | Should Be 21
    }

    It "preserves the previous snapshot when api refresh fails" {
        $existingUsage = [pscustomobject]@{
            ok = $true
            plan = "X Premium"
            primary = [pscustomobject]@{
                used_percent = 73
            }
        }

        $result = Invoke-GrokRefreshCore { throw "auth missing" } $existingUsage

        $result.Status.state | Should Be "error"
        $result.Error | Should Be "auth missing"
        $result.Usage.primary.used_percent | Should Be 73
    }

    It "parses bearer auth and user id from the cli auth file" {
        $tempPath = Join-Path $env:TEMP ("grok-auth-test-{0}.json" -f [guid]::NewGuid().ToString("N"))
        @'
{
  "https://auth.x.ai::example": {
    "key": "token-value",
    "user_id": "user-123"
  }
}
'@ | Set-Content -Path $tempPath -Encoding UTF8

        try {
            $auth = Resolve-GrokAuthContext $tempPath

            $auth.Key | Should Be "token-value"
            $auth.UserId | Should Be "user-123"
        } finally {
            Remove-Item $tempPath -ErrorAction SilentlyContinue
        }
    }

    It "throttles automatic api refresh by refreshSeconds" {
        $settings = [pscustomobject]@{
            RefreshSeconds = 300
        }
        $script:GrokRemoteState.LastFetch = $null
        (Test-GrokApiRefreshDue $settings) | Should Be $true

        $script:GrokRemoteState.LastFetch = Get-Date
        (Test-GrokApiRefreshDue $settings) | Should Be $false

        $script:GrokRemoteState.LastFetch = (Get-Date).AddSeconds(-301)
        (Test-GrokApiRefreshDue $settings) | Should Be $true
    }

    It "auto refresh preserves existing usage when the live fetch fails" {
        $existingUsage = [pscustomobject]@{
            ok = $true
            isStale = $true
            primary = [pscustomobject]@{
                used_percent = 12
            }
        }
        $settings = [pscustomobject]@{
            RefreshSeconds = 1
        }
        $script:GrokRemoteState.LastFetch = $null

        $result = Invoke-GrokAutoBillingRefresh $existingUsage $settings { throw "auth missing" }

        $result.Attempted | Should Be $true
        $result.Error | Should Be "auth missing"
        $result.Usage.primary.used_percent | Should Be 12
        $script:GrokRemoteState.LastFetch | Should Not Be $null
    }

    It "auto refresh replaces stale usage when the live fetch succeeds" {
        $existingUsage = [pscustomobject]@{
            ok = $true
            isStale = $true
            primary = [pscustomobject]@{
                used_percent = 88
            }
        }
        $settings = [pscustomobject]@{
            RefreshSeconds = 1
        }
        $script:GrokRemoteState.LastFetch = $null
        $freshUsage = [pscustomobject]@{
            ok = $true
            primary = [pscustomobject]@{
                used_percent = 3
            }
        }

        $result = Invoke-GrokAutoBillingRefresh $existingUsage $settings { $freshUsage }

        $result.Attempted | Should Be $true
        $result.Error | Should Be $null
        $result.Usage.primary.used_percent | Should Be 3
    }
}
