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
}
