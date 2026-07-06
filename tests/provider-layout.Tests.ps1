$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Compact layout helpers" {
    It "uses single-column compact layout for one provider" {
        $layout = Get-CompactLayoutMetrics 1

        $layout.Columns | Should Be 1
        $layout.Rows | Should Be 1
        $layout.Width | Should Be $script:CompactSingleWidth
        $layout.Height | Should Be $script:CompactHeight
    }

    It "keeps two providers on one compact row" {
        $layout = Get-CompactLayoutMetrics 2

        $layout.Columns | Should Be 2
        $layout.Rows | Should Be 1
        $layout.Width | Should Be $script:CompactDoubleWidth
        $layout.Height | Should Be $script:CompactHeight
    }

    It "expands compact height when three providers are visible" {
        $layout = Get-CompactLayoutMetrics 3

        $layout.Columns | Should Be 2
        $layout.Rows | Should Be 2
        $layout.Width | Should Be $script:CompactDoubleWidth
        ($layout.Height -gt $script:CompactHeight) | Should Be $true
    }

    It "styles the primary full row larger than the weekly row" {
        $primary = New-LimitRow "CURRENT SESSION" $true 7
        $secondary = New-LimitRow "WEEKLY" $false 7

        ($primary.value.FontSize -gt $secondary.value.FontSize) | Should Be $true
        ($primary.track.Height -gt $secondary.track.Height) | Should Be $true
    }

    It "starts compact panels without an inner box border" {
        $panel = New-CompactProviderPanel "CODEX" "#6FE8FF"

        $panel.panel.BorderThickness.Left | Should Be 0
        $panel.panel.Padding.Bottom | Should BeGreaterThan 4
    }
}
