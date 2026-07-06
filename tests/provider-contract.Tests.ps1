$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Provider contract helpers" {
    It "merges provider config objects without erasing unrelated settings" {
        $base = [pscustomobject]@{
            minimax = [pscustomobject]@{
                enabled = $false
                modelPattern = "general"
                refreshSeconds = 300
            }
            window = [pscustomobject]@{
                topmost = $true
            }
        }

        $local = [pscustomobject]@{
            minimax = [pscustomobject]@{
                enabled = $true
                timeoutSeconds = 10
            }
            grok = [pscustomobject]@{
                enabled = $true
            }
        }

        $merged = Merge-ConfigObject $base $local

        $merged.minimax.enabled | Should Be $true
        $merged.minimax.modelPattern | Should Be "general"
        $merged.minimax.refreshSeconds | Should Be 300
        $merged.minimax.timeoutSeconds | Should Be 10
        $merged.grok.enabled | Should Be $true
        $merged.window.topmost | Should Be $true
    }

    It "resolves provider enabled map from known providers" {
        $config = [pscustomobject]@{
            minimax = [pscustomobject]@{
                enabled = $true
            }
            grok = [pscustomobject]@{
                enabled = $false
            }
        }

        $enabledMap = Get-ProviderEnabledMap $config

        $enabledMap.codex | Should Be $true
        $enabledMap.minimax | Should Be $true
        $enabledMap.grok | Should Be $false
    }
}
