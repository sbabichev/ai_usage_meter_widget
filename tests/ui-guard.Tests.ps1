$env:USAGE_WIDGET_TEST_MODE = "1"
. "$PSScriptRoot\..\usage-widget.ps1"

Describe "UI guard helper" {
    It "returns true for successful callbacks" {
        Invoke-GuardedUiAction "test.ok" { $script:UiGuardProbe = "ok" } | Should Be $true
        $script:UiGuardProbe | Should Be "ok"
    }

    It "catches command-not-found callbacks and logs the action name" {
        $logMessages = [System.Collections.Generic.List[string]]::new()
        Mock Write-WidgetLog {
            param($message)
            $logMessages.Add($message) | Out-Null
        }

        $result = Invoke-GuardedUiAction "test.fail" { Missing-WidgetCommand }

        $result | Should Be $false
        $logMessages.Count | Should Be 1
        $logMessages[0] | Should Match "UI callback failed \[test\.fail\]"
        $logMessages[0] | Should Match "CommandNotFoundException"
        $logMessages[0] | Should Match "Missing-WidgetCommand"
    }
}
