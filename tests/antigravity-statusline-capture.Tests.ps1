$captureScript = Join-Path $PSScriptRoot "..\tools\capture-antigravity-statusline.ps1"

Describe "Antigravity statusline capture" {
    It "records matching field paths and types without retaining values" {
        $outputPath = Join-Path $env:TEMP ("antigravity-shape-{0}.json" -f [guid]::NewGuid().ToString("N"))
        $input = @'
{"email":"private@example.com","access_token":"secret-value","plan_tier":"Pro","quota":{"remaining_percent":61,"resets_at":"2026-07-10T18:00:00Z"}}
'@

        try {
            $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $powershell
            $startInfo.Arguments = "-NoProfile -File `"$captureScript`" -OutputPath `"$outputPath`""
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardInput = $true
            $process = [System.Diagnostics.Process]::Start($startInfo)
            $process.StandardInput.Write($input)
            $process.StandardInput.Close()
            $process.WaitForExit()
            $process.ExitCode | Should Be 0
            $capture = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
            ($capture.candidates.path -contains '$.quota.remaining_percent') | Should Be $true
            ($capture.candidates.path -contains '$.quota.resets_at') | Should Be $true
            (Get-Content -LiteralPath $outputPath -Raw) | Should Not Match 'private@example.com|secret-value|"remaining_percent": 61|"resets_at": "2026-07-10T18:00:00Z"'
        } finally {
            Remove-Item -LiteralPath $outputPath -ErrorAction SilentlyContinue
        }
    }
}
