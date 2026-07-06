$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Usage display mode helpers" {
    It "normalizes unknown display modes back to used" {
        Normalize-UsageDisplayMode "anything" | Should Be "used"
        Normalize-UsageDisplayMode "left" | Should Be "left"
    }

    It "shows the opposite mode in the toggle label" {
        Get-UsageDisplayToggleLabel "used" | Should Be "Show Left %"
        Get-UsageDisplayToggleLabel "left" | Should Be "Show Used %"
    }

    It "shows used percent in used mode" {
        $script:UsageDisplayMode = "used"

        $display = Get-UsageDisplayData 37

        $display.mode | Should Be "used"
        $display.percent | Should Be 37
        $display.accentPercent | Should Be 37
    }

    It "shows remaining percent in left mode while keeping severity colors aligned" {
        $script:UsageDisplayMode = "left"

        $display = Get-UsageDisplayData 82

        $display.mode | Should Be "left"
        $display.percent | Should Be 18
        $display.accentPercent | Should Be 82
    }
}
