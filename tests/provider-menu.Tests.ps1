$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Provider visibility guard" {
    It "refuses to hide the last visible enabled provider" {
        $enabledMap = [ordered]@{
            codex = $true
            minimax = $false
            grok = $true
        }
        $visibilityMap = [ordered]@{
            codex = $true
            minimax = $false
            grok = $false
        }

        (Test-CanHideProvider "codex" $enabledMap $visibilityMap) | Should Be $false
    }

    It "allows hiding a provider when another enabled provider stays visible" {
        $enabledMap = [ordered]@{
            codex = $true
            minimax = $false
            grok = $true
        }
        $visibilityMap = [ordered]@{
            codex = $true
            minimax = $false
            grok = $true
        }

        (Test-CanHideProvider "grok" $enabledMap $visibilityMap) | Should Be $true
    }
}
