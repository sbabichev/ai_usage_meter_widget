$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Provider state helpers" {
    It "keeps enabled providers visible when legacy state does not contain them" {
        $rawVisibility = [pscustomobject]@{
            codex = $true
            minimax = $false
        }
        $enabledMap = [ordered]@{
            codex = $true
            minimax = $true
            grok = $true
        }

        $visibility = Normalize-ProviderVisibilityMap $rawVisibility $enabledMap

        $visibility.codex | Should Be $true
        $visibility.minimax | Should Be $false
        $visibility.grok | Should Be $true
    }

    It "forces at least one enabled provider visible" {
        $enabledMap = [ordered]@{
            codex = $true
            minimax = $true
            grok = $false
        }
        $rawVisibility = [pscustomobject]@{
            codex = $false
            minimax = $false
        }

        $visibility = Normalize-ProviderVisibilityMap $rawVisibility $enabledMap

        @($visibility.codex, $visibility.minimax) -contains $true | Should Be $true
    }

    It "serializes and restores provider snapshots with mixed window counts" {
        $providers = [ordered]@{
            codex = [pscustomobject]@{
                ok = $true
                updated = (Get-Date)
                primary = [pscustomobject]@{
                    used_percent = 12
                    resets_at = 100
                    window_minutes = 300
                }
                secondary = [pscustomobject]@{
                    used_percent = 34
                    resets_at = 200
                    window_minutes = 10080
                }
            }
            grok = [pscustomobject]@{
                ok = $true
                updated = (Get-Date)
                source = "log"
                primary = [pscustomobject]@{
                    used_percent = 77
                    resets_at = 300
                    window_minutes = 10080
                }
                secondary = $null
            }
        }

        $snapshot = New-ProviderUsageSnapshotMap $providers
        $restored = Restore-ProviderUsageSnapshotMap $snapshot

        $restored.codex.primary.used_percent | Should Be 12
        $restored.codex.secondary.used_percent | Should Be 34
        $restored.grok.primary.used_percent | Should Be 77
        $restored.grok.secondary | Should Be $null
    }
}
