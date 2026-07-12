$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "Provider formatting helpers" {
    It "formats multi-day reset durations without invoking if as a command" {
        (Format-CompactDuration ([timespan]::FromDays(7).Add([timespan]::FromHours(3)))) | Should Be "7d3h"
    }

    It "formats display percent with a suffix" {
        Format-DisplayPercent 23 | Should Be "23%"
        Format-DisplayPercent 100 | Should Be "100%"
    }

    It "formats compact durations without spacing jumps" {
        Format-CompactDuration ([timespan]::FromMinutes(272)) | Should Be "4h32m"
        Format-CompactDuration ([timespan]::FromMinutes(23)) | Should Be "23m"
    }

    It "formats reset labels with the monochrome reset symbol" {
        $resetSeconds = [DateTimeOffset]::Now.AddHours(4).ToUnixTimeSeconds()
        $label = Format-ResetLabel $resetSeconds

        $label.StartsWith(("{0} " -f (Get-UiGlyph "reset"))) | Should Be $true
        $label.Contains("Reset") | Should Be $false
        $label.Contains("Bali") | Should Be $false
    }

    It "uses tabular numerals for numeric text blocks" {
        $block = New-NumericTextBlock "23%" 16 "Light" "#FFFFFF"

        [System.Windows.Documents.Typography]::GetNumeralAlignment($block) | Should Be ([System.Windows.FontNumeralAlignment]::Tabular)
        [System.Windows.Documents.Typography]::GetNumeralStyle($block) | Should Be ([System.Windows.FontNumeralStyle]::Lining)
    }
}
