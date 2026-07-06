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
}
