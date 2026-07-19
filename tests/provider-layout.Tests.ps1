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

    It "reuses the same outer border shell for hover detail windows" {
        $outer = New-WidgetOuterBorder

        $outer.CornerRadius.TopLeft | Should Be 16
        $outer.Padding.Top | Should Be 10
        $outer.BorderThickness.Left | Should Be 1
    }

    It "prefers placing the hover detail window above the compact tile when space allows" {
        $ownerRect = [pscustomobject]@{ Left = 100; Top = 400; Width = 360; Height = 62; Right = 460; Bottom = 462 }
        $sourceRect = [pscustomobject]@{ Left = 220; Top = 410; Width = 140; Height = 48; Right = 360; Bottom = 458 }
        $popupSize = [pscustomobject]@{ Width = 360; Height = 210 }
        $workArea = [pscustomobject]@{ Left = 0; Top = 0; Width = 1200; Height = 900; Right = 1200; Bottom = 900 }

        $placement = Get-HoverDetailPlacement $ownerRect $sourceRect $popupSize $workArea

        $placement.Left | Should Be 220
        $placement.Top | Should Be 192
    }

    It "falls back below and clamps horizontally when the hover detail window would overflow" {
        $ownerRect = [pscustomobject]@{ Left = 900; Top = 70; Width = 360; Height = 62; Right = 1260; Bottom = 132 }
        $sourceRect = [pscustomobject]@{ Left = 1100; Top = 78; Width = 140; Height = 48; Right = 1240; Bottom = 126 }
        $popupSize = [pscustomobject]@{ Width = 360; Height = 210 }
        $workArea = [pscustomobject]@{ Left = 0; Top = 0; Width = 1280; Height = 800; Right = 1280; Bottom = 800 }

        $placement = Get-HoverDetailPlacement $ownerRect $sourceRect $popupSize $workArea

        $placement.Left | Should Be 920
        $placement.Top | Should Be 134
    }

    It "places the detailed panel on the right side and vertically centered" {
        $popupSize = [pscustomobject]@{ Width = 360; Height = 400 }
        $workArea = [pscustomobject]@{ Left = 0; Top = 0; Width = 1920; Height = 1080; Right = 1920; Bottom = 1080 }

        $placement = Get-DetailedPanelPlacement $popupSize $workArea 12

        $placement.Left | Should Be 1548
        $placement.Top | Should Be 340
    }

    It "clamps the detailed panel into the work area when the popup is taller than the screen" {
        $popupSize = [pscustomobject]@{ Width = 360; Height = 900 }
        $workArea = [pscustomobject]@{ Left = 100; Top = 50; Width = 800; Height = 600; Right = 900; Bottom = 650 }

        $placement = Get-DetailedPanelPlacement $popupSize $workArea 12

        $placement.Left | Should Be 528
        $placement.Top | Should Be 50
    }
}
