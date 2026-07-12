Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("NativeWindowTools" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class NativeWindowTools {
    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

    public const UInt32 SWP_NOSIZE = 0x0001;
    public const UInt32 SWP_NOMOVE = 0x0002;
    public const UInt32 SWP_NOACTIVATE = 0x0010;
    public const UInt32 SWP_SHOWWINDOW = 0x0040;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        UInt32 uFlags);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
}

[NativeWindowTools]::ShowWindow([NativeWindowTools]::GetConsoleWindow(), 0) | Out-Null

$ErrorActionPreference = "Continue"

$script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:StatePath = Join-Path $script:AppDir "usage-widget.state.json"
$script:ConfigPath = Join-Path $script:AppDir "usage-widget.config.json"
$script:LocalConfigPath = Join-Path $script:AppDir "usage-widget.local.json"
$script:LogPath = Join-Path $script:AppDir "usage-widget.log"
$script:CodexSessionsDir = Join-Path $env:USERPROFILE ".codex\sessions"
$script:CodexLogsPath = Join-Path $env:USERPROFILE ".codex\logs_2.sqlite"
$script:GrokLogsPath = Join-Path $env:USERPROFILE ".grok\logs\unified.jsonl"
$script:GrokAuthPath = Join-Path $env:USERPROFILE ".grok\auth.json"
$script:IconPath = Join-Path $script:AppDir "assets\codex-usage-meter.ico"
$script:CodexUsageDashboardUrl = "https://chatgpt.com/codex/settings/usage"
$script:WidgetWidth = 360
$script:WidgetHeight = 430
$script:CompactSingleWidth = 240
$script:CompactDoubleWidth = 460
$script:CompactHeight = 62
$script:CompactMultiRowHeight = 116
$script:StaleAfterSeconds = 900
$script:ResetDriftToleranceSeconds = 120
$script:MinimaxDefaultRefreshSeconds = 300
$script:MinimaxTokenPlanUrl = "https://api.minimax.io/v1/token_plan/remains"
$script:GrokBillingApiUrl = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
$script:GrokClientVersion = $null
$script:MinimaxRemoteState = @{
    LastFetch = $null
    Usage = $null
    Error = $null
}
$script:GrokRemoteState = @{
    Usage = $null
    Error = $null
    RefreshStatus = $null
}
$script:AntigravityRemoteState = @{
    Usage = $null
    Error = $null
    RefreshStatus = $null
}
$script:CodexEnabled = $true
$script:MinimaxEnabled = $true
$script:CompactMode = $false
$script:TopmostEnabled = $true
$script:UsageDisplayMode = "used"
$script:UsageSnapshot = $null
$script:StartupRefreshTimer = $null
$script:CompactTopmostTimer = $null
$script:CodexSessionChangeTimer = $null
$script:CodexLastSessionChangeKey = ""
$script:FullWidgetHeight = $script:WidgetHeight
$script:HoverDetailOpenDelayMs = 2000
$script:HoverDetailCloseDelayMs = 140
$script:HoverDetailState = $null
$script:UsageFloorState = @{
    WindowKey = ""
    PrimaryUsed = $null
    SecondaryUsed = $null
}
$script:MinimaxFloorState = @{
    WindowKey = ""
    PrimaryUsed = $null
    SecondaryUsed = $null
}

function New-ProviderMetadataMap {
    return [ordered]@{
        codex = [pscustomobject]@{
            id = "codex"
            label = "Codex"
            title = "CODEX"
            accent = "#6FE8FF"
            defaultEnabled = $true
            defaultVisible = $true
            supportsActivity = $true
            supportsHint = $true
            supportsRefresh = $false
            defaultWindows = @("Session", "Weekly")
        }
        minimax = [pscustomobject]@{
            id = "minimax"
            label = "MiniMax"
            title = "MINIMAX"
            accent = "#FF8A3D"
            defaultEnabled = $false
            defaultVisible = $true
            supportsActivity = $false
            supportsHint = $false
            supportsRefresh = $false
            defaultWindows = @("Session", "Weekly")
        }
        grok = [pscustomobject]@{
            id = "grok"
            label = "Grok"
            title = "GROK"
            accent = "#B9A7FF"
            defaultEnabled = $false
            defaultVisible = $true
            supportsActivity = $false
            supportsHint = $true
            supportsRefresh = $true
            actionLabel = "API"
            actionToolTip = "Check via API"
            defaultWindows = @("Weekly")
        }
        antigravity = [pscustomobject]@{
            id = "antigravity"
            label = "Google Antigravity"
            title = "ANTIGRAVITY"
            accent = "#4285F4"
            defaultEnabled = $false
            defaultVisible = $true
            supportsActivity = $false
            supportsHint = $true
            supportsRefresh = $true
            actionLabel = "AGY"
            actionToolTip = "Read latest AGY statusline snapshot"
            defaultWindows = @("Session", "Weekly")
        }
    }
}

$script:ProviderMetadata = New-ProviderMetadataMap
$script:ProviderVisibility = [ordered]@{}
$script:ProviderEnabledMap = [ordered]@{}
$script:ProviderActionStatus = [ordered]@{}

function Get-ProviderIds {
    return @($script:ProviderMetadata.Keys)
}

function Get-ProviderMetadata($providerId) {
    return Get-ObjectValue $script:ProviderMetadata $providerId $null
}

function New-HoverDetailState($controls = $null) {
    return [pscustomobject]@{
        Controls = $controls
        Window = $null
        Outer = $null
        ContentHost = $null
        PopupControl = $null
        ProviderId = $null
        PendingProviderId = $null
        HoverProviderId = $null
        SourcePanel = $null
        IsPointerOverPopup = $false
        OpenTimer = $null
        CloseTimer = $null
        UsageMap = [ordered]@{}
        Activity = $null
    }
}

function Get-HoverDetailState($controls = $null) {
    if (-not $script:HoverDetailState) {
        $script:HoverDetailState = New-HoverDetailState $controls
    } elseif ($controls) {
        $script:HoverDetailState.Controls = $controls
    }

    return $script:HoverDetailState
}

function Stop-DispatcherTimer($timer) {
    if ($null -eq $timer) {
        return
    }

    try {
        $timer.Stop()
    } catch {
    }
}

function Stop-HoverDetailOpenTimer {
    $state = Get-HoverDetailState
    Stop-DispatcherTimer $state.OpenTimer
}

function Stop-HoverDetailCloseTimer {
    $state = Get-HoverDetailState
    Stop-DispatcherTimer $state.CloseTimer
}

function Clear-HoverDetailPendingProvider {
    $state = Get-HoverDetailState
    $state.PendingProviderId = $null
    $state.SourcePanel = $null
    Stop-HoverDetailOpenTimer
}

function Test-CanShowHoverDetail($providerId) {
    if (-not $script:CompactMode) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($providerId)) {
        return $false
    }

    return (Get-VisibleProviderIds) -contains $providerId
}

function New-WidgetOuterBorder {
    $outer = New-Object System.Windows.Controls.Border
    $outer.Margin = "6"
    $outer.Padding = "12,10,12,4"
    $outer.CornerRadius = 16
    $outer.BorderThickness = 1
    $outer.BorderBrush = Get-Brush "#AAB7BD"
    $outer.Background = Get-Brush "#E00E1821"
    $outer.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
        BlurRadius = 8
        ShadowDepth = 0
        Opacity = 0.18
        Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#02080E")
    }

    return $outer
}

function Get-VisualScreenRect($element) {
    if (-not $element) {
        return $null
    }

    try {
        $point = $element.PointToScreen([System.Windows.Point]::new(0, 0))
        $width = if ($element.ActualWidth -gt 0) { [double]$element.ActualWidth } else { 0 }
        $height = if ($element.ActualHeight -gt 0) { [double]$element.ActualHeight } else { 0 }
        return [pscustomobject]@{
            Left = [double]$point.X
            Top = [double]$point.Y
            Width = $width
            Height = $height
            Right = [double]$point.X + $width
            Bottom = [double]$point.Y + $height
        }
    } catch {
        return $null
    }
}

function Get-ScreenWorkAreaForRect($rect) {
    $defaultBounds = [System.Windows.SystemParameters]::WorkArea
    if (-not $rect) {
        return [pscustomobject]@{
            Left = [double]$defaultBounds.Left
            Top = [double]$defaultBounds.Top
            Width = [double]$defaultBounds.Width
            Height = [double]$defaultBounds.Height
            Right = [double]$defaultBounds.Right
            Bottom = [double]$defaultBounds.Bottom
        }
    }

    $centerX = [int][Math]::Round($rect.Left + ($rect.Width / 2))
    $centerY = [int][Math]::Round($rect.Top + ($rect.Height / 2))
    $screen = [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new($centerX, $centerY))
    $bounds = $screen.WorkingArea

    return [pscustomobject]@{
        Left = [double]$bounds.Left
        Top = [double]$bounds.Top
        Width = [double]$bounds.Width
        Height = [double]$bounds.Height
        Right = [double]$bounds.Right
        Bottom = [double]$bounds.Bottom
    }
}

function Get-HoverDetailPlacement($ownerRect, $sourceRect, $popupSize, $workArea, $gap = 8) {
    $anchorRect = if ($sourceRect) { $sourceRect } else { $ownerRect }

    $left = $anchorRect.Left
    if ($ownerRect) {
        $left = [Math]::Max($ownerRect.Left, $left)
    }

    $maxLeft = [Math]::Max($workArea.Left, $workArea.Right - $popupSize.Width)
    if ($left -gt $maxLeft) {
        $left = $maxLeft
    }

    if ($left -lt $workArea.Left) {
        $left = $workArea.Left
    }

    $preferredTop = $anchorRect.Top - $popupSize.Height - $gap
    $fallbackTop = $anchorRect.Bottom + $gap
    $top = if ($preferredTop -ge $workArea.Top) { $preferredTop } else { $fallbackTop }
    $maxTop = [Math]::Max($workArea.Top, $workArea.Bottom - $popupSize.Height)
    if ($top -gt $maxTop) {
        $top = $maxTop
    }

    if ($top -lt $workArea.Top) {
        $top = $workArea.Top
    }

    return [pscustomobject]@{
        Left = [Math]::Round($left)
        Top = [Math]::Round($top)
    }
}

function Get-OwnerWindowRect($window) {
    if (-not $window) {
        return $null
    }

    $width = if ($window.ActualWidth -gt 0) { [double]$window.ActualWidth } elseif ($window.Width -gt 0) { [double]$window.Width } else { [double]$script:WidgetWidth }
    $height = if ($window.ActualHeight -gt 0) { [double]$window.ActualHeight } elseif ($window.Height -gt 0) { [double]$window.Height } else { [double]$script:WidgetHeight }

    return [pscustomobject]@{
        Left = [double]$window.Left
        Top = [double]$window.Top
        Width = $width
        Height = $height
        Right = [double]$window.Left + $width
        Bottom = [double]$window.Top + $height
    }
}

function Get-ElementRectWithinOwner($element, $ownerWindow) {
    if (-not $element -or -not $ownerWindow) {
        return $null
    }

    try {
        $point = $element.TranslatePoint([System.Windows.Point]::new(0, 0), $ownerWindow)
        $width = if ($element.ActualWidth -gt 0) { [double]$element.ActualWidth } else { 0 }
        $height = if ($element.ActualHeight -gt 0) { [double]$element.ActualHeight } else { 0 }
        return [pscustomobject]@{
            Left = [double]$ownerWindow.Left + [double]$point.X
            Top = [double]$ownerWindow.Top + [double]$point.Y
            Width = $width
            Height = $height
            Right = [double]$ownerWindow.Left + [double]$point.X + $width
            Bottom = [double]$ownerWindow.Top + [double]$point.Y + $height
        }
    } catch {
        return $null
    }
}

function Test-IsConfigObject($value) {
    return ($value -is [System.Collections.IDictionary]) -or ($value -is [psobject] -and $null -ne $value.PSObject)
}

function Get-ObjectEntries($value) {
    if ($null -eq $value) {
        return @()
    }

    if ($value -is [System.Collections.IDictionary]) {
        return @($value.GetEnumerator())
    }

    return @($value.PSObject.Properties)
}

function Merge-ConfigObject($target, $source) {
    if (-not (Test-IsConfigObject $target)) {
        $target = [pscustomobject]@{}
    }

    if (-not (Test-IsConfigObject $source)) {
        return $target
    }

    foreach ($entry in (Get-ObjectEntries $source)) {
        $name = if ($entry -is [System.Collections.DictionaryEntry]) { [string]$entry.Key } else { [string]$entry.Name }
        $value = if ($entry -is [System.Collections.DictionaryEntry]) { $entry.Value } else { $entry.Value }
        $existing = Get-ObjectValue $target $name $null

        if ((Test-IsConfigObject $existing) -and (Test-IsConfigObject $value)) {
            $merged = Merge-ConfigObject $existing $value
            $target | Add-Member -MemberType NoteProperty -Name $name -Value $merged -Force
            continue
        }

        $target | Add-Member -MemberType NoteProperty -Name $name -Value $value -Force
    }

    return $target
}

function Get-ProviderConfigObject($config, $providerId) {
    if (-not $config) {
        return $null
    }

    $topLevel = Get-ObjectValue $config $providerId $null
    $providersRoot = Get-ObjectValue $config "providers" $null
    $nested = Get-ObjectValue $providersRoot $providerId $null

    if ((Test-IsConfigObject $topLevel) -and (Test-IsConfigObject $nested)) {
        return Merge-ConfigObject $topLevel $nested
    }

    if (Test-IsConfigObject $topLevel) {
        return $topLevel
    }

    if (Test-IsConfigObject $nested) {
        return $nested
    }

    return $null
}

function New-DefaultProviderVisibilityMap {
    $map = [ordered]@{}
    foreach ($providerId in (Get-ProviderIds)) {
        $metadata = Get-ProviderMetadata $providerId
        $map[$providerId] = [bool](Get-ObjectValue $metadata "defaultVisible" $true)
    }

    return $map
}

function Get-ProviderEnabledMap($config) {
    $map = [ordered]@{}
    foreach ($providerId in (Get-ProviderIds)) {
        $metadata = Get-ProviderMetadata $providerId
        $providerConfig = Get-ProviderConfigObject $config $providerId
        $defaultEnabled = [bool](Get-ObjectValue $metadata "defaultEnabled" $false)
        $enabled = Convert-ToBoolean (Get-ObjectValue $providerConfig "enabled" $null) $defaultEnabled
        $map[$providerId] = [bool]$enabled
    }

    return $map
}

function Normalize-ProviderVisibilityMap($rawVisibility, $enabledMap) {
    $visibility = [ordered]@{}

    foreach ($providerId in (Get-ProviderIds)) {
        $metadata = Get-ProviderMetadata $providerId
        $defaultVisible = [bool](Get-ObjectValue $metadata "defaultVisible" $true)
        $isEnabled = [bool](Get-ObjectValue $enabledMap $providerId $false)
        $savedValue = Get-ObjectValue $rawVisibility $providerId $null
        if (-not $isEnabled) {
            $visibility[$providerId] = $false
        } elseif ($null -eq $savedValue) {
            $visibility[$providerId] = if ($isEnabled) { $defaultVisible } else { $false }
        } else {
            $visibility[$providerId] = [bool]$savedValue
        }
    }

    $enabledVisibleIds = @(
        foreach ($providerId in (Get-ProviderIds)) {
            if ([bool](Get-ObjectValue $enabledMap $providerId $false) -and [bool](Get-ObjectValue $visibility $providerId $false)) {
                $providerId
            }
        }
    )

    if ($enabledVisibleIds.Count -eq 0) {
        foreach ($providerId in (Get-ProviderIds)) {
            if ([bool](Get-ObjectValue $enabledMap $providerId $false)) {
                $visibility[$providerId] = $true
                break
            }
        }
    }

    return $visibility
}

function Get-VisibleProviderIds {
    return @(
        foreach ($providerId in (Get-ProviderIds)) {
            if ([bool](Get-ObjectValue $script:ProviderEnabledMap $providerId $false) -and [bool](Get-ObjectValue $script:ProviderVisibility $providerId $false)) {
                $providerId
            }
        }
    )
}

function Test-ProviderVisible($providerId) {
    return [bool](Get-ObjectValue $script:ProviderVisibility $providerId $false)
}

function Set-ProviderVisible($providerId, $visible) {
    $script:ProviderVisibility[$providerId] = [bool]$visible
}

function Test-CanHideProvider($providerId, $enabledMap = $script:ProviderEnabledMap, $visibilityMap = $script:ProviderVisibility) {
    if (-not [bool](Get-ObjectValue $enabledMap $providerId $false)) {
        return $false
    }

    if (-not [bool](Get-ObjectValue $visibilityMap $providerId $false)) {
        return $true
    }

    $visibleCount = 0
    foreach ($candidateProviderId in (Get-ProviderIds)) {
        if ([bool](Get-ObjectValue $enabledMap $candidateProviderId $false) -and [bool](Get-ObjectValue $visibilityMap $candidateProviderId $false)) {
            $visibleCount++
        }
    }

    return ($visibleCount -gt 1)
}

function Get-ProviderActionStatus($providerId) {
    return Get-ObjectValue $script:ProviderActionStatus $providerId $null
}

function Set-ProviderActionStatus($providerId, $state, $summary = $null, $detail = $null) {
    $status = [pscustomobject]@{
        state = $state
        summary = $summary
        detail = $detail
        updated = Get-Date
    }

    $script:ProviderActionStatus[$providerId] = $status
    return $status
}

function Get-Brush($hex) {
    return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}

function Get-Color($hex) {
    return [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
}

function Get-LimitAccent($usedPercent) {
    $used = [Math]::Max([double]0, [Math]::Min([double]100, [double]$usedPercent))
    if ($used -ge 90) {
        return "#FF8A3D"
    }

    if ($used -ge 75) {
        return "#FFC857"
    }

    if ($used -ge 50) {
        return "#D7F85A"
    }

    return "#A6FF4F"
}

function Normalize-UsageDisplayMode($mode) {
    if ([string]$mode -eq "left") {
        return "left"
    }

    return "used"
}

function Get-UsageDisplayData($usedPercent) {
    $safeUsed = [Math]::Max([double]0, [Math]::Min([double]100, [double]$usedPercent))
    $mode = Normalize-UsageDisplayMode $script:UsageDisplayMode
    $displayPercent = if ($mode -eq "left") { 100 - $safeUsed } else { $safeUsed }

    return [pscustomobject]@{
        mode = $mode
        percent = $displayPercent
        accentPercent = if ($mode -eq "left") { 100 - $displayPercent } else { $displayPercent }
    }
}

function Get-UsageDisplayToggleLabel($mode = $script:UsageDisplayMode) {
    if ((Normalize-UsageDisplayMode $mode) -eq "left") {
        return "Show Used %"
    }

    return "Show Left %"
}

function Format-DisplayPercent($percent) {
    $safePercent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$percent))
    return ("{0}%" -f [Math]::Round($safePercent))
}

function Get-UiGlyph($name) {
    switch ($name) {
        "ok" { return [string][char]0x25CF }
        "low" { return [string][char]0x25B2 }
        "wait" { return [string][char]0x25A0 }
        "reset" { return [string][char]0x21BB }
        "hourglass" { return [string][char]0x23F3 }
        default { return "" }
    }
}

function Enable-TabularNumbers($block) {
    if (-not $block) {
        return $null
    }

    try {
        [System.Windows.Documents.Typography]::SetNumeralAlignment($block, [System.Windows.FontNumeralAlignment]::Tabular)
        [System.Windows.Documents.Typography]::SetNumeralStyle($block, [System.Windows.FontNumeralStyle]::Lining)
    } catch {
    }

    return $block
}

function Set-LimitAccent($row, $usedPercent, $enabled) {
    $accent = if ($enabled) { Get-LimitAccent $usedPercent } else { "#6F7D85" }
    $row.fill.Background = Get-Brush $accent
    $row.value.Foreground = Get-Brush $accent
    if ($row.mode) {
        $row.mode.Foreground = Get-Brush "#D6E1E6"
    }
    if ($row.fill.Effect) {
        $row.fill.Effect.Color = Get-Color $accent
        $row.fill.Effect.Opacity = if ($enabled) { 0.42 } else { 0.12 }
    }
}

function New-TextBlock($text, $fontSize, $weight, $color) {
    $block = New-Object System.Windows.Controls.TextBlock
    $block.Text = $text
    $block.FontSize = $fontSize
    $block.FontWeight = $weight
    $block.Foreground = Get-Brush $color
    $block.FontFamily = "Segoe UI Variable Text, Segoe UI"
    $block.TextTrimming = "CharacterEllipsis"
    return $block
}

function New-NumericTextBlock($text, $fontSize, $weight, $color) {
    $block = New-TextBlock $text $fontSize $weight $color
    Enable-TabularNumbers $block | Out-Null
    return $block
}

function New-Hairline($topMargin, $bottomMargin) {
    $line = New-Object System.Windows.Controls.Border
    $line.Height = 1
    $line.Margin = "0,$topMargin,0,$bottomMargin"
    $line.Background = Get-Brush "#CAD4D9"
    $line.Opacity = 0.11
    return $line
}

function Write-WidgetLog($message) {
    try {
        $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        [System.IO.File]::AppendAllText($script:LogPath, "[$stamp] $message`r`n", [System.Text.Encoding]::UTF8)
    } catch {
    }
}

function Invoke-GuardedUiAction($actionName, $action) {
    if (-not $action) {
        return $false
    }

    try {
        & $action
        return $true
    } catch {
        $exception = $_.Exception
        $typeName = if ($exception) { $exception.GetType().FullName } else { "UnknownException" }
        $message = if ($exception) { $exception.Message } else { $_.ToString() }
        Write-WidgetLog ("UI callback failed [{0}] {1}: {2}" -f $actionName, $typeName, $message)
        return $false
    }
}

function Get-FileTailLines($path, $maxBytes) {
    try {
        $stream = [System.IO.File]::Open(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            $length = $stream.Length
            $bytesToRead = [Math]::Min([int64]$maxBytes, $length)
            $offset = $length - $bytesToRead
            $stream.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null

            $buffer = New-Object byte[] ([int]$bytesToRead)
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) {
                return @()
            }

            $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
            if ($offset -gt 0) {
                $firstNewline = $text.IndexOf("`n")
                if ($firstNewline -ge 0 -and $firstNewline + 1 -lt $text.Length) {
                    $text = $text.Substring($firstNewline + 1)
                }
            }

            $lineArray = $text.Split([char]10)
            return @($lineArray | Where-Object { $_ })
        } finally {
            $stream.Dispose()
        }
    } catch {
        return @()
    }
}

function Get-FileTailText($path, $maxBytes) {
    try {
        $stream = [System.IO.File]::Open(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            $length = $stream.Length
            $bytesToRead = [Math]::Min([int64]$maxBytes, $length)
            $offset = $length - $bytesToRead
            $stream.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null

            $buffer = New-Object byte[] ([int]$bytesToRead)
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) {
                return ""
            }

            return [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        } finally {
            $stream.Dispose()
        }
    } catch {
        return ""
    }
}

function Get-BalancedJsonFromText($text, $startIndex) {
    if ([string]::IsNullOrEmpty($text) -or $startIndex -lt 0 -or $startIndex -ge $text.Length) {
        return $null
    }

    $depth = 0
    $inString = $false
    $escaped = $false
    for ($i = $startIndex; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($escaped) {
            $escaped = $false
            continue
        }

        if ($ch -eq '\') {
            $escaped = $true
            continue
        }

        if ($ch -eq '"') {
            $inString = -not $inString
            continue
        }

        if ($inString) {
            continue
        }

        if ($ch -eq "{") {
            $depth++
        } elseif ($ch -eq "}") {
            $depth--
            if ($depth -eq 0) {
                return $text.Substring($startIndex, $i - $startIndex + 1)
            }
        }
    }

    return $null
}

function Test-IsInsideButton($source) {
    $current = $source
    while ($null -ne $current) {
        if ($current -is [System.Windows.Controls.Button]) {
            return $true
        }

        try {
            $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
        } catch {
            return $false
        }
    }

    return $false
}

function Read-State {
    $default = [pscustomobject]@{
        left = 120
        top = 90
        topmost = $true
        opacity = 1.0
        refreshSeconds = 3
        compactMode = $false
        displayMode = "used"
        usageSnapshot = $null
        usageFloor = $null
        providers = New-DefaultProviderVisibilityMap
    }

    if (-not (Test-Path $script:StatePath)) {
        return $default
    }

    try {
        $raw = [System.IO.File]::ReadAllText($script:StatePath, [System.Text.Encoding]::UTF8)
        $state = $raw | ConvertFrom-Json
        if ($null -eq $state.left -or $null -eq $state.top) {
            return $default
        }

        return $state
    } catch {
        return $default
    }
}

function Get-ObjectValue($object, $name, $fallback = $null) {
    if ($null -eq $object) {
        return $fallback
    }

    if ($object -is [System.Collections.IDictionary]) {
        if ($object.Contains($name)) {
            return $object[$name]
        }

        return $fallback
    }

    $property = $object.PSObject.Properties[$name]
    if ($null -eq $property) {
        return $fallback
    }

    return $property.Value
}

function Set-WindowTopmost($window) {
    if ($null -eq $window) {
        return
    }

    $isTopmost = ($script:CompactMode -or $script:TopmostEnabled)
    $window.Topmost = $isTopmost

    try {
        $handle = ([System.Windows.Interop.WindowInteropHelper]::new($window)).Handle
        if ($handle -ne [IntPtr]::Zero) {
            $insertAfter = if ($isTopmost) { [NativeWindowTools]::HWND_TOPMOST } else { [NativeWindowTools]::HWND_NOTOPMOST }
            [NativeWindowTools]::SetWindowPos(
                $handle,
                $insertAfter,
                0,
                0,
                0,
                0,
                [NativeWindowTools]::SWP_NOMOVE -bor [NativeWindowTools]::SWP_NOSIZE -bor [NativeWindowTools]::SWP_NOACTIVATE -bor [NativeWindowTools]::SWP_SHOWWINDOW
            ) | Out-Null
        }
    } catch {
    }

    $hoverState = $script:HoverDetailState
    if ($hoverState -and $hoverState.Window -and $hoverState.Window -ne $window) {
        $hoverState.Window.Topmost = $script:TopmostEnabled
    }
}

function Sync-CompactTopmostTimer($window) {
    if ($script:CompactMode) {
        if ($null -eq $script:CompactTopmostTimer) {
            $script:CompactTopmostTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:CompactTopmostTimer.Interval = [TimeSpan]::FromMilliseconds(700)
            $script:CompactTopmostTimer.Tag = $window
            $script:CompactTopmostTimer.Add_Tick({
                param($sender)
                Invoke-GuardedUiAction "CompactTopmostTimer.Tick" {
                    if (-not $script:CompactMode) {
                        $sender.Stop()
                        $script:CompactTopmostTimer = $null
                        return
                    }

                    Set-WindowTopmost $sender.Tag
                } | Out-Null
            })
        } else {
            $script:CompactTopmostTimer.Tag = $window
        }

        if (-not $script:CompactTopmostTimer.IsEnabled) {
            $script:CompactTopmostTimer.Start()
        }
        Set-WindowTopmost $window
        return
    }

    if ($null -ne $script:CompactTopmostTimer) {
        $script:CompactTopmostTimer.Stop()
        $script:CompactTopmostTimer = $null
    }

    Set-WindowTopmost $window
}

function Read-Config {
    $config = [pscustomobject]@{}

    if (Test-Path $script:ConfigPath) {
        try {
            $raw = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.Encoding]::UTF8)
            $config = $raw | ConvertFrom-Json
        } catch {
            $config = [pscustomobject]@{}
        }
    }

    if (Test-Path $script:LocalConfigPath) {
        try {
            $raw = [System.IO.File]::ReadAllText($script:LocalConfigPath, [System.Text.Encoding]::UTF8)
            $localConfig = $raw | ConvertFrom-Json
            $config = Merge-ConfigObject $config $localConfig
        } catch {
        }
    }

    return $config
}

function Build-ProviderContextMenu($window, $controls) {
    $menu = New-Object System.Windows.Controls.ContextMenu

    foreach ($providerId in (Get-ProviderIds)) {
        if (-not [bool](Get-ObjectValue $script:ProviderEnabledMap $providerId $false)) {
            continue
        }

        $metadata = Get-ProviderMetadata $providerId
        $item = New-Object System.Windows.Controls.MenuItem
        $item.Header = "Show {0}" -f $metadata.label
        $item.IsCheckable = $true
        $item.IsChecked = Test-ProviderVisible $providerId
        $item.Tag = $providerId
        $item.Add_Click({
            param($sender)
            $targetProviderId = [string]$sender.Tag
            $currentlyVisible = Test-ProviderVisible $targetProviderId
            if ($currentlyVisible -and -not (Test-CanHideProvider $targetProviderId)) {
                return
            }

            Set-ProviderVisible $targetProviderId (-not $currentlyVisible)
            $script:CodexEnabled = Test-ProviderVisible "codex"
            $script:MinimaxEnabled = Test-ProviderVisible "minimax"
            Sync-ProviderVisibility $controls
            Sync-ProviderState
        })
        $menu.Items.Add($item) | Out-Null
    }

    $separator = New-Object System.Windows.Controls.Separator

    $displayLeftItem = New-Object System.Windows.Controls.MenuItem
    $displayLeftItem.Header = Get-UsageDisplayToggleLabel
    $displayLeftItem.Add_Click({
        $script:UsageDisplayMode = if ((Normalize-UsageDisplayMode $script:UsageDisplayMode) -eq "left") { "used" } else { "left" }
        if (-not (Apply-CachedUsageSnapshot $controls $script:UsageSnapshot)) {
            Update-Widget $controls
        }
        Sync-ProviderState
    })

    $topmostItem = New-Object System.Windows.Controls.MenuItem
    $topmostItem.Header = "Always on Top"
    $topmostItem.IsCheckable = $true
    $topmostItem.IsChecked = ($script:CompactMode -or $script:TopmostEnabled)
    $topmostItem.IsEnabled = -not $script:CompactMode
    $topmostItem.Add_Click({
        $script:TopmostEnabled = -not $script:TopmostEnabled
        Set-WindowTopmost $window
        Sync-ProviderState
    })

    $exitItem = New-Object System.Windows.Controls.MenuItem
    $exitItem.Header = "Exit"
    $exitItem.Add_Click({
        $window.Close()
    })

    $menu.Items.Add($separator) | Out-Null
    $menu.Items.Add($displayLeftItem) | Out-Null
    $menu.Items.Add($topmostItem) | Out-Null
    $menu.Items.Add($exitItem) | Out-Null

    return $menu
}

function Sync-ProviderVisibility($controls) {
    if ((Get-VisibleProviderIds).Count -eq 0) {
        foreach ($providerId in (Get-ProviderIds)) {
            if ([bool](Get-ObjectValue $script:ProviderEnabledMap $providerId $false)) {
                Set-ProviderVisible $providerId $true
                break
            }
        }
    }

    $script:CodexEnabled = Test-ProviderVisible "codex"
    $script:MinimaxEnabled = Test-ProviderVisible "minimax"

    $visibleIds = Get-VisibleProviderIds
    $compactColumns = (Get-CompactLayoutMetrics $visibleIds.Count).Columns
    foreach ($providerId in (Get-ProviderIds)) {
        $isVisible = $visibleIds -contains $providerId
        $fullControl = Get-ObjectValue $controls.ProviderSections $providerId $null
        $compactControl = Get-ObjectValue $controls.CompactProviders $providerId $null

        if ($fullControl) {
            $fullControl.Section.Visibility = if ($isVisible) { "Visible" } else { "Collapsed" }
            $fullControl.Section.Margin = if ($isVisible -and $providerId -ne $visibleIds[-1]) { "0,0,0,8" } else { "0,0,0,0" }
        }

        if ($compactControl) {
            $compactControl.panel.Visibility = if ($isVisible) { "Visible" } else { "Collapsed" }
            if ($isVisible) {
                $visibleIndex = [Array]::IndexOf($visibleIds, $providerId)
                $columnIndex = if ($compactColumns -gt 0) { $visibleIndex % $compactColumns } else { 0 }
                $rowIndex = if ($compactColumns -gt 0) { [Math]::Floor($visibleIndex / $compactColumns) } else { 0 }
                $leftMargin = if ($columnIndex -gt 0) { 8 } else { 0 }
                $topMargin = if ($rowIndex -gt 0) { 6 } else { 0 }
                $compactControl.panel.Margin = "{0},{1},0,0" -f $leftMargin, $topMargin
                $compactControl.panel.BorderThickness = if ($compactColumns -gt 1 -and $columnIndex -gt 0) { "1,0,0,0" } else { "0" }
                $compactControl.panel.BorderBrush = Get-Brush "#53636D"
                $compactControl.panel.BorderBrush.Opacity = 0.45
            } else {
                $compactControl.panel.Margin = "0"
                $compactControl.panel.BorderThickness = 0
            }
        }
    }

    $controls.CompactContent.Columns = $compactColumns
    Set-WidgetMode $controls.Window $controls $script:CompactMode $false
    Sync-HoverDetailVisibility $controls
}

function Sync-ProviderState {
    $state = Read-State
    foreach ($providerId in (Get-ProviderIds)) {
        $state.providers[$providerId] = [bool](Get-ObjectValue $script:ProviderVisibility $providerId $false)
    }
    $state | Add-Member -MemberType NoteProperty -Name compactMode -Value $script:CompactMode -Force
    $state | Add-Member -MemberType NoteProperty -Name displayMode -Value (Normalize-UsageDisplayMode $script:UsageDisplayMode) -Force
    $state | Add-Member -MemberType NoteProperty -Name topmost -Value $script:TopmostEnabled -Force

    $json = $state | ConvertTo-Json -Depth 8
    try {
        [System.IO.File]::WriteAllText($script:StatePath, $json, [System.Text.Encoding]::UTF8)
    } catch {
    }
}

function Save-State($window) {
    try {
        $providerState = [ordered]@{}
        foreach ($providerId in (Get-ProviderIds)) {
            $providerState[$providerId] = [bool](Get-ObjectValue $script:ProviderVisibility $providerId $false)
        }

        $state = [ordered]@{
            left = [Math]::Round($window.Left)
            top = [Math]::Round($window.Top)
            topmost = [bool]$script:TopmostEnabled
            opacity = 1.0
            refreshSeconds = 3
            compactMode = $script:CompactMode
            displayMode = Normalize-UsageDisplayMode $script:UsageDisplayMode
            usageSnapshot = $script:UsageSnapshot
            usageFloor = [ordered]@{
                windowKey = if ($script:UsageFloorState.WindowKey) { [string]$script:UsageFloorState.WindowKey } else { "" }
                primaryUsed = if ($null -ne $script:UsageFloorState.PrimaryUsed) { [double]$script:UsageFloorState.PrimaryUsed } else { $null }
                secondaryUsed = if ($null -ne $script:UsageFloorState.SecondaryUsed) { [double]$script:UsageFloorState.SecondaryUsed } else { $null }
            }
            providers = $providerState
        }
        $json = $state | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($script:StatePath, $json, [System.Text.Encoding]::UTF8)
    } catch {
    }
}

function Convert-ToDateTimeOrNull($value) {
    if ($null -eq $value) {
        return $null
    }

    if ($value -is [DateTime]) {
        return [DateTime]$value
    }

    if ($value -is [DateTimeOffset]) {
        return ([DateTimeOffset]$value).LocalDateTime
    }

    try {
        return ([DateTimeOffset]::Parse($value.ToString(), [Globalization.CultureInfo]::InvariantCulture)).LocalDateTime
    } catch {
        try {
            return [DateTime]::Parse($value.ToString(), [Globalization.CultureInfo]::InvariantCulture)
        } catch {
            return $null
        }
    }
}

function New-LimitSnapshot($limit) {
    if (-not $limit) {
        return $null
    }

    return [ordered]@{
        used_percent = Convert-ToNumber (Get-ObjectValue $limit "used_percent" 0)
        resets_at = Convert-ToInt64 (Get-ObjectValue $limit "resets_at" 0)
        window_minutes = Convert-ToInt64 (Get-ObjectValue $limit "window_minutes" 0)
        total = Convert-ToNullableNumber (Get-ObjectValue $limit "total" $null)
        remaining = Convert-ToNullableNumber (Get-ObjectValue $limit "remaining" $null)
        used = Convert-ToNullableNumber (Get-ObjectValue $limit "used" $null)
    }
}

function Restore-LimitSnapshot($snapshot) {
    if (-not $snapshot) {
        return $null
    }

    return [pscustomobject]@{
        used_percent = Convert-ToNumber (Get-ObjectValue $snapshot "used_percent" 0)
        resets_at = Convert-ToInt64 (Get-ObjectValue $snapshot "resets_at" 0)
        window_minutes = Convert-ToInt64 (Get-ObjectValue $snapshot "window_minutes" 0)
        total = Convert-ToNullableNumber (Get-ObjectValue $snapshot "total" $null)
        remaining = Convert-ToNullableNumber (Get-ObjectValue $snapshot "remaining" $null)
        used = Convert-ToNullableNumber (Get-ObjectValue $snapshot "used" $null)
    }
}

function New-TokenUsageSnapshot($usage) {
    if (-not $usage) {
        return $null
    }

    return [ordered]@{
        input = Convert-ToInt64 (Get-ObjectValue $usage "input" 0)
        cached = Convert-ToInt64 (Get-ObjectValue $usage "cached" 0)
        output = Convert-ToInt64 (Get-ObjectValue $usage "output" 0)
        reasoning = Convert-ToInt64 (Get-ObjectValue $usage "reasoning" 0)
        total = Convert-ToInt64 (Get-ObjectValue $usage "total" 0)
    }
}

function Restore-TokenUsageSnapshot($snapshot) {
    if (-not $snapshot) {
        return $null
    }

    return [pscustomobject]@{
        input = Convert-ToInt64 (Get-ObjectValue $snapshot "input" 0)
        cached = Convert-ToInt64 (Get-ObjectValue $snapshot "cached" 0)
        output = Convert-ToInt64 (Get-ObjectValue $snapshot "output" 0)
        reasoning = Convert-ToInt64 (Get-ObjectValue $snapshot "reasoning" 0)
        total = Convert-ToInt64 (Get-ObjectValue $snapshot "total" 0)
    }
}

function New-UsageObjectSnapshot($usage) {
    if (-not $usage) {
        return $null
    }

    $updated = Get-ObjectValue $usage "updated" (Get-Date)
    if ($updated -and -not ($updated -is [DateTime]) -and -not ($updated -is [DateTimeOffset])) {
        $updated = Convert-ToDateTimeOrNull $updated
    }
    if (-not $updated) {
        $updated = Get-Date
    }

    return [ordered]@{
        ok = [bool](Get-ObjectValue $usage "ok" $false)
        configured = Get-ObjectValue $usage "configured" $null
        message = Get-ObjectValue $usage "message" $null
        plan = Get-ObjectValue $usage "plan" $null
        source = Get-ObjectValue $usage "source" $null
        limitReachedType = Get-ObjectValue $usage "limitReachedType" $null
        updated = $updated.ToString("o")
        isStale = [bool](Get-ObjectValue $usage "isStale" $false)
        staleText = Get-ObjectValue $usage "staleText" ""
        error = Get-ObjectValue $usage "error" $null
        primaryDelta = Convert-ToNullableNumber (Get-ObjectValue $usage "primaryDelta" $null)
        secondaryDelta = Convert-ToNullableNumber (Get-ObjectValue $usage "secondaryDelta" $null)
        primaryDeltaText = Get-ObjectValue $usage "primaryDeltaText" $null
        secondaryDeltaText = Get-ObjectValue $usage "secondaryDeltaText" $null
        primary = New-LimitSnapshot (Get-ObjectValue $usage "primary" $null)
        secondary = New-LimitSnapshot (Get-ObjectValue $usage "secondary" $null)
    }
}

function Restore-UsageObjectSnapshot($snapshot) {
    if (-not $snapshot) {
        return $null
    }

    $updated = Convert-ToDateTimeOrNull (Get-ObjectValue $snapshot "updated" $null)
    if (-not $updated) {
        $updated = Get-Date
    }

    return [pscustomobject]@{
        ok = [bool](Get-ObjectValue $snapshot "ok" $false)
        configured = Get-ObjectValue $snapshot "configured" $null
        message = Get-ObjectValue $snapshot "message" $null
        plan = Get-ObjectValue $snapshot "plan" $null
        source = Get-ObjectValue $snapshot "source" $null
        limitReachedType = Get-ObjectValue $snapshot "limitReachedType" $null
        updated = $updated
        isStale = [bool](Get-ObjectValue $snapshot "isStale" $false)
        staleText = Get-ObjectValue $snapshot "staleText" ""
        error = Get-ObjectValue $snapshot "error" $null
        primaryDelta = Convert-ToNullableNumber (Get-ObjectValue $snapshot "primaryDelta" $null)
        secondaryDelta = Convert-ToNullableNumber (Get-ObjectValue $snapshot "secondaryDelta" $null)
        primaryDeltaText = Get-ObjectValue $snapshot "primaryDeltaText" $null
        secondaryDeltaText = Get-ObjectValue $snapshot "secondaryDeltaText" $null
        primary = Restore-LimitSnapshot (Get-ObjectValue $snapshot "primary" $null)
        secondary = Restore-LimitSnapshot (Get-ObjectValue $snapshot "secondary" $null)
    }
}

function New-ProviderUsageSnapshotMap($providers) {
    $snapshot = [ordered]@{}

    if (-not $providers) {
        return $snapshot
    }

    foreach ($providerId in (Get-ProviderIds)) {
        if ($providers.Contains($providerId)) {
            $snapshot[$providerId] = New-UsageObjectSnapshot $providers[$providerId]
        }
    }

    return $snapshot
}

function Restore-ProviderUsageSnapshotMap($providers) {
    $restored = [ordered]@{}

    if (-not $providers) {
        return $restored
    }

    foreach ($providerId in (Get-ProviderIds)) {
        $snapshot = Get-ObjectValue $providers $providerId $null
        if ($null -ne $snapshot) {
            $restored[$providerId] = Restore-UsageObjectSnapshot $snapshot
        }
    }

    return $restored
}

function New-UsageSnapshot($codex, $minimax, $activity, $providers = $null) {
    if (-not $providers) {
        $providers = [ordered]@{
            codex = $codex
            minimax = $minimax
        }
    }

    return [ordered]@{
        savedAt = (Get-Date).ToString("o")
        providers = New-ProviderUsageSnapshotMap $providers
        codex = New-UsageObjectSnapshot $codex
        minimax = New-UsageObjectSnapshot $minimax
        activity = [ordered]@{
            latestCall = New-TokenUsageSnapshot (Get-ObjectValue $activity "LatestCall" $null)
            latestTurn = New-TokenUsageSnapshot (Get-ObjectValue $activity "LatestTurn" $null)
            recent = New-TokenUsageSnapshot (Get-ObjectValue $activity "Recent" $null)
            observedAt = if ($activity -and $activity.ObservedAt) { $activity.ObservedAt.ToString("o") } else { $null }
        }
    }
}

function Restore-UsageSnapshot($snapshot) {
    if (-not $snapshot) {
        return $null
    }

    $activity = Get-ObjectValue $snapshot "activity" $null
    $observedAt = if ($activity) { Convert-ToDateTimeOrNull (Get-ObjectValue $activity "observedAt" $null) } else { $null }
    $providers = Restore-ProviderUsageSnapshotMap (Get-ObjectValue $snapshot "providers" $null)
    $codex = if ($providers.Contains("codex")) { $providers["codex"] } else { Restore-UsageObjectSnapshot (Get-ObjectValue $snapshot "codex" $null) }
    $minimax = if ($providers.Contains("minimax")) { $providers["minimax"] } else { Restore-UsageObjectSnapshot (Get-ObjectValue $snapshot "minimax" $null) }
    return [pscustomobject]@{
        Providers = $providers
        Codex = $codex
        Minimax = $minimax
        Activity = [pscustomobject]@{
            LatestCall = Restore-TokenUsageSnapshot (Get-ObjectValue $activity "latestCall" $null)
            LatestTurn = Restore-TokenUsageSnapshot (Get-ObjectValue $activity "latestTurn" $null)
            Recent = Restore-TokenUsageSnapshot (Get-ObjectValue $activity "recent" $null)
            ObservedAt = $observedAt
        }
    }
}

function Restore-GrokRuntimeUsage($snapshot) {
    $restored = Restore-UsageSnapshot $snapshot
    if (-not $restored -or -not $restored.Providers) {
        return $null
    }

    $usage = Get-ObjectValue $restored.Providers "grok" $null
    if ($usage -and $usage.ok -and $usage.primary) {
        $script:GrokRemoteState.Usage = Set-GrokUsageFreshness $usage (Get-GrokSettings).StaleAfterSeconds
        return $script:GrokRemoteState.Usage
    }

    return $null
}

function Initialize-UsageFloorState($state) {
    $script:UsageFloorState = @{
        WindowKey = ""
        PrimaryUsed = $null
        SecondaryUsed = $null
    }

    if (-not $state -or -not $state.usageFloor) {
        return
    }

    $floor = $state.usageFloor
    $script:UsageFloorState.WindowKey = if ($floor.windowKey) { [string]$floor.windowKey } else { "" }
    $script:UsageFloorState.PrimaryUsed = if ($null -ne $floor.primaryUsed) { Convert-ToNumber $floor.primaryUsed } else { $null }
    $script:UsageFloorState.SecondaryUsed = if ($null -ne $floor.secondaryUsed) { Convert-ToNumber $floor.secondaryUsed } else { $null }
}

function Convert-UnixSeconds($seconds) {
    if (-not $seconds) {
        return $null
    }

    return [DateTimeOffset]::FromUnixTimeSeconds([int64]$seconds)
}

function Format-Remaining($resetSeconds) {
    $resetAt = Convert-UnixSeconds $resetSeconds
    if (-not $resetAt) {
        return "reset unknown"
    }

    $span = $resetAt.LocalDateTime - (Get-Date)
    if ($span.TotalSeconds -le 0) {
        return "reset due"
    }

    if ($span.TotalDays -ge 1) {
        return ("{0}d {1}h left" -f [Math]::Floor($span.TotalDays), $span.Hours)
    }

    if ($span.TotalHours -ge 1) {
        return ("{0}h {1}m left" -f [Math]::Floor($span.TotalHours), $span.Minutes)
    }

    return ("{0}m left" -f [Math]::Max(1, [Math]::Ceiling($span.TotalMinutes)))
}

function Get-RemainingSpan($resetSeconds) {
    $resetAt = Convert-UnixSeconds $resetSeconds
    if (-not $resetAt) {
        return $null
    }

    return ($resetAt.LocalDateTime - (Get-Date))
}

function Format-CompactDuration($span) {
    if ($null -eq $span) {
        return "--"
    }

    if ($span.TotalSeconds -le 0) {
        return "0m"
    }

    if ($span.TotalDays -ge 1) {
        $days = [Math]::Floor($span.TotalDays)
        $hours = $span.Hours
        if ($hours -gt 0) {
            return "{0}d{1}h" -f $days, $hours
        }
        return "{0}d" -f $days
    }

    if ($span.TotalHours -ge 1) {
        return "{0}h{1}m" -f [Math]::Floor($span.TotalHours), $span.Minutes
    }

    return "{0}m" -f [Math]::Max(1, [Math]::Ceiling($span.TotalMinutes))
}

function Format-ResetLabel($resetSeconds) {
    $resetAt = Convert-UnixSeconds $resetSeconds
    if (-not $resetAt) {
        return "↻ --"
    }

    return ("↻ {0}" -f $resetAt.LocalDateTime.ToString("MMM d, h:mm tt", [Globalization.CultureInfo]::InvariantCulture))
}

function Format-CompactRemaining($resetSeconds, $icon = "↻") {
    $value = Format-CompactDuration (Get-RemainingSpan $resetSeconds)
    if ([string]::IsNullOrWhiteSpace($icon)) {
        return $value
    }

    return "$icon $value"
}

function Get-UsageProjection($limit) {
    if (-not $limit) {
        return [pscustomobject]@{
            Ready = $false
            ElapsedPercent = 0
            ProjectedUsedPercent = $null
        }
    }

    $elapsedPercent = [Math]::Max([double]0, [Math]::Min([double]100, (Get-ElapsedPercent $limit)))
    if ($elapsedPercent -lt 5) {
        return [pscustomobject]@{
            Ready = $false
            ElapsedPercent = $elapsedPercent
            ProjectedUsedPercent = $null
        }
    }

    $usedPercent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$limit.used_percent))
    $projected = [Math]::Max([double]0, [Math]::Min([double]100, ($usedPercent / $elapsedPercent) * 100))
    return [pscustomobject]@{
        Ready = $true
        ElapsedPercent = $elapsedPercent
        ProjectedUsedPercent = [Math]::Round($projected)
    }
}

function Get-StatusPalette($state) {
    switch ($state) {
        "wait" {
            return [pscustomobject]@{
                Foreground = "#FFD4B5"
                Border = "#FF8A3D"
                Background = "#332319"
            }
        }
        "low" {
            return [pscustomobject]@{
                Foreground = "#F5E1A0"
                Border = "#FFC857"
                Background = "#312A16"
            }
        }
        "reset_soon" {
            return [pscustomobject]@{
                Foreground = "#FFD4B5"
                Border = "#FF8A3D"
                Background = "#332319"
            }
        }
        default {
            return [pscustomobject]@{
                Foreground = "#DDE8ED"
                Border = "#6C7E89"
                Background = "#1A242D"
            }
        }
    }
}

function Get-UsageStatus($limit, $isStale = $false, $limitReachedType = $null, $projection = $null) {
    if (-not $limit) {
        return [pscustomobject]@{
            State = "wait"
            Label = "WAIT"
            Icon = "■"
            ChipText = "■ WAIT"
            CountdownText = $null
            Palette = Get-StatusPalette "wait"
        }
    }

    if ($null -eq $projection) {
        $projection = Get-UsageProjection $limit
    }

    $remainingSpan = Get-RemainingSpan $limit.resets_at
    $remainingMinutes = if ($remainingSpan) { [Math]::Max(0, [Math]::Floor($remainingSpan.TotalMinutes)) } else { [int]::MaxValue }
    $usedPercent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$limit.used_percent))

    if (-not [string]::IsNullOrWhiteSpace($limitReachedType) -or $usedPercent -ge 100) {
        $countdown = if ($remainingSpan) { Format-CompactRemaining $limit.resets_at "⏳" } else { $null }
        return [pscustomobject]@{
            State = "wait"
            Label = "WAIT"
            Icon = "⏳"
            ChipText = if ($countdown) { $countdown } else { "■ WAIT" }
            CountdownText = $countdown
            Palette = Get-StatusPalette "wait"
        }
    }

    if ($remainingMinutes -le 30) {
        return [pscustomobject]@{
            State = "reset_soon"
            Label = "RESET SOON"
            Icon = "↻"
            ChipText = "↻ RESET SOON"
            CountdownText = $null
            Palette = Get-StatusPalette "reset_soon"
        }
    }

    $isLow = $usedPercent -ge 75 -or ($projection -and $projection.Ready -and $projection.ProjectedUsedPercent -ge 90) -or ($isStale -and $usedPercent -ge 85)
    if ($isLow) {
        return [pscustomobject]@{
            State = "low"
            Label = "LOW"
            Icon = "▲"
            ChipText = "▲ LOW"
            CountdownText = $null
            Palette = Get-StatusPalette "low"
        }
    }

    return [pscustomobject]@{
        State = "ok"
        Label = "OK"
        Icon = "●"
        ChipText = "● OK"
        CountdownText = $null
        Palette = Get-StatusPalette "ok"
    }
}

function Get-WeeklyHintLimit($providerId, $usage) {
    if (-not $usage) {
        return $null
    }

    if ($usage.secondary) {
        return $usage.secondary
    }

    if (-not $usage.primary) {
        return $null
    }

    $metadata = Get-ObjectValue $script:ProviderMetadata $providerId $null
    $defaultWindows = @()
    if ($metadata) {
        $defaultWindows = @(Get-ObjectValue $metadata "defaultWindows" @())
    }

    if ($defaultWindows.Count -eq 1 -and $defaultWindows[0] -eq "Weekly") {
        return $usage.primary
    }

    $windowMinutes = Convert-ToInt64 (Get-ObjectValue $usage.primary "window_minutes" 0)
    if ($windowMinutes -ge 8640) {
        return $usage.primary
    }

    return $null
}

function Get-WeeklyHint($providerId, $usage, $limitReachedType = $null) {
    if (-not $usage -or -not $usage.ok) {
        return [pscustomobject]@{
            Text = "No weekly limit data."
            Color = "#D6E2E8"
            ToolTip = $null
        }
    }

    $weekly = Get-WeeklyHintLimit $providerId $usage
    if (-not $weekly) {
        return [pscustomobject]@{
            Text = "No weekly limit data."
            Color = "#D6E2E8"
            ToolTip = $null
        }
    }

    if ($usage.isStale) {
        return [pscustomobject]@{
            Text = "Waiting for fresh data."
            Color = "#FFC857"
            ToolTip = $null
        }
    }

    $weeklyUsedPercent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$weekly.used_percent))
    if (-not [string]::IsNullOrWhiteSpace($limitReachedType) -or $weeklyUsedPercent -ge 100) {
        return [pscustomobject]@{
            Text = "Weekly limit reached, wait for reset."
            Color = "#FF8A3D"
            ToolTip = $null
        }
    }

    $remainingSpan = Get-RemainingSpan $weekly.resets_at
    if ($remainingSpan -and $remainingSpan.TotalHours -le 6) {
        $text = if ($weeklyUsedPercent -ge 80) {
            "Reset is soon, heavy tasks can wait."
        } else {
            "Reset is soon, you are fine."
        }

        return [pscustomobject]@{
            Text = $text
            Color = "#FFD4B5"
            ToolTip = $null
        }
    }

    $windowMinutes = Convert-ToInt64 (Get-ObjectValue $weekly "window_minutes" 0)
    $timingReady = $false
    $elapsedPercent = 0
    $weeklyEndEstimate = $null
    $safeDelta = $null
    if ($remainingSpan -and $windowMinutes -gt 0) {
        $elapsedPercent = [Math]::Max([double]0, [Math]::Min([double]100, 100 - (Get-TimeLeftPercent $weekly)))
        if ($elapsedPercent -ge 5) {
            $timingReady = $true
            $weeklyEndEstimate = [Math]::Max([double]0, [Math]::Min([double]150, ($weeklyUsedPercent / $elapsedPercent) * 100))
            $safeDelta = $weeklyUsedPercent - ($elapsedPercent * 0.90)
        }
    }

    $text = $null
    $color = "#D6E2E8"
    if (-not $timingReady) {
        if ($weeklyUsedPercent -lt 50) {
            $text = "Plenty of room for normal use."
        } elseif ($weeklyUsedPercent -lt 75) {
            $text = "Still healthy, keep using normally."
        } elseif ($weeklyUsedPercent -lt 90) {
            $text = "Use a bit slower, this week may get tight."
            $color = "#FFC857"
        } else {
            $text = "Save it for important tasks this week."
            $color = "#FF8A3D"
        }
    } else {
        if ($weeklyUsedPercent -ge 95) {
            $text = "Save it for important tasks this week."
            $color = "#FF8A3D"
        } elseif ($weeklyUsedPercent -ge 85) {
            $text = "Use a bit slower, this week may get tight."
            $color = "#FFC857"
        } elseif ($weeklyEndEstimate -ge 95) {
            $text = "Use a bit slower, this week may get tight."
            $color = "#FFC857"
        } elseif ($safeDelta -ge 10) {
            $text = "Use a bit slower, this week may get tight."
            $color = "#FFC857"
        } elseif ($weeklyUsedPercent -lt 50 -and $weeklyEndEstimate -lt 80) {
            $text = "Plenty of room for normal use."
        } else {
            $text = "Still healthy, keep using normally."
        }
    }

    $tooltipLines = @(
        ("Weekly used: {0:N0}%" -f $weeklyUsedPercent)
    )

    if ($null -ne $weeklyEndEstimate) {
        $tooltipLines += ("By reset: {0:N0}%" -f [Math]::Round($weeklyEndEstimate))
    }

    $resetAt = Convert-UnixSeconds $weekly.resets_at
    if ($resetAt) {
        $tooltipLines += ("Reset: {0}" -f $resetAt.LocalDateTime.ToString("MMM d, h:mm tt", [Globalization.CultureInfo]::InvariantCulture))
    }

    return [pscustomobject]@{
        Text = $text
        Color = $color
        ToolTip = ($tooltipLines -join [Environment]::NewLine)
    }
}

function Get-ProviderHint($providerId, $usage, $limitReachedType = $null) {
    return Get-WeeklyHint $providerId $usage $limitReachedType
}

function Get-TimeLeftPercent($limit) {
    if (-not $limit -or -not $limit.resets_at -or -not $limit.window_minutes) {
        return 0
    }

    $resetAt = Convert-UnixSeconds $limit.resets_at
    if (-not $resetAt) {
        return 0
    }

    $remainingSeconds = ($resetAt.LocalDateTime - (Get-Date)).TotalSeconds
    $windowSeconds = [double]$limit.window_minutes * 60
    if ($windowSeconds -le 0) {
        return 0
    }

    return [Math]::Max([double]0, [Math]::Min([double]100, ($remainingSeconds / $windowSeconds) * 100))
}

function Get-ElapsedPercent($limit) {
    return 100 - (Get-TimeLeftPercent $limit)
}

function Get-UsageHint($primary, $secondary, $isStale, $limitReachedType = $null) {
    return Get-ProviderHint "codex" ([pscustomobject]@{
            ok = ($null -ne $primary)
            primary = $primary
            secondary = $secondary
            isStale = $isStale
        }) $limitReachedType
}

function Convert-ToNumber($value) {
    if ($null -eq $value) {
        return 0
    }

    try {
        return [double]$value
    } catch {
        return 0
    }
}

function Convert-ToInt64($value) {
    if ($null -eq $value) {
        return [int64]0
    }

    try {
        return [int64]$value
    } catch {
        return [int64]0
    }
}

function Convert-ToNullableNumber($value) {
    if ($null -eq $value) {
        return $null
    }

    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    try {
        return [double]$value
    } catch {
        return $null
    }
}

function Convert-ToBoolean($value, $default) {
    if ($null -eq $value) {
        return [bool]$default
    }

    if ($value -is [bool]) {
        return [bool]$value
    }

    $text = $value.ToString().Trim().ToLowerInvariant()
    if (@("1", "true", "yes", "on") -contains $text) {
        return $true
    }

    if (@("0", "false", "no", "off") -contains $text) {
        return $false
    }

    return [bool]$default
}

function Get-EnvValue($name) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value
}

function Get-FirstObjectValue($object, [string[]]$names) {
    foreach ($name in $names) {
        $value = Get-ObjectValue $object $name $null
        if ($null -ne $value) {
            if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
                continue
            }

            return $value
        }
    }

    return $null
}

function Get-FirstNumberValue($object, [string[]]$names) {
    foreach ($name in $names) {
        $value = Convert-ToNullableNumber (Get-ObjectValue $object $name $null)
        if ($null -ne $value) {
            return $value
        }
    }

    return $null
}

function Get-FirstStringValue($object, [string[]]$names) {
    foreach ($name in $names) {
        $value = Get-ObjectValue $object $name $null
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace($value.ToString())) {
            return $value.ToString()
        }
    }

    return $null
}

function Get-MinimaxRemoteSettings {
    $config = Read-Config
    $minimax = Get-ObjectValue $config "minimax" $null

    $envUrl = Get-EnvValue "MINIMAX_QUOTA_URL"
    $url = $envUrl
    if (-not $url) {
        $url = Get-FirstObjectValue $minimax @("url", "quotaUrl", "endpoint")
    }

    $envSource = Get-EnvValue "MINIMAX_QUOTA_SOURCE"
    $source = $envSource
    if (-not $source) {
        $source = Get-FirstStringValue $minimax @("source", "mode")
    }

    $envFilePath = Get-EnvValue "MINIMAX_QUOTA_FILE"
    $filePath = $envFilePath
    if (-not $filePath) {
        $filePath = Get-FirstObjectValue $minimax @("file", "filePath", "jsonPath")
    }

    $envSshCommand = Get-EnvValue "MINIMAX_QUOTA_SSH_COMMAND"
    $sshCommand = $envSshCommand
    if (-not $sshCommand) {
        $sshCommand = Get-FirstObjectValue $minimax @("sshCommand")
    }

    $envSshTarget = Get-EnvValue "MINIMAX_QUOTA_SSH_TARGET"
    $sshTarget = $envSshTarget
    if (-not $sshTarget) {
        $sshTarget = Get-FirstObjectValue $minimax @("sshTarget", "sshHost", "ssh")
    }

    $authToken = Get-EnvValue "MINIMAX_QUOTA_TOKEN"
    if (-not $authToken) {
        $authToken = Get-EnvValue "MINIMAX_TOKEN_PLAN_KEY"
    }
    if (-not $authToken) {
        $authToken = Get-EnvValue "MINIMAX_API_KEY"
    }
    if (-not $authToken) {
        $authToken = Get-FirstObjectValue $minimax @("authToken", "token", "tokenPlanKey", "apiKey")
    }

    if (-not $source) {
        if ($filePath) {
            $source = "file"
        } elseif ($sshCommand -or $sshTarget) {
            $source = "ssh"
        } elseif ($authToken) {
            $source = "token_plan"
        } else {
            $source = "http"
        }
    }

    $normalizedSource = $source.ToString().ToLowerInvariant()
    if (-not $url -and ($normalizedSource -in @("token_plan", "token-plan", "api"))) {
        $url = $script:MinimaxTokenPlanUrl
    }

    $enabledValue = Get-EnvValue "MINIMAX_QUOTA_ENABLED"
    $envHasSource = ($envUrl -or $envFilePath -or $envSshCommand -or $envSshTarget -or $authToken)
    if (-not $enabledValue -and -not $envHasSource) {
        $enabledValue = Get-ObjectValue $minimax "enabled" $null
    }

    $hasSource = ($url -or $filePath -or $sshCommand -or $sshTarget -or $authToken)
    $enabled = Convert-ToBoolean $enabledValue $hasSource

    $refreshSeconds = Convert-ToNullableNumber (Get-EnvValue "MINIMAX_QUOTA_REFRESH_SECONDS")
    if ($null -eq $refreshSeconds) {
        $refreshSeconds = Convert-ToNullableNumber (Get-ObjectValue $minimax "refreshSeconds" $script:MinimaxDefaultRefreshSeconds)
    }
    if ($null -eq $refreshSeconds -or $refreshSeconds -le 0) {
        $refreshSeconds = $script:MinimaxDefaultRefreshSeconds
    }

    $timeoutSeconds = Convert-ToNullableNumber (Get-EnvValue "MINIMAX_QUOTA_TIMEOUT_SECONDS")
    if ($null -eq $timeoutSeconds) {
        $timeoutSeconds = Convert-ToNullableNumber (Get-ObjectValue $minimax "timeoutSeconds" 10)
    }
    if ($null -eq $timeoutSeconds -or $timeoutSeconds -le 0) {
        $timeoutSeconds = 10
    }

    $authHeaderName = Get-EnvValue "MINIMAX_QUOTA_AUTH_HEADER"
    if (-not $authHeaderName) {
        $authHeaderName = Get-FirstObjectValue $minimax @("authHeaderName", "tokenHeader")
    }
    if (-not $authHeaderName) {
        $authHeaderName = "Authorization"
    }

    $authHeaderScheme = Get-EnvValue "MINIMAX_QUOTA_AUTH_SCHEME"
    if (-not $authHeaderScheme) {
        $authHeaderScheme = Get-FirstObjectValue $minimax @("authHeaderScheme")
    }
    if ($null -eq $authHeaderScheme) {
        $authHeaderScheme = "Bearer"
    }

    $sshPath = Get-EnvValue "MINIMAX_QUOTA_SSH_PATH"
    if (-not $sshPath) {
        $sshPath = Get-FirstObjectValue $minimax @("sshPath")
    }
    if (-not $sshPath) {
        $sshPath = "ssh"
    }

    $sshRemoteCommand = Get-EnvValue "MINIMAX_QUOTA_SSH_REMOTE_COMMAND"
    if (-not $sshRemoteCommand) {
        $sshRemoteCommand = Get-FirstObjectValue $minimax @("sshRemoteCommand", "remoteCommand")
    }
    if (-not $sshRemoteCommand) {
        $sshRemoteCommand = "mmx quota --output json --non-interactive"
    }

    $modelPattern = Get-EnvValue "MINIMAX_QUOTA_MODEL_PATTERN"
    if (-not $modelPattern) {
        $modelPattern = Get-FirstObjectValue $minimax @("modelPattern", "quotaModelPattern")
    }
    if (-not $modelPattern) {
        $modelPattern = "general"
    }

    return [pscustomobject]@{
        Enabled = [bool]$enabled
        Source = $normalizedSource
        Url = if ($url) { $url.ToString() } else { "" }
        FilePath = if ($filePath) { $filePath.ToString() } else { "" }
        AuthToken = if ($authToken) { $authToken.ToString() } else { "" }
        AuthHeaderName = $authHeaderName.ToString()
        AuthHeaderScheme = if ($authHeaderScheme) { $authHeaderScheme.ToString() } else { "" }
        RefreshSeconds = [int][Math]::Max(10, [Math]::Round([double]$refreshSeconds))
        TimeoutSeconds = [int][Math]::Max(2, [Math]::Round([double]$timeoutSeconds))
        SshCommand = if ($sshCommand) { $sshCommand.ToString() } else { "" }
        SshPath = $sshPath.ToString()
        SshTarget = if ($sshTarget) { $sshTarget.ToString() } else { "" }
        SshRemoteCommand = $sshRemoteCommand.ToString()
        ModelPattern = $modelPattern.ToString()
    }
}

function Quote-ProcessArgument($value) {
    if ($null -eq $value) {
        return '""'
    }

    $text = $value.ToString()
    if ($text -notmatch '[\s"]') {
        return $text
    }

    return '"' + $text.Replace('"', '\"') + '"'
}

function Invoke-ExternalTextCommand($fileName, $arguments, $timeoutSeconds) {
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $fileName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true

    $process.Start() | Out-Null
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit([int]($timeoutSeconds * 1000))
    if (-not $completed) {
        try {
            $process.Kill()
        } catch {
        }
        throw "Minimax quota command timed out."
    }

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if ($process.ExitCode -ne 0) {
        $message = if ($stderr) { $stderr.Trim() } else { "exit code $($process.ExitCode)" }
        throw "Minimax quota command failed: $message"
    }

    return $stdout
}

function Invoke-MinimaxHttpQuota($settings) {
    if (-not $settings.Url) {
        throw "Minimax HTTP quota URL is not configured."
    }

    $headers = @{}
    if ($settings.AuthToken) {
        $scheme = $settings.AuthHeaderScheme
        if ($settings.AuthHeaderName -eq "Authorization" -and $scheme -and $scheme.ToLowerInvariant() -ne "none") {
            $headers[$settings.AuthHeaderName] = ("{0} {1}" -f $scheme, $settings.AuthToken)
        } else {
            $headers[$settings.AuthHeaderName] = $settings.AuthToken
        }
    }

    return Invoke-RestMethod -Method Get -Uri $settings.Url -Headers $headers -TimeoutSec $settings.TimeoutSeconds
}

function Invoke-MinimaxSshQuota($settings) {
    if ($settings.SshCommand) {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -Command " + (Quote-ProcessArgument $settings.SshCommand)
        $stdout = Invoke-ExternalTextCommand "powershell.exe" $arguments $settings.TimeoutSeconds
        return $stdout | ConvertFrom-Json
    }

    if (-not $settings.SshTarget) {
        throw "Minimax SSH target is not configured."
    }

    $arguments = (Quote-ProcessArgument $settings.SshTarget) + " " + (Quote-ProcessArgument $settings.SshRemoteCommand)
    $stdout = Invoke-ExternalTextCommand $settings.SshPath $arguments $settings.TimeoutSeconds
    return $stdout | ConvertFrom-Json
}

function Invoke-MinimaxQuotaRaw($settings) {
    switch ($settings.Source) {
        "ssh" {
            return Invoke-MinimaxSshQuota $settings
        }
        "file" {
            if (-not $settings.FilePath -or -not (Test-Path $settings.FilePath)) {
                throw "Minimax quota file is not configured or does not exist."
            }

            return ([System.IO.File]::ReadAllText($settings.FilePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
        }
        "token_plan" {
            return Invoke-MinimaxHttpQuota $settings
        }
        "token-plan" {
            return Invoke-MinimaxHttpQuota $settings
        }
        "api" {
            return Invoke-MinimaxHttpQuota $settings
        }
        default {
            return Invoke-MinimaxHttpQuota $settings
        }
    }
}

function Convert-MinimaxTimestamp($value) {
    if ($null -eq $value) {
        return [int64]0
    }

    if ($value -is [DateTime]) {
        return ([DateTimeOffset]$value).ToUnixTimeSeconds()
    }

    $number = Convert-ToNullableNumber $value
    if ($null -ne $number) {
        if ($number -le 0) {
            return [int64]0
        }

        if ($number -gt 9999999999) {
            return [int64][Math]::Floor($number / 1000)
        }

        return [int64][Math]::Floor($number)
    }

    try {
        return ([DateTimeOffset]::Parse($value.ToString())).ToUnixTimeSeconds()
    } catch {
        return [int64]0
    }
}

function Convert-MinimaxDurationSeconds($value, $defaultWindowMinutes) {
    $number = Convert-ToNullableNumber $value
    if ($null -eq $number -or $number -le 0) {
        return $null
    }

    $windowSeconds = [Math]::Max(1, [double]$defaultWindowMinutes * 60)
    if ($number -gt ($windowSeconds * 2)) {
        return [double]$number / 1000
    }

    return [double]$number
}

function Get-MinimaxPayloadRoot($raw) {
    $current = $raw
    for ($index = 0; $index -lt 3; $index++) {
        $child = Get-FirstObjectValue $current @("data", "quota", "quotas", "usage", "result")
        if ($null -eq $child -or $child -is [string]) {
            break
        }

        $current = $child
    }

    return $current
}

function Get-MinimaxModelQuotaObject($root, $modelPattern) {
    $items = Get-FirstObjectValue $root @("model_remains", "modelRemains", "models")
    if (-not $items) {
        return $null
    }

    $usableItems = @($items) | Where-Object {
        (Get-FirstNumberValue $_ @("current_interval_total_count", "current_weekly_total_count", "total_count", "total")) -ne $null
    }

    if ($modelPattern) {
        $matched = $usableItems | Where-Object {
            $modelName = Get-FirstStringValue $_ @("model_name", "modelName", "name")
            $modelName -and ($modelName -like $modelPattern)
        }
        if ($matched) {
            $usableItems = $matched
        } else {
            $general = $usableItems | Where-Object {
                $modelName = Get-FirstStringValue $_ @("model_name", "modelName", "name")
                $modelName -and ($modelName -ieq "general")
            }
            if ($general) {
                $usableItems = $general
            }
        }
    }

    $usable = $usableItems | Sort-Object {
        $total = Get-FirstNumberValue $_ @("current_interval_total_count", "current_weekly_total_count", "total_count", "total")
        if ($null -eq $total) { 0 } else { $total }
    } -Descending | Select-Object -First 1

    return $usable
}

function Convert-MinimaxQuotaWindow($source, $prefix, $defaultWindowMinutes, $allowGenericTime) {
    if (-not $source) {
        return $null
    }

    $total = Get-FirstNumberValue $source @("${prefix}_total_count", "total_count", "total", "limit", "entitlement", "quota")
    $used = Get-FirstNumberValue $source @(
        "${prefix}_usage_count",
        "${prefix}_used_count",
        "usage_count",
        "used_count",
        "used"
    )
    $remaining = Get-FirstNumberValue $source @(
        "${prefix}_remaining_count",
        "${prefix}_remains_count",
        "${prefix}_left_count",
        "remaining_count",
        "remaining",
        "remains",
        "left"
    )

    if ($null -eq $used -and $null -ne $total -and $null -ne $remaining) {
        $used = [Math]::Max(0, $total - $remaining)
    }

    if ($null -eq $remaining -and $null -ne $total -and $null -ne $used) {
        $remaining = [Math]::Max(0, $total - $used)
    }

    $percent = $null
    if ($null -ne $used -and $null -ne $total -and $total -gt 0) {
        $percent = ($used / $total) * 100
    } else {
        $percent = Get-FirstNumberValue $source @("${prefix}_used_percent", "used_percent", "usage_percent", "usagePercentage")
    }
    if ($null -eq $percent) {
        $remainingPercent = Get-FirstNumberValue $source @("${prefix}_remaining_percent", "${prefix}_remains_percent", "remaining_percent", "remains_percent", "left_percent")
        if ($null -ne $remainingPercent) {
            $percent = 100 - $remainingPercent
        }
    }

    if ($null -eq $percent) {
        return $null
    }

    $endNames = @("${prefix}_end_time", "${prefix}_reset_at", "${prefix}_resets_at", "${prefix}_reset_time")
    $startNames = @("${prefix}_start_time", "${prefix}_starts_at", "${prefix}_started_at")
    $durationNames = @("${prefix}_remains_time", "${prefix}_remaining_time", "${prefix}_ttl_seconds")
    if ($prefix -eq "current_weekly") {
        $endNames += @("weekly_end_time", "week_end_time")
        $startNames += @("weekly_start_time", "week_start_time")
        $durationNames += @("weekly_remains_time", "weekly_remaining_time", "week_remains_time")
    }
    if ($allowGenericTime) {
        $endNames += @("end_time", "reset_at", "resets_at", "reset_time", "endAt")
        $startNames += @("start_time", "starts_at", "started_at", "startAt")
        $durationNames += @("remains_time", "remaining_time", "time_remaining", "ttl_seconds")
    }

    $resetSeconds = Convert-MinimaxTimestamp (Get-FirstObjectValue $source $endNames)
    if ($resetSeconds -le 0) {
        $durationSeconds = Convert-MinimaxDurationSeconds (Get-FirstObjectValue $source $durationNames) $defaultWindowMinutes
        if ($null -ne $durationSeconds -and $durationSeconds -gt 0) {
            $resetSeconds = [DateTimeOffset]::Now.AddSeconds($durationSeconds).ToUnixTimeSeconds()
        }
    }
    if ($resetSeconds -le 0) {
        $startSeconds = Convert-MinimaxTimestamp (Get-FirstObjectValue $source $startNames)
        if ($startSeconds -gt 0 -and $defaultWindowMinutes -gt 0) {
            $resetSeconds = [int64]($startSeconds + ([double]$defaultWindowMinutes * 60))
        }
    }

    return [pscustomobject]@{
        used_percent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$percent))
        resets_at = $resetSeconds
        window_minutes = $defaultWindowMinutes
        total = if ($null -ne $total) { [double]$total } else { $null }
        remaining = if ($null -ne $remaining) { [double]$remaining } else { $null }
        used = if ($null -ne $used) { [double]$used } else { $null }
    }
}

function Convert-MinimaxQuota($raw, $sourceName, $modelPattern = "general") {
    $root = Get-MinimaxPayloadRoot $raw
    $model = Get-MinimaxModelQuotaObject $root $modelPattern
    $primarySource = if ($model) { $model } else { $root }

    $intervalSource = Get-FirstObjectValue $root @("interval", "current_interval", "session", "five_hour", "rolling_interval")
    if (-not $intervalSource) {
        $intervalSource = $primarySource
    }

    $weeklySource = Get-FirstObjectValue $root @("weekly", "current_weekly", "week")
    if (-not $weeklySource) {
        $weeklySource = $primarySource
    }

    $sameSource = [Object]::ReferenceEquals($intervalSource, $weeklySource)
    $interval = Convert-MinimaxQuotaWindow $intervalSource "current_interval" 300 $true
    $weekly = Convert-MinimaxQuotaWindow $weeklySource "current_weekly" 10080 (-not $sameSource)

    if (-not $interval -or -not $weekly) {
        throw "Minimax quota JSON does not contain usable interval and weekly counts."
    }

    $plan = Get-FirstStringValue $primarySource @("current_subscribe_title", "subscribe_title", "plan_name", "plan", "title", "name", "model_name")
    if (-not $plan) {
        $plan = Get-FirstStringValue $root @("current_subscribe_title", "subscribe_title", "plan_name", "plan", "title", "name")
    }

    return [pscustomobject]@{
        ok = $true
        message = $null
        plan = if ($plan) { $plan } else { "Minimax" }
        source = $sourceName
        updated = Get-Date
        isStale = $false
        error = $null
        primary = $interval
        secondary = $weekly
    }
}

function Convert-ToTokenUsage($usage) {
    if (-not $usage) {
        return $null
    }

    return [pscustomobject]@{
        input = Convert-ToInt64 $usage.input_tokens
        cached = Convert-ToInt64 $usage.cached_input_tokens
        output = Convert-ToInt64 $usage.output_tokens
        reasoning = Convert-ToInt64 $usage.reasoning_output_tokens
        total = Convert-ToInt64 $usage.total_tokens
    }
}

function Get-TokenDelta($current, $previous) {
    if (-not $current) {
        return $null
    }

    if (-not $previous) {
        return $current
    }

    return [pscustomobject]@{
        input = [Math]::Max(0, $current.input - $previous.input)
        cached = [Math]::Max(0, $current.cached - $previous.cached)
        output = [Math]::Max(0, $current.output - $previous.output)
        reasoning = [Math]::Max(0, $current.reasoning - $previous.reasoning)
        total = [Math]::Max(0, $current.total - $previous.total)
    }
}

function Add-TokenUsage($left, $right) {
    if (-not $left) {
        $left = [pscustomobject]@{ input = 0; cached = 0; output = 0; reasoning = 0; total = 0 }
    }

    if (-not $right) {
        return $left
    }

    return [pscustomobject]@{
        input = $left.input + $right.input
        cached = $left.cached + $right.cached
        output = $left.output + $right.output
        reasoning = $left.reasoning + $right.reasoning
        total = $left.total + $right.total
    }
}

function Format-TokenCount($value) {
    $number = [double](Convert-ToInt64 $value)
    $absolute = [Math]::Abs($number)
    $prefix = if ($number -lt 0) { "-" } else { "" }
    $culture = [Globalization.CultureInfo]::InvariantCulture

    if ($absolute -ge 1000000) {
        return $prefix + ($absolute / 1000000).ToString("0.0", $culture) + "M"
    }

    if ($absolute -ge 1000) {
        return $prefix + ($absolute / 1000).ToString("0.0", $culture) + "K"
    }

    return ("{0}" -f [int64]$number)
}

function Format-PercentDelta($value) {
    if ($null -eq $value) {
        return $null
    }

    $rounded = [Math]::Round([double]$value, 1)
    if ([Math]::Abs($rounded) -lt 0.1) {
        return "0%"
    }

    $sign = if ($rounded -gt 0) { "+" } else { "" }
    if ([Math]::Abs($rounded - [Math]::Round($rounded)) -lt 0.01) {
        return ("{0}{1}%" -f $sign, [int]$rounded)
    }

    return $sign + $rounded.ToString("0.0", [Globalization.CultureInfo]::InvariantCulture) + "%"
}

function Get-RateLimitWindowKey($primaryReset, $secondaryReset) {
    return "{0}:{1}" -f (Convert-ToInt64 $primaryReset), (Convert-ToInt64 $secondaryReset)
}

function Test-ResetTimesMatch($left, $right) {
    return [Math]::Abs((Convert-ToInt64 $left) - (Convert-ToInt64 $right)) -le $script:ResetDriftToleranceSeconds
}

function Test-RateLimitWindowMatches($leftPrimaryReset, $leftSecondaryReset, $rightPrimaryReset, $rightSecondaryReset) {
    return (Test-ResetTimesMatch $leftPrimaryReset $rightPrimaryReset) -and
        (Test-ResetTimesMatch $leftSecondaryReset $rightSecondaryReset)
}

function Test-RateLimitWindowKeyMatches($windowKey, $primaryReset, $secondaryReset) {
    if ([string]::IsNullOrWhiteSpace($windowKey)) {
        return $false
    }

    $parts = $windowKey.Split(":")
    if ($parts.Count -ne 2) {
        return $false
    }

    return Test-RateLimitWindowMatches $parts[0] $parts[1] $primaryReset $secondaryReset
}

function Convert-CodexLogRateLimitEvent($event) {
    if (-not $event -or $event.type -ne "codex.rate_limits" -or -not $event.rate_limits) {
        return $null
    }

    $limits = $event.rate_limits
    if (-not $limits.primary -or -not $limits.secondary) {
        return $null
    }

    $primaryReset = Convert-ToInt64 (Get-ObjectValue $limits.primary "reset_at" 0)
    $secondaryReset = Convert-ToInt64 (Get-ObjectValue $limits.secondary "reset_at" 0)
    $primaryResetAfter = Convert-ToInt64 (Get-ObjectValue $limits.primary "reset_after_seconds" 0)
    $stampSeconds = if ($primaryReset -gt 0 -and $primaryResetAfter -gt 0) {
        $primaryReset - $primaryResetAfter
    } else {
        [DateTimeOffset]::Now.ToUnixTimeSeconds()
    }

    $reachedType = $null
    if ([bool](Get-ObjectValue $limits "limit_reached" $false)) {
        $reachedType = "primary"
    }

    $rateLimits = [pscustomobject]@{
        limit_id = "codex"
        limit_name = $null
        primary = [pscustomobject]@{
            used_percent = Convert-ToNumber (Get-ObjectValue $limits.primary "used_percent" 0)
            window_minutes = Convert-ToInt64 (Get-ObjectValue $limits.primary "window_minutes" 0)
            resets_at = $primaryReset
        }
        secondary = [pscustomobject]@{
            used_percent = Convert-ToNumber (Get-ObjectValue $limits.secondary "used_percent" 0)
            window_minutes = Convert-ToInt64 (Get-ObjectValue $limits.secondary "window_minutes" 0)
            resets_at = $secondaryReset
        }
        credits = Get-ObjectValue $event "credits" $null
        plan_type = Get-ObjectValue $event "plan_type" $null
        rate_limit_reached_type = $reachedType
    }

    return [pscustomobject]@{
        Stamp = [DateTimeOffset]::FromUnixTimeSeconds($stampSeconds)
        Event = [pscustomobject]@{
            timestamp = ([DateTimeOffset]::FromUnixTimeSeconds($stampSeconds)).ToString("o")
            payload = [pscustomobject]@{
                type = "token_count"
                rate_limits = $rateLimits
            }
        }
        File = $script:CodexLogsPath
        PrimaryUsed = Convert-ToNumber $rateLimits.primary.used_percent
        SecondaryUsed = Convert-ToNumber $rateLimits.secondary.used_percent
        PrimaryReset = Convert-ToInt64 $rateLimits.primary.resets_at
        SecondaryReset = Convert-ToInt64 $rateLimits.secondary.resets_at
        RateLimitReachedType = $reachedType
    }
}

function Get-CodexLogRateLimitSnapshot {
    $paths = @($script:CodexLogsPath + "-wal", $script:CodexLogsPath)
    $snapshots = @()
    foreach ($path in $paths) {
        if (-not (Test-Path $path)) {
            continue
        }

        $text = Get-FileTailText $path (8 * 1024 * 1024)
        if ([string]::IsNullOrEmpty($text)) {
            continue
        }

        $needle = '{"type":"codex.rate_limits"'
        $index = 0
        while ($true) {
            $found = $text.IndexOf($needle, $index, [StringComparison]::Ordinal)
            if ($found -lt 0) {
                break
            }

            $json = Get-BalancedJsonFromText $text $found
            if ($json) {
                try {
                    $snapshot = Convert-CodexLogRateLimitEvent ($json | ConvertFrom-Json)
                    if ($snapshot) {
                        $snapshots += $snapshot
                    }
                } catch {
                }
            }

            $index = $found + $needle.Length
        }
    }

    return $snapshots |
        Sort-Object Stamp -Descending |
        Select-Object -First 1
}

function Test-UsableCodexRateLimits($limits) {
    if (-not $limits) {
        return $false
    }

    if ($limits.limit_id -and $limits.limit_id -ne "codex") {
        return $false
    }

    if (-not $limits.primary) {
        return $false
    }

    if ($null -eq $limits.primary.used_percent) {
        return $false
    }

    if ($limits.secondary -and $null -eq $limits.secondary.used_percent) {
        return $false
    }

    return $true
}

function Test-UsableMinimaxRateLimits($limits) {
    if (-not $limits) {
        return $false
    }

    if ($limits.limit_id -and $limits.limit_id -ne "minimax") {
        return $false
    }

    if (-not $limits.primary -or -not $limits.secondary) {
        return $false
    }

    if ($null -eq $limits.primary.used_percent -or $null -eq $limits.secondary.used_percent) {
        return $false
    }

    return $true
}

function Get-RateLimitHistory($limitId = "codex") {
    if (-not (Test-Path $script:CodexSessionsDir)) {
        return $null
    }

    $files = Get-ChildItem -Path $script:CodexSessionsDir -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 30

    $snapshots = @()
    $testLimitsFunc = if ($limitId -eq "minimax") { ${function:Test-UsableMinimaxRateLimits} } else { ${function:Test-UsableCodexRateLimits} }

    foreach ($file in $files) {
        $lines = Get-FileTailLines $file.FullName (512 * 1024)
        foreach ($line in $lines) {
            if ($line -notmatch '"rate_limits"') {
                continue
            }

            try {
                $event = $line | ConvertFrom-Json
                $limits = $event.payload.rate_limits
                if (-not (& $testLimitsFunc $limits)) {
                    continue
                }

                $stamp = [DateTimeOffset]::Parse($event.timestamp)
                $snapshots += [pscustomobject]@{
                    Stamp = $stamp
                    Event = $event
                    File = $file.FullName
                    PrimaryUsed = Convert-ToNumber $limits.primary.used_percent
                    SecondaryUsed = Convert-ToNumber $limits.secondary.used_percent
                    PrimaryReset = Convert-ToInt64 $limits.primary.resets_at
                    SecondaryReset = Convert-ToInt64 $limits.secondary.resets_at
                    RateLimitReachedType = Get-ObjectValue $limits "rate_limit_reached_type" $null
                }
            } catch {
                continue
            }
        }
    }

    if ($limitId -eq "codex") {
        $logSnapshot = Get-CodexLogRateLimitSnapshot
        if ($logSnapshot) {
            $snapshots += $logSnapshot
        }
    }

    $sorted = $snapshots | Sort-Object Stamp -Descending
    $latest = $sorted | Select-Object -First 1
    if (-not $latest) {
        return $null
    }

    $sameWindow = $sorted | Where-Object {
        Test-RateLimitWindowMatches $_.PrimaryReset $_.SecondaryReset $latest.PrimaryReset $latest.SecondaryReset
    }
    $windowPrimaryMax = ($sameWindow | Measure-Object -Property PrimaryUsed -Maximum).Maximum
    $windowSecondaryMax = if ($latest.Event.payload.rate_limits.secondary) {
        ($sameWindow | Measure-Object -Property SecondaryUsed -Maximum).Maximum
    } else {
        $null
    }
    $reachedType = $sameWindow |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.RateLimitReachedType) } |
        Sort-Object Stamp -Descending |
        Select-Object -First 1 -ExpandProperty RateLimitReachedType

    if ($null -eq $windowPrimaryMax) {
        $windowPrimaryMax = $latest.PrimaryUsed
    }
    if ($null -eq $windowSecondaryMax) {
        $windowSecondaryMax = $latest.SecondaryUsed
    }

    # In the same reset window the consumed percentage should not move backwards.
    if ($windowPrimaryMax -gt $latest.PrimaryUsed) {
        $latest.PrimaryUsed = $windowPrimaryMax
        $latest.Event.payload.rate_limits.primary.used_percent = $windowPrimaryMax
    }
    if ($latest.Event.payload.rate_limits.secondary -and $windowSecondaryMax -gt $latest.SecondaryUsed) {
        $latest.SecondaryUsed = $windowSecondaryMax
        $latest.Event.payload.rate_limits.secondary.used_percent = $windowSecondaryMax
    }
    if (-not [string]::IsNullOrWhiteSpace($reachedType)) {
        $latest.Event.payload.rate_limits.rate_limit_reached_type = $reachedType
    }

    $previous = $sorted |
        Select-Object -Skip 1 |
        Where-Object {
            ([Math]::Abs($_.PrimaryUsed - $latest.PrimaryUsed) -ge 0.01) -or
            ([Math]::Abs($_.SecondaryUsed - $latest.SecondaryUsed) -ge 0.01)
        } |
        Select-Object -First 1

    return [pscustomobject]@{
        Latest = $latest
        PreviousDistinct = $previous
    }
}

function Apply-UsageFloor($limits) {
    if (-not $limits -or -not $limits.primary) {
        return
    }

    $windowKey = Get-RateLimitWindowKey $limits.primary.resets_at $limits.secondary.resets_at
    $primaryCurrent = Convert-ToNumber $limits.primary.used_percent
    $secondaryCurrent = if ($limits.secondary) { Convert-ToNumber $limits.secondary.used_percent } else { $null }

    if (-not (Test-RateLimitWindowKeyMatches $script:UsageFloorState.WindowKey $limits.primary.resets_at $limits.secondary.resets_at)) {
        $script:UsageFloorState.WindowKey = $windowKey
        $script:UsageFloorState.PrimaryUsed = $primaryCurrent
        $script:UsageFloorState.SecondaryUsed = $secondaryCurrent
    } else {
        if ($null -eq $script:UsageFloorState.PrimaryUsed) {
            $script:UsageFloorState.PrimaryUsed = $primaryCurrent
        } else {
            $script:UsageFloorState.PrimaryUsed = [Math]::Max($script:UsageFloorState.PrimaryUsed, $primaryCurrent)
        }

        if ($limits.secondary) {
            if ($null -eq $script:UsageFloorState.SecondaryUsed) {
                $script:UsageFloorState.SecondaryUsed = $secondaryCurrent
            } else {
                $script:UsageFloorState.SecondaryUsed = [Math]::Max($script:UsageFloorState.SecondaryUsed, $secondaryCurrent)
            }
        }
    }

    $limits.primary.used_percent = $script:UsageFloorState.PrimaryUsed
    if ($limits.secondary) {
        $limits.secondary.used_percent = $script:UsageFloorState.SecondaryUsed
    }
}

function Apply-CodexRateLimitReached($limits) {
    if (-not $limits -or -not $limits.primary) {
        return
    }

    $reachedType = Get-ObjectValue $limits "rate_limit_reached_type" $null
    if ([string]::IsNullOrWhiteSpace($reachedType)) {
        return
    }

    $text = $reachedType.ToString().ToLowerInvariant()
    if ($limits.secondary -and $text -match "secondary|weekly|week") {
        $limits.secondary.used_percent = 100
        return
    }

    $limits.primary.used_percent = 100
}

function Get-TokenActivitySummary {
    if (-not (Test-Path $script:CodexSessionsDir)) {
        return $null
    }

    $files = Get-ChildItem -Path $script:CodexSessionsDir -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 6

    $sessionScans = @()

    foreach ($file in $files) {
        $sequence = 0
        $taskStarts = @()
        $tokenEvents = @()

        $lines = Get-FileTailLines $file.FullName (1024 * 1024)
        foreach ($line in $lines) {
            $sequence++
            if (($line -notmatch '"token_count"') -and ($line -notmatch '"task_started"')) {
                continue
            }

            try {
                $event = $line | ConvertFrom-Json
                $stamp = [DateTimeOffset]::Parse($event.timestamp)
                $payload = $event.payload
                if (-not $payload -or -not $payload.type) {
                    continue
                }

                if ($payload.type -eq "task_started") {
                    $taskStarts += $stamp
                    continue
                }

                if ($payload.type -ne "token_count" -or -not $payload.info) {
                    continue
                }

                $total = Convert-ToTokenUsage $payload.info.total_token_usage
                $last = Convert-ToTokenUsage $payload.info.last_token_usage
                if (-not $total -or -not $last) {
                    continue
                }

                $tokenEvents += [pscustomobject]@{
                    File = $file.FullName
                    Stamp = $stamp
                    Sequence = $sequence
                    Total = $total
                    Last = $last
                }
            } catch {
                continue
            }
        }

        if ($taskStarts.Count -gt 0 -or $tokenEvents.Count -gt 0) {
            $sessionScans += [pscustomobject]@{
                File = $file.FullName
                TaskStarts = $taskStarts
                TokenEvents = $tokenEvents
            }
        }
    }

    $allTokenEvents = @($sessionScans | ForEach-Object { $_.TokenEvents } | Where-Object { $_ })
    $latestCall = $allTokenEvents |
        Sort-Object Stamp, Sequence -Descending |
        Select-Object -First 1

    $latestTask = $sessionScans |
        ForEach-Object {
            $scan = $_
            $scan.TaskStarts | ForEach-Object {
                [pscustomobject]@{
                    File = $scan.File
                    Stamp = $_
                }
            }
        } |
        Sort-Object Stamp -Descending |
        Select-Object -First 1

    $latestTurnUsage = $null
    if ($latestTask) {
        $scan = $sessionScans | Where-Object { $_.File -eq $latestTask.File } | Select-Object -First 1
        if ($scan) {
            $events = @($scan.TokenEvents | Sort-Object Stamp, Sequence)
            $latestAfterStart = $events | Where-Object { $_.Stamp -ge $latestTask.Stamp } | Select-Object -Last 1
            if ($latestAfterStart) {
                $previousBeforeStart = $events | Where-Object { $_.Stamp -lt $latestTask.Stamp } | Select-Object -Last 1
                if ($previousBeforeStart) {
                    $latestTurnUsage = Get-TokenDelta $latestAfterStart.Total $previousBeforeStart.Total
                } else {
                    $firstAfterStart = $events | Where-Object { $_.Stamp -ge $latestTask.Stamp } | Select-Object -First 1
                    if ($firstAfterStart -and $firstAfterStart.Sequence -ne $latestAfterStart.Sequence) {
                        $latestTurnUsage = Get-TokenDelta $latestAfterStart.Total $firstAfterStart.Total
                    } else {
                        $latestTurnUsage = $latestAfterStart.Last
                    }
                }
            }
        }
    }

    $cutoff = (Get-Date).AddMinutes(-3)
    $recentUsage = [pscustomobject]@{ input = 0; cached = 0; output = 0; reasoning = 0; total = 0 }
    foreach ($scan in $sessionScans) {
        $events = @($scan.TokenEvents | Sort-Object Stamp, Sequence)
        $previous = $null
        foreach ($event in $events) {
            if ($event.Stamp.LocalDateTime -ge $cutoff -and $previous) {
                $delta = Get-TokenDelta $event.Total $previous.Total
                if ($delta -and $delta.total -gt 0) {
                    $recentUsage = Add-TokenUsage $recentUsage $delta
                }
            }

            $previous = $event
        }
    }

    return [pscustomobject]@{
        LatestCall = if ($latestCall) { $latestCall.Last } else { $null }
        LatestTurn = $latestTurnUsage
        Recent = $recentUsage
        ObservedAt = if ($latestCall) { $latestCall.Stamp.LocalDateTime } else { $null }
    }
}

function Format-ActivityText($usage, $activity) {
    $parts = @()

    if ($usage -and $null -ne $usage.primaryDelta) {
        if ($usage.primaryDelta -gt 0.05) {
            $parts += ("session {0}" -f $usage.primaryDeltaText)
        } elseif ($usage.primaryDelta -lt -0.05) {
            $parts += "session reset"
        }
    }

    if ($usage -and $null -ne $usage.secondaryDelta) {
        if ($usage.secondaryDelta -gt 0.05) {
            $parts += ("week {0}" -f $usage.secondaryDeltaText)
        } elseif ($usage.secondaryDelta -lt -0.05) {
            $parts += "week reset"
        }
    }

    $tokenUsage = $null
    $usageLabel = if ($activity -and $activity.LatestCall -and $activity.LatestCall.total -gt 0) {
        $tokenUsage = $activity.LatestCall
        "request {0} tok" -f (Format-TokenCount $tokenUsage.total)
    } elseif ($activity -and $activity.LatestTurn -and $activity.LatestTurn.total -gt 0) {
        $tokenUsage = $activity.LatestTurn
        "turn {0} tok" -f (Format-TokenCount $tokenUsage.total)
    } else {
        $null
    }

    if ($usageLabel) {
        $parts += $usageLabel
    }

    if ($tokenUsage -and $tokenUsage.output -gt 0) {
        $parts += ("out {0}" -f (Format-TokenCount $tokenUsage.output))
    }

    if ($parts.Count -eq 0) {
        return "Last activity: waiting for token details"
    }

    return "Last activity: " + ($parts -join " | ")
}

function Format-TokenUsageDetail($label, $usage) {
    if (-not $usage -or $usage.total -le 0) {
        return "${label}: unknown"
    }

    return "{0}: {1} tok (in {2}, out {3})" -f `
        $label,
        (Format-TokenCount $usage.total),
        (Format-TokenCount $usage.input),
        (Format-TokenCount $usage.output)
}

function Format-ActivityTooltip($usage, $activity) {
    $lines = @((Format-ActivityText $usage $activity))

    if ($activity) {
        $lines += Format-TokenUsageDetail "Last turn" $activity.LatestTurn
        $lines += Format-TokenUsageDetail "Latest call" $activity.LatestCall
        $lines += Format-TokenUsageDetail "Last 3 min" $activity.Recent
    }

    return $lines -join [Environment]::NewLine
}

function Get-CodexUsage {
    $history = Get-RateLimitHistory
    if (-not $history) {
        return [pscustomobject]@{
            ok = $false
            message = "Waiting for Codex limits"
            plan = "unknown"
            updated = Get-Date
            primary = $null
            secondary = $null
        }
    }

    $latest = $history.Latest
    $previous = $history.PreviousDistinct
    $limits = $latest.Event.payload.rate_limits
    Apply-UsageFloor $limits
    Apply-CodexRateLimitReached $limits
    $age = (Get-Date) - $latest.Stamp.LocalDateTime
    $primaryDelta = if ($previous) { $latest.PrimaryUsed - $previous.PrimaryUsed } else { $null }
    $secondaryDelta = if ($previous) { $latest.SecondaryUsed - $previous.SecondaryUsed } else { $null }
    return [pscustomobject]@{
        ok = $true
        message = $null
        plan = $limits.plan_type
        limitReachedType = Get-ObjectValue $limits "rate_limit_reached_type" $null
        updated = $latest.Stamp.LocalDateTime
        isStale = ($age.TotalSeconds -gt $script:StaleAfterSeconds)
        staleText = if ($age.TotalSeconds -gt $script:StaleAfterSeconds) { "Updated {0}m ago" -f [Math]::Max(1, [Math]::Floor($age.TotalMinutes)) } else { "" }
        primaryDelta = $primaryDelta
        secondaryDelta = $secondaryDelta
        primaryDeltaText = Format-PercentDelta $primaryDelta
        secondaryDeltaText = Format-PercentDelta $secondaryDelta
        primary = $limits.primary
        secondary = $limits.secondary
    }
}

function Apply-MinimaxFloor($limits) {
    if (-not $limits -or -not $limits.primary -or -not $limits.secondary) {
        return
    }

    $windowKey = Get-RateLimitWindowKey $limits.primary.resets_at $limits.secondary.resets_at
    $primaryCurrent = Convert-ToNumber $limits.primary.used_percent
    $secondaryCurrent = Convert-ToNumber $limits.secondary.used_percent

    if (-not (Test-RateLimitWindowKeyMatches $script:MinimaxFloorState.WindowKey $limits.primary.resets_at $limits.secondary.resets_at)) {
        $script:MinimaxFloorState.WindowKey = $windowKey
        $script:MinimaxFloorState.PrimaryUsed = $primaryCurrent
        $script:MinimaxFloorState.SecondaryUsed = $secondaryCurrent
    } else {
        if ($null -eq $script:MinimaxFloorState.PrimaryUsed) {
            $script:MinimaxFloorState.PrimaryUsed = $primaryCurrent
        } else {
            $script:MinimaxFloorState.PrimaryUsed = [Math]::Max($script:MinimaxFloorState.PrimaryUsed, $primaryCurrent)
        }

        if ($null -eq $script:MinimaxFloorState.SecondaryUsed) {
            $script:MinimaxFloorState.SecondaryUsed = $secondaryCurrent
        } else {
            $script:MinimaxFloorState.SecondaryUsed = [Math]::Max($script:MinimaxFloorState.SecondaryUsed, $secondaryCurrent)
        }
    }

    $limits.primary.used_percent = $script:MinimaxFloorState.PrimaryUsed
    $limits.secondary.used_percent = $script:MinimaxFloorState.SecondaryUsed
}

function Get-MinimaxUsage {
    $settings = Get-MinimaxRemoteSettings
    if (-not $settings.Enabled) {
        return [pscustomobject]@{
            ok = $false
            configured = $false
            message = "Minimax not configured"
            plan = "unknown"
            updated = Get-Date
            primary = $null
            secondary = $null
        }
    }

    $now = Get-Date
    if ($script:MinimaxRemoteState.Usage -and $script:MinimaxRemoteState.LastFetch) {
        $age = $now - $script:MinimaxRemoteState.LastFetch
        if ($age.TotalSeconds -lt $settings.RefreshSeconds) {
            return $script:MinimaxRemoteState.Usage
        }
    }

    try {
        $raw = Invoke-MinimaxQuotaRaw $settings
        $usage = Convert-MinimaxQuota $raw $settings.Source $settings.ModelPattern
        $script:MinimaxRemoteState.LastFetch = $now
        $script:MinimaxRemoteState.Usage = $usage
        $script:MinimaxRemoteState.Error = $null
        Write-WidgetLog ("Minimax quota refreshed via {0}: interval {1:N1}%, weekly {2:N1}%." -f $settings.Source, [double]$usage.primary.used_percent, [double]$usage.secondary.used_percent)
        return $usage
    } catch {
        $script:MinimaxRemoteState.LastFetch = $now
        $script:MinimaxRemoteState.Error = $_.Exception.Message
        Write-WidgetLog ("Minimax quota refresh failed via {0}: {1}" -f $settings.Source, $_.Exception.Message)
        if ($script:MinimaxRemoteState.Usage) {
            $script:MinimaxRemoteState.Usage.isStale = $true
            $script:MinimaxRemoteState.Usage.error = $_.Exception.Message
            return $script:MinimaxRemoteState.Usage
        }

        return [pscustomobject]@{
            ok = $false
            configured = $true
            message = "Minimax unavailable"
            plan = "unknown"
            updated = $now
            error = $_.Exception.Message
            primary = $null
            secondary = $null
        }
    }
}

function Get-AntigravitySettings {
    $config = Read-Config
    $antigravity = Get-ProviderConfigObject $config "antigravity"
    return [pscustomobject]@{
        Enabled = Convert-ToBoolean (Get-ObjectValue $antigravity "enabled" $null) $false
        Pool = Get-ObjectValue $antigravity "pool" "gemini"
        SnapshotPath = Get-ObjectValue $antigravity "snapshotPath" (Join-Path $env:LOCALAPPDATA "CodexUsageMeter\antigravity-quota.json")
    }
}

function Invoke-AntigravityLiveFetch {
    $settings = Get-AntigravitySettings
    $snapshotFile = $settings.SnapshotPath
    
    if (-not (Test-Path $snapshotFile)) {
        return [pscustomobject]@{ Usage = $null; Error = "AGY snapshot not found. Start AGY with the statusline bridge."; Status = "error" }
    }
    
    try {
        $content = Get-Content -Path $snapshotFile -Raw -Encoding UTF8
        $data = $content | ConvertFrom-Json
        $pool = Get-ObjectValue (Get-ObjectValue $data "pools" $null) $settings.Pool $null
        if (-not $pool) { throw "AGY pool '$($settings.Pool)' is unavailable in the latest snapshot." }
        $convertWindow = {
            param($source, $label, $title, $windowMinutes)
            if (-not $source) { return $null }
            $remaining = [Math]::Max([double]0, [Math]::Min([double]1, [double](Get-ObjectValue $source "remaining_fraction" 0)))
            $reset = Get-ObjectValue $source "resets_at" $null
            $resetSeconds = Convert-ToUnixTimestamp $reset
            return [pscustomobject]@{ label = $label; title = $title; total = $null; used = $null; used_percent = [Math]::Round((1 - $remaining) * 100, 1); resets_at = $resetSeconds; window_minutes = $windowMinutes }
        }
        $updated = [datetime](Get-ObjectValue $data "captured_at" (Get-Date))
        $age = (Get-Date).ToUniversalTime() - $updated.ToUniversalTime()
        
        $usage = [pscustomobject]@{
            ok = $true
            configured = $true
            message = "AGY $($settings.Pool) quota"
            plan = Get-ObjectValue $data "plan_tier" "Antigravity"
            updated = $updated
            isStale = $age.TotalSeconds -gt $script:StaleAfterSeconds
            staleText = if ($age.TotalSeconds -gt $script:StaleAfterSeconds) { "AGY snapshot {0:N0}m old" -f [Math]::Floor($age.TotalMinutes) } else { "" }
            primary = & $convertWindow (Get-ObjectValue $pool "current" $null) "Session" "Current session" 300
            secondary = & $convertWindow (Get-ObjectValue $pool "weekly" $null) "Weekly" "Weekly limit" 10080
        }
        
        return [pscustomobject]@{ Usage = $usage; Error = $null; Status = "success" }
    } catch {
        return [pscustomobject]@{ Usage = $null; Error = "Failed to read AGY snapshot."; Status = "error" }
    }
}

function Invoke-AntigravityManualRefresh($controls) {
    if ($null -ne $script:AntigravityRefreshTask) { return $false }
    $settings = Get-AntigravitySettings
    if (-not $settings.Enabled) { return $false }
    
    $script:AntigravityRefreshTask = [System.Threading.Tasks.Task]::Run({
        $result = Invoke-AntigravityLiveFetch
        $controls.Window.Dispatcher.Invoke([Action] {
            $script:AntigravityRefreshTask = $null
            if ($result.Status -eq "success" -and $result.Usage) {
                $script:AntigravityRemoteState.Usage = $result.Usage
                $script:AntigravityRemoteState.Usage.error = $null
            } elseif ($script:AntigravityRemoteState.Usage) {
                $script:AntigravityRemoteState.Usage.error = $result.Error
            }
            $script:AntigravityRemoteState.Error = $result.Error
            $script:AntigravityRemoteState.RefreshStatus = $result.Status
            Update-Widget $controls
            $null = Set-ProviderActionStatus "antigravity" $result.Status (if ($result.Status -eq "success") { "OK" } else { "err" }) $result.Error
            $control = Get-ObjectValue $controls.ProviderSections "antigravity" $null
            if ($control) { Update-ProviderActionButton $control }
        })
    })
    return $true
}

function Get-AntigravityUsage {
    $settings = Get-AntigravitySettings
    if (-not $settings.Enabled) {
        return [pscustomobject]@{ ok = $false; configured = $false; message = "Antigravity not configured"; plan = "unknown"; updated = Get-Date; primary = $null; secondary = $null }
    }
    
    $result = Invoke-AntigravityLiveFetch
    if ($result.Status -eq "success") {
        $script:AntigravityRemoteState.Usage = $result.Usage
        $script:AntigravityRemoteState.Error = $null
    } elseif (-not $script:AntigravityRemoteState.Usage) {
        return [pscustomobject]@{ ok = $false; configured = $true; message = "Antigravity usage unavailable"; plan = "unknown"; updated = Get-Date; error = $result.Error; primary = $null; secondary = $null }
    } else {
        $script:AntigravityRemoteState.Usage.error = $result.Error
    }
    return $script:AntigravityRemoteState.Usage
}

function Get-GrokSettings {
    $config = Read-Config
    $grok = Get-ProviderConfigObject $config "grok"

    return [pscustomobject]@{
        Enabled = Convert-ToBoolean (Get-ObjectValue $grok "enabled" $null) $false
        LogPath = Get-FirstObjectValue $grok @("logPath", "log", "path", "billingLogPath")
        StaleAfterSeconds = [Math]::Max(60, [int](Convert-ToNullableNumber (Get-ObjectValue $grok "staleAfterSeconds" $script:StaleAfterSeconds)))
        ApiTimeoutSeconds = [Math]::Max(3, [int](Convert-ToNullableNumber (Get-ObjectValue $grok "apiTimeoutSeconds" 12)))
    }
}

function Convert-ToUnixTimestamp($value) {
    if ($null -eq $value) {
        return [int64]0
    }

    if ($value -is [DateTime]) {
        return ([DateTimeOffset]$value).ToUnixTimeSeconds()
    }

    $number = Convert-ToNullableNumber $value
    if ($null -ne $number) {
        if ($number -le 0) {
            return [int64]0
        }

        if ($number -gt 9999999999) {
            return [int64][Math]::Floor($number / 1000)
        }

        return [int64][Math]::Floor($number)
    }

    try {
        return ([DateTimeOffset]::Parse($value.ToString(), [Globalization.CultureInfo]::InvariantCulture)).ToUnixTimeSeconds()
    } catch {
        return [int64]0
    }
}

function Get-NewerUsage($primaryUsage, $fallbackUsage) {
    if (-not $primaryUsage) {
        return $fallbackUsage
    }

    if (-not $fallbackUsage) {
        return $primaryUsage
    }

    $primaryUpdated = Convert-ToDateTimeOrNull (Get-ObjectValue $primaryUsage "updated" $null)
    $fallbackUpdated = Convert-ToDateTimeOrNull (Get-ObjectValue $fallbackUsage "updated" $null)
    if ($primaryUpdated -and $fallbackUpdated -and $fallbackUpdated -gt $primaryUpdated) {
        return $fallbackUsage
    }

    return $primaryUsage
}

function Set-GrokUsageFreshness($usage, $staleAfterSeconds) {
    if (-not $usage -or -not $usage.ok) {
        return $usage
    }

    $updated = Convert-ToDateTimeOrNull (Get-ObjectValue $usage "updated" $null)
    if (-not $updated) {
        $updated = Get-Date
        $usage.updated = $updated
    }

    $age = (Get-Date) - $updated
    $usage.isStale = ($age.TotalSeconds -gt $staleAfterSeconds)
    $usage.staleText = if ($usage.isStale) { "Updated {0}m ago" -f [Math]::Max(1, [Math]::Floor($age.TotalMinutes)) } else { "" }
    return $usage
}

function Convert-GrokBillingConfigToUsage($config, $updatedValue = $null, $source = "local_log", $plan = "Grok") {
    if (-not $config) {
        return $null
    }

    $usedPercent = Convert-ToNullableNumber (Get-ObjectValue $config "creditUsagePercent" $null)
    if ($null -eq $usedPercent) {
        return $null
    }

    $currentPeriod = Get-ObjectValue $config "currentPeriod" $null
    $periodStart = Get-ObjectValue $currentPeriod "start" (Get-ObjectValue $config "billingPeriodStart" $null)
    $periodEnd = Get-ObjectValue $currentPeriod "end" (Get-ObjectValue $config "billingPeriodEnd" $null)
    $startSeconds = Convert-ToUnixTimestamp $periodStart
    $endSeconds = Convert-ToUnixTimestamp $periodEnd
    $windowMinutes = if ($startSeconds -gt 0 -and $endSeconds -gt $startSeconds) {
        [int][Math]::Max(1, [Math]::Round(($endSeconds - $startSeconds) / 60.0))
    } else {
        10080
    }

    $updated = Convert-ToDateTimeOrNull $updatedValue
    if (-not $updated) {
        $updated = Get-Date
    }

    return [pscustomobject]@{
        ok = $true
        configured = $true
        message = $null
        plan = if ([string]::IsNullOrWhiteSpace($plan)) { "Grok" } else { $plan }
        source = $source
        updated = $updated
        isStale = $false
        staleText = ""
        error = $null
        primary = [pscustomobject]@{
            used_percent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$usedPercent))
            resets_at = $endSeconds
            window_minutes = $windowMinutes
            total = $null
            remaining = $null
            used = $null
        }
        secondary = $null
    }
}

function Get-GrokClientVersion {
    if (-not [string]::IsNullOrWhiteSpace($script:GrokClientVersion)) {
        return $script:GrokClientVersion
    }

    try {
        $versionOutput = & grok --version 2>$null | Select-Object -First 1
        $match = [regex]::Match(($versionOutput -join " "), 'grok\s+([0-9]+\.[0-9]+\.[0-9]+)')
        if ($match.Success) {
            $script:GrokClientVersion = $match.Groups[1].Value
            return $script:GrokClientVersion
        }
    } catch {
    }

    $script:GrokClientVersion = "0.2.82"
    return $script:GrokClientVersion
}

function Resolve-GrokAuthContext($path = $script:GrokAuthPath) {
    if (-not (Test-Path $path)) {
        throw "Grok auth.json not found"
    }

    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $keyMatch = [regex]::Match($raw, '"key"\s*:\s*"([^"]+)"')
    $userIdMatch = [regex]::Match($raw, '"user_id"\s*:\s*"([^"]+)"')
    if (-not $keyMatch.Success) {
        throw "Grok auth key not found"
    }

    if (-not $userIdMatch.Success) {
        throw "Grok auth user id not found"
    }

    return [pscustomobject]@{
        Key = $keyMatch.Groups[1].Value
        UserId = $userIdMatch.Groups[1].Value
    }
}

function Convert-GrokBillingLogRecord($record) {
    if (-not $record -or (Get-ObjectValue $record "msg" "") -ne "billing: fetched credits config") {
        return $null
    }

    $ctx = Get-ObjectValue $record "ctx" $null
    $config = Get-ObjectValue $ctx "config" $null
    if (-not $config) {
        return $null
    }

    return Convert-GrokBillingConfigToUsage $config (Get-ObjectValue $record "ts" $null) "local_log" (Get-ObjectValue $ctx "subscriptionTier" "Grok")
}

function Convert-GrokBillingApiResponse($response, $existingUsage = $null) {
    if (-not $response) {
        return $null
    }

    $config = Get-ObjectValue $response "config" $null
    if (-not $config) {
        return $null
    }

    $plan = Get-ObjectValue $response "subscriptionTier" $null
    if ([string]::IsNullOrWhiteSpace($plan) -and $existingUsage) {
        $plan = Get-ObjectValue $existingUsage "plan" $null
    }

    return Convert-GrokBillingConfigToUsage $config (Get-Date) "api" $plan
}

function Invoke-GrokLiveBillingFetch {
    $settings = Get-GrokSettings
    $auth = Resolve-GrokAuthContext
    $headers = @{
        Authorization = "Bearer {0}" -f $auth.Key
        "x-userid" = $auth.UserId
        "x-grok-client-version" = Get-GrokClientVersion
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri $script:GrokBillingApiUrl -Headers $headers -Method Get -TimeoutSec $settings.ApiTimeoutSeconds -UseBasicParsing
    $data = $response.Content | ConvertFrom-Json
    $usage = Convert-GrokBillingApiResponse $data $script:GrokRemoteState.Usage
    if (-not $usage) {
        throw "Malformed Grok billing response"
    }

    return $usage
}

function Invoke-GrokRefreshCore($fetchOperation, $existingUsage = $null) {
    try {
        $usage = & $fetchOperation
        if (-not $usage -or -not $usage.ok) {
            throw "Grok API returned no usage snapshot"
        }

        return [pscustomobject]@{
            Usage = $usage
            Error = $null
            Status = [pscustomobject]@{
                state = "success"
                summary = "api ok"
                detail = "Grok usage refreshed via API"
                updated = Get-Date
            }
        }
    } catch {
        return [pscustomobject]@{
            Usage = $existingUsage
            Error = $_.Exception.Message
            Status = [pscustomobject]@{
                state = "error"
                summary = "api failed"
                detail = $_.Exception.Message
                updated = Get-Date
            }
        }
    }
}

function Invoke-GrokManualRefresh($controls = $null) {
    $result = Invoke-GrokRefreshCore { Invoke-GrokLiveBillingFetch } $script:GrokRemoteState.Usage
    if ($result.Usage) {
        $script:GrokRemoteState.Usage = Set-GrokUsageFreshness $result.Usage (Get-GrokSettings).StaleAfterSeconds
        if ($result.Error) {
            $script:GrokRemoteState.Usage.error = $result.Error
        } else {
            $script:GrokRemoteState.Usage.error = $null
        }
    }

    $script:GrokRemoteState.Error = $result.Error
    $script:GrokRemoteState.RefreshStatus = $result.Status
    $null = Set-ProviderActionStatus "grok" $result.Status.state $result.Status.summary $result.Status.detail
    if ($result.Error) {
        Write-WidgetLog ("Grok API refresh failed: {0}" -f $result.Error)
    } elseif ($result.Usage -and $result.Usage.primary) {
        Write-WidgetLog ("Grok API refresh succeeded: weekly {0:N1}%." -f [double]$result.Usage.primary.used_percent)
    }

    if ($controls) {
        Update-Widget $controls
    }

    return $result
}

function Read-GrokBillingUsageFromLog($path) {
    if (-not $path) {
        $path = $script:GrokLogsPath
    }

    if (-not (Test-Path $path)) {
        return $null
    }

    $lines = Get-Content $path -Tail 250 -ErrorAction SilentlyContinue
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch 'billing: fetched credits config') {
            continue
        }

        try {
            $record = $line | ConvertFrom-Json
            $usage = Convert-GrokBillingLogRecord $record
            if ($usage) {
                return $usage
            }
        } catch {
        }
    }

    return $null
}

function Get-GrokUsage {
    $settings = Get-GrokSettings
    if (-not $settings.Enabled) {
        return [pscustomobject]@{
            ok = $false
            configured = $false
            message = "Grok not configured"
            plan = "unknown"
            updated = Get-Date
            primary = $null
            secondary = $null
        }
    }

    $logPath = if ($settings.LogPath) { $settings.LogPath } else { $script:GrokLogsPath }

    try {
        $logUsage = Read-GrokBillingUsageFromLog $logPath
        if (-not $logUsage) {
            throw "No Grok billing snapshot found"
        }

        $usage = Get-NewerUsage $logUsage $script:GrokRemoteState.Usage
        $usage = Set-GrokUsageFreshness $usage $settings.StaleAfterSeconds

        if ($usage -ne $script:GrokRemoteState.Usage) {
            $script:GrokRemoteState.Usage = $usage
        }
        $script:GrokRemoteState.Error = $null
        return $usage
    } catch {
        $script:GrokRemoteState.Error = $_.Exception.Message
        if ($script:GrokRemoteState.Usage) {
            $script:GrokRemoteState.Usage = Set-GrokUsageFreshness $script:GrokRemoteState.Usage $settings.StaleAfterSeconds
            $script:GrokRemoteState.Usage.error = $_.Exception.Message
            return $script:GrokRemoteState.Usage
        }

        return [pscustomobject]@{
            ok = $false
            configured = $true
            message = "Grok usage unavailable"
            plan = "unknown"
            updated = Get-Date
            error = $_.Exception.Message
            primary = $null
            secondary = $null
        }
    }
}

function Set-Progress($row, $percent) {
    $safePercent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$percent))
    $row.percent = $safePercent
    $row.fill.Width = [Math]::Max([double]5, $row.track.ActualWidth * ($safePercent / 100))
}

function Set-TimeProgress($row, $percent) {
    $safePercent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$percent))
    $elapsedPercent = 100 - $safePercent
    $row.timePercent = $safePercent
    $accent = if ($elapsedPercent -ge 88) {
        "#FF8A3D"
    } elseif ($elapsedPercent -ge 70) {
        "#FFC857"
    } else {
        "#D6E2E8"
    }

    $trackWidth = $row.timeTrack.ActualWidth
    $row.timeElapsed.Width = 0
    $row.timeFill.Width = if ($elapsedPercent -le 0) { 0 } else { [Math]::Max(7, $trackWidth * ($elapsedPercent / 100)) }
    $row.timeFill.Background = Get-Brush $accent
    $row.timeFill.Opacity = if ($elapsedPercent -ge 70) { 0.86 } else { 0.64 }
    if ($row.timeFill.Effect) {
        $row.timeFill.Effect.Color = Get-Color $accent
        $row.timeFill.Effect.Opacity = if ($elapsedPercent -ge 70) { 0.42 } else { 0.18 }
    }
}

function Update-TimeTicks($timeBar) {
    foreach ($child in $timeBar.Children) {
        if ($null -eq $child.Tag -or $null -eq $child.Tag.Segments) {
            continue
        }

        $x = $timeBar.ActualWidth * ($child.Tag.Index / $child.Tag.Segments)
        $child.Margin = ("{0},0,0,0" -f [Math]::Round($x))
    }
}

function New-StatusChip($fontSize = 8.25) {
    $border = New-Object System.Windows.Controls.Border
    $border.Padding = "6,1,6,1"
    $border.Margin = "8,1,0,0"
    $border.CornerRadius = 7
    $border.BorderThickness = 1
    $border.Visibility = "Collapsed"

    $text = New-NumericTextBlock "" $fontSize "SemiBold" "#DDE8ED"
    $text.VerticalAlignment = "Center"
    $text.HorizontalAlignment = "Center"
    $text.TextWrapping = "NoWrap"
    $border.Child = $text

    return [pscustomobject]@{
        Border = $border
        Text = $text
    }
}

function Set-StatusChipVisual($border, $textBlock, $status, $visible = $true) {
    if (-not $border -or -not $textBlock -or -not $visible -or -not $status) {
        if ($border) {
            $border.Visibility = "Collapsed"
        }
        return
    }

    $palette = if ($status.Palette) { $status.Palette } else { Get-StatusPalette "ok" }
    $border.Visibility = "Visible"
    $border.Background = Get-Brush $palette.Background
    $border.BorderBrush = Get-Brush $palette.Border
    $textBlock.Foreground = Get-Brush $palette.Foreground
    $textBlock.Text = $status.ChipText
}

function New-LimitRow($title, $large, $timeSegments) {
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = if ($large) { "0,10,0,0" } else { "0,6,0,0" }

    $header = New-Object System.Windows.Controls.Grid
    $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))

    $titleSize = if ($large) { 9.75 } else { 9.0 }
    $valueSize = if ($large) { 18.5 } else { 15.5 }
    $barHeight = if ($large) { 8 } else { 5 }
    $barRadius = $barHeight / 2

    $titleBlock = New-TextBlock $title $titleSize "SemiBold" "#D5DEE3"
    $titleBlock.Opacity = 0.66
    $value = New-NumericTextBlock "0%" $valueSize "Light" "#9DFF58"
    $value.Margin = "12,0,0,0"
    $mode = New-TextBlock "used" 8.25 "SemiBold" "#D6E1E6"
    $mode.Margin = "6,4,0,0"
    $mode.Opacity = 0.78
    $statusChip = New-StatusChip

    $valueWrap = New-Object System.Windows.Controls.StackPanel
    $valueWrap.Orientation = "Horizontal"
    $valueWrap.HorizontalAlignment = "Right"
    $valueWrap.Children.Add($value) | Out-Null
    $valueWrap.Children.Add($mode) | Out-Null
    $valueWrap.Children.Add($statusChip.Border) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($valueWrap, 1)

    $header.Children.Add($titleBlock) | Out-Null
    $header.Children.Add($valueWrap) | Out-Null

    $track = New-Object System.Windows.Controls.Border
    $track.Height = $barHeight
    $track.CornerRadius = $barRadius
    $track.Background = Get-Brush "#5D7F4C"
    $track.Opacity = 0.42

    $fill = New-Object System.Windows.Controls.Border
    $fill.Height = $barHeight
    $fill.CornerRadius = $barRadius
    $fill.HorizontalAlignment = "Left"
    $fill.Background = Get-Brush "#A6FF4F"
    $fill.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
        BlurRadius = 10
        ShadowDepth = 0
        Opacity = 0.42
        Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#A6FF4F")
    }

    $bar = New-Object System.Windows.Controls.Grid
    $bar.Margin = if ($large) { "0,5,0,0" } else { "0,3,0,0" }
    $bar.Children.Add($track) | Out-Null
    $bar.Children.Add($fill) | Out-Null

    $reset = New-NumericTextBlock "" 9 "Regular" "#E0E7EA"
    $reset.Margin = if ($large) { "0,5,0,0" } else { "0,3,0,0" }
    $reset.Opacity = 0.8

    $left = New-NumericTextBlock "" 9 "Regular" "#E0E7EA"
    $left.Margin = if ($large) { "0,5,0,0" } else { "0,3,0,0" }
    $left.HorizontalAlignment = "Right"
    $left.Opacity = 0.8

    $timeTextGrid = New-Object System.Windows.Controls.Grid
    $timeTextGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $timeTextGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))
    [System.Windows.Controls.Grid]::SetColumn($left, 1)
    $timeTextGrid.Children.Add($reset) | Out-Null
    $timeTextGrid.Children.Add($left) | Out-Null

    $timeTrack = New-Object System.Windows.Controls.Border
    $timeTrack.Height = if ($large) { 5 } else { 4 }
    $timeTrack.CornerRadius = $timeTrack.Height / 2
    $timeTrack.Background = Get-Brush "#62737D"
    $timeTrack.Opacity = 0.36

    $timeFill = New-Object System.Windows.Controls.Border
    $timeFill.Height = $timeTrack.Height
    $timeFill.CornerRadius = $timeTrack.CornerRadius
    $timeFill.HorizontalAlignment = "Left"
    $timeFill.Background = Get-Brush "#D6E2E8"
    $timeFill.Opacity = 0.64
    $timeFill.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
        BlurRadius = 8
        ShadowDepth = 0
        Opacity = 0.18
        Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#D6E2E8")
    }

    $timeElapsed = New-Object System.Windows.Controls.Border
    $timeElapsed.Height = $timeTrack.Height
    $timeElapsed.CornerRadius = $timeTrack.CornerRadius
    $timeElapsed.HorizontalAlignment = "Left"
    $timeElapsed.Background = Get-Brush "#435865"
    $timeElapsed.Opacity = 0.26

    $timeBar = New-Object System.Windows.Controls.Grid
    $timeBar.Margin = if ($large) { "0,5,0,0" } else { "0,3,0,0" }
    $timeBar.Children.Add($timeTrack) | Out-Null
    $timeBar.Children.Add($timeElapsed) | Out-Null
    $timeBar.Children.Add($timeFill) | Out-Null

    if ($timeSegments -gt 1) {
        for ($tickIndex = 1; $tickIndex -lt $timeSegments; $tickIndex++) {
            $tick = New-Object System.Windows.Controls.Border
            $tick.Width = 1
            $tick.Height = 7
            $tick.CornerRadius = 0.5
            $tick.Background = Get-Brush "#EAF3F7"
            $tick.Opacity = 0.38
            $tick.HorizontalAlignment = "Left"
            $tick.VerticalAlignment = "Center"
            $tick.Tag = [pscustomobject]@{
                Index = $tickIndex
                Segments = $timeSegments
            }
            $timeBar.Children.Add($tick) | Out-Null
        }
    }

    $panel.Children.Add($header) | Out-Null
    $panel.Children.Add($bar) | Out-Null
    $panel.Children.Add($timeTextGrid) | Out-Null
    $panel.Children.Add($timeBar) | Out-Null

    $row = [pscustomobject]@{
        panel = $panel
        isPrimary = [bool]$large
        title = $titleBlock
        value = $value
        mode = $mode
        statusBorder = $statusChip.Border
        statusText = $statusChip.Text
        track = $track
        fill = $fill
        reset = $reset
        left = $left
        percent = 0
        timeTrack = $timeTrack
        timeElapsed = $timeElapsed
        timeFill = $timeFill
        timePercent = 0
    }

    $bar.Tag = $row
    $bar.Add_SizeChanged({
        param($sender)
        $data = $sender.Tag
        Set-Progress $data $data.percent
    })

    $timeBar.Tag = $row
    $timeBar.Add_SizeChanged({
        param($sender)
        $data = $sender.Tag
        Set-TimeProgress $data $data.timePercent
        Update-TimeTicks $sender
    })

    return $row
}

function Set-CompactProgress($panel, $percent) {
    $safePercent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$percent))
    $panel.percent = $safePercent
    $panel.fill.Width = if ($safePercent -le 0) { 0 } else { [Math]::Max(4, $panel.track.ActualWidth * ($safePercent / 100)) }
}

function Set-CompactAccent($panel, $usedPercent, $enabled) {
    $accent = if ($enabled) { Get-LimitAccent $usedPercent } else { "#6F7D85" }
    $panel.fill.Background = Get-Brush $accent
    $panel.percentText.Foreground = Get-Brush $accent
    if ($panel.fill.Effect) {
        $panel.fill.Effect.Color = Get-Color $accent
        $panel.fill.Effect.Opacity = if ($enabled) { 0.42 } else { 0.12 }
    }
}

function Set-CompactWeeklyAccent($panel, $usedPercent, $enabled) {
    $accent = if ($enabled) { Get-LimitAccent $usedPercent } else { "#6F7D85" }
    $panel.weeklyText.Foreground = Get-Brush $accent
}

function New-CompactProviderPanel($name, $accentColor) {
    $panelBorder = New-Object System.Windows.Controls.Border
    $panelBorder.Padding = "8,4,8,6"
    $panelBorder.BorderThickness = 0
    $panelBorder.CornerRadius = 0
    $panelBorder.BorderBrush = Get-Brush "#53636D"
    $panelBorder.Background = [System.Windows.Media.Brushes]::Transparent

    $grid = New-Object System.Windows.Controls.Grid
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))

    $label = New-TextBlock $name 9.5 "SemiBold" $accentColor
    $label.Opacity = 0.9
    $label.VerticalAlignment = "Center"

    $percentText = New-NumericTextBlock "--" 16 "Light" "#A6FF4F"
    $percentText.Margin = "10,-2,0,0"
    $percentText.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($percentText, 1)
    $statusChip = New-StatusChip 8.0
    $statusChip.Border.Margin = "10,0,0,0"
    [System.Windows.Controls.Grid]::SetColumn($statusChip.Border, 2)

    $timeText = New-NumericTextBlock "↻ --" 9 "Regular" "#E0E8EC"
    $timeText.Margin = "10,1,0,0"
    $timeText.Opacity = 0.84
    [System.Windows.Controls.Grid]::SetRow($timeText, 1)
    [System.Windows.Controls.Grid]::SetColumn($timeText, 1)
    [System.Windows.Controls.Grid]::SetColumnSpan($timeText, 3)

    $weeklyText = New-NumericTextBlock "W --" 9 "SemiBold" "#D6E2E8"
    $weeklyText.Margin = "12,1,0,0"
    $weeklyText.Opacity = 0.78
    $weeklyText.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetRow($weeklyText, 1)
    [System.Windows.Controls.Grid]::SetColumn($weeklyText, 4)

    $track = New-Object System.Windows.Controls.Border
    $track.Height = 7
    $track.CornerRadius = 3.5
    $track.Background = Get-Brush "#5D7F4C"
    $track.Opacity = 0.42

    $fill = New-Object System.Windows.Controls.Border
    $fill.Height = 7
    $fill.CornerRadius = 3.5
    $fill.HorizontalAlignment = "Left"
    $fill.Background = Get-Brush "#A6FF4F"
    $fill.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
        BlurRadius = 10
        ShadowDepth = 0
        Opacity = 0.42
        Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#A6FF4F")
    }

    $bar = New-Object System.Windows.Controls.Grid
    $bar.Margin = "0,4,0,0"
    $bar.Children.Add($track) | Out-Null
    $bar.Children.Add($fill) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($bar, 2)
    [System.Windows.Controls.Grid]::SetColumnSpan($bar, 5)

    $grid.Children.Add($label) | Out-Null
    $grid.Children.Add($percentText) | Out-Null
    $grid.Children.Add($statusChip.Border) | Out-Null
    $grid.Children.Add($timeText) | Out-Null
    $grid.Children.Add($weeklyText) | Out-Null
    $grid.Children.Add($bar) | Out-Null

    $panelBorder.Child = $grid
    [System.Windows.Controls.ToolTipService]::SetIsEnabled($panelBorder, $false)

    $panel = [pscustomobject]@{
        panel = $panelBorder
        label = $label
        percentText = $percentText
        statusBorder = $statusChip.Border
        statusText = $statusChip.Text
        timeText = $timeText
        weeklyText = $weeklyText
        track = $track
        fill = $fill
        percent = 0
    }

    $bar.Tag = $panel
    $bar.Add_SizeChanged({
        param($sender)
        $data = $sender.Tag
        Set-CompactProgress $data $data.percent
    })

    return $panel
}

function New-ProviderSection($metadata) {
    $section = New-Object System.Windows.Controls.Border
    $section.Margin = "0,0,0,8"
    $section.Padding = "0"
    $section.BorderThickness = 1
    $section.CornerRadius = 10
    $section.BorderBrush = Get-Brush $metadata.accent
    $section.BorderBrush.Opacity = 0.35
    $section.Background = [System.Windows.Media.Brushes]::Transparent

    $inner = New-Object System.Windows.Controls.StackPanel
    $inner.Margin = "10,8,10,8"

    $header = New-Object System.Windows.Controls.Grid
    $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))
    $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))
    $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))

    $label = New-TextBlock $metadata.title 9.5 "SemiBold" $metadata.accent
    $label.Opacity = 0.85
    $updated = New-NumericTextBlock "not updated" 9 "Regular" "#C7D0D5"
    $updated.Margin = "8,0,0,0"
    $updated.Opacity = 0.74
    [System.Windows.Controls.Grid]::SetColumn($updated, 1)

    $actionButton = $null
    if ($metadata.supportsRefresh) {
        $actionButton = New-Object System.Windows.Controls.Button
        $actionButton.Content = "↻"
        $actionButton.FontSize = 8
        $actionButton.FontWeight = "SemiBold"
        $actionButton.Width = 28
        $actionButton.Height = 18
        $actionButton.Padding = "0"
        $actionButton.Margin = "6,0,0,0"
        $actionButton.VerticalAlignment = "Center"
        $actionButton.Background = Get-Brush "#1E2730"
        $actionButton.Foreground = Get-Brush $metadata.accent
        $actionButton.BorderBrush = Get-Brush $metadata.accent
        $actionButton.BorderBrush.Opacity = 0.35
        $actionButton.Visibility = "Visible"
        $actionButton.ToolTip = Get-ObjectValue $metadata "actionToolTip" "Refresh"
        $actionButton.Content = Get-ObjectValue $metadata "actionLabel" "API"
        [System.Windows.Controls.Grid]::SetColumn($actionButton, 3)
    }

    $header.Children.Add($label) | Out-Null
    $header.Children.Add($updated) | Out-Null
    if ($actionButton) {
        $header.Children.Add($actionButton) | Out-Null
    }

    $rows = @()
    foreach ($windowTitle in $metadata.defaultWindows) {
        $isPrimaryWindow = ($rows.Count -eq 0)
        $timeSegments = switch -Exact ($windowTitle) {
            "Session" { 5 }
            "Weekly" { 7 }
            default { if ($isPrimaryWindow) { 5 } else { 7 } }
        }
        $row = New-LimitRow $windowTitle $isPrimaryWindow $timeSegments
        $rows += $row
        $inner.Children.Add($row.panel) | Out-Null
    }

    $inner.Children.Insert(0, $header)

    $activityBlock = $null
    if ([bool](Get-ObjectValue $metadata "showActivityBlock" $false)) {
        $activityBlock = New-NumericTextBlock "Last activity: waiting for token details" 9 "Regular" "#E7EEF1"
        $activityBlock.Margin = "0,6,0,0"
        $activityBlock.Opacity = 0.86
        $inner.Children.Add($activityBlock) | Out-Null
    }

    $hintBlock = $null
    if ($metadata.supportsHint) {
        $hintBlock = New-TextBlock "No weekly limit data." 9.5 "Regular" "#D6E2E8"
        $hintBlock.Margin = "0,4,0,0"
        $hintBlock.Opacity = 0.86
        $inner.Children.Add($hintBlock) | Out-Null
    }

    $section.Child = $inner

    return [pscustomobject]@{
        Metadata = $metadata
        Section = $section
        Header = $header
        Updated = $updated
        ActionButton = $actionButton
        Rows = $rows
        Activity = $activityBlock
        Hint = $hintBlock
    }
}

function Get-ProviderUsageWindows($metadata, $usage) {
    $windows = @()
    $defaultTitles = @($metadata.defaultWindows)

    if ($usage -and $usage.primary) {
        $primaryMinutes = Convert-ToInt64 (Get-ObjectValue $usage.primary "window_minutes" 0)
        $windows += [pscustomobject]@{
            title = if ($primaryMinutes -ge 8640) { "Weekly" } elseif ($defaultTitles.Count -ge 1) { $defaultTitles[0] } else { "LIMIT" }
            limit = $usage.primary
        }
    }

    if ($usage -and $usage.secondary) {
        $secondaryMinutes = Convert-ToInt64 (Get-ObjectValue $usage.secondary "window_minutes" 0)
        $windows += [pscustomobject]@{
            title = if ($secondaryMinutes -ge 8640) { "Weekly" } elseif ($defaultTitles.Count -ge 2) { $defaultTitles[1] } else { "LIMIT" }
            limit = $usage.secondary
        }
    }

    return $windows
}

function Format-CompactTooltip($metadata, $usage, $activity) {
    if (-not $usage -or -not $usage.ok -or -not $usage.primary) {
        return "{0}: waiting for telemetry" -f $metadata.label
    }

    $lines = @()
    foreach ($window in (Get-ProviderUsageWindows $metadata $usage)) {
        $label = $window.title.ToLowerInvariant()
        $display = Get-UsageDisplayData $window.limit.used_percent
        $lines += ("{0} {1}: {2:N0}% {3} ({4})" -f $metadata.label, $label, [double]$display.percent, $display.mode, (Format-Remaining $window.limit.resets_at))
    }

    if ($usage.isStale) {
        $lines += "Telemetry may be stale."
    }

    if ($metadata.supportsActivity) {
        $lines += Format-ActivityTooltip $usage $activity
    }

    return $lines -join [Environment]::NewLine
}

function Update-CompactProviderPanel($panel, $metadata, $usage, $activity) {
    if (-not $usage -or -not $usage.ok -or -not $usage.primary) {
        $panel.percentText.Text = "--"
        $panel.timeText.Text = "↻ --"
        $panel.weeklyText.Text = ""
        $panel.panel.ToolTip = "{0}: waiting for telemetry" -f $metadata.label
        Set-StatusChipVisual $panel.statusBorder $panel.statusText $null $false
        Set-CompactAccent $panel 0 $false
        Set-CompactWeeklyAccent $panel 0 $false
        Set-CompactProgress $panel 0
        return
    }

    $primaryDisplay = Get-UsageDisplayData $usage.primary.used_percent
    $weeklyDisplay = if ($usage.secondary) { Get-UsageDisplayData $usage.secondary.used_percent } else { $null }
    $status = Get-UsageStatus $usage.primary $usage.isStale (Get-ObjectValue $usage "limitReachedType" $null)
    $percent = [Math]::Round([double]$primaryDisplay.percent)
    $weeklyPercent = if ($weeklyDisplay) { [Math]::Round([double]$weeklyDisplay.percent) } else { $null }
    $panel.percentText.Text = Format-DisplayPercent $percent
    $panel.timeText.Text = if ($status.CountdownText) { Format-ResetLabel $usage.primary.resets_at } else { Format-CompactRemaining $usage.primary.resets_at }
    $panel.weeklyText.Text = if ($null -ne $weeklyPercent) { "W $weeklyPercent%" } else { "" }
    $panel.panel.ToolTip = Format-CompactTooltip $metadata $usage $activity
    Set-StatusChipVisual $panel.statusBorder $panel.statusText $status $true
    Set-CompactAccent $panel $primaryDisplay.accentPercent $true
    $weeklyAccentPercent = if ($weeklyDisplay) { $weeklyDisplay.accentPercent } else { $null }
    Set-CompactWeeklyAccent $panel $weeklyAccentPercent ($null -ne $weeklyPercent)
    Set-CompactProgress $panel $percent
}

function Update-ProviderSection($control, $usage, $activity) {
    $metadata = $control.Metadata
    $windows = @(Get-ProviderUsageWindows $metadata $usage)
    Update-ProviderActionButton $control

    if (-not $usage -or -not $usage.ok -or $windows.Count -eq 0) {
        for ($i = 0; $i -lt $control.Rows.Count; $i++) {
            $row = $control.Rows[$i]
            $row.panel.Visibility = "Visible"
            if ($i -eq 0) {
                Update-LimitRow $row $null ("Waiting for {0}" -f $metadata.label) "No fresh data"
            } else {
                Update-LimitRow $row $null "" ""
            }
        }

        if ($control.Hint) {
            $hint = Get-ProviderHint $metadata.id $null
            $control.Hint.Text = $hint.Text
            $control.Hint.Foreground = Get-Brush $hint.Color
            $control.Hint.ToolTip = $hint.ToolTip
        }

        if ($control.Activity) {
            $control.Activity.Text = Format-ActivityText $null $activity
            $control.Activity.ToolTip = Format-ActivityTooltip $null $activity
        }

        $control.Updated.Text = Format-ProviderUpdatedText $usage $metadata.id
        return
    }

    for ($i = 0; $i -lt $control.Rows.Count; $i++) {
        $row = $control.Rows[$i]
        if ($i -lt $windows.Count) {
            $window = $windows[$i]
            $row.panel.Visibility = "Visible"
            $status = if ($row.isPrimary) { Get-UsageStatus $window.limit $usage.isStale (Get-ObjectValue $usage "limitReachedType" $null) } else { $null }
            $resetText = Format-ResetLabel $window.limit.resets_at
            $timeText = Format-Remaining $window.limit.resets_at
            Update-LimitRow $row $window.limit $resetText $timeText $status
        } else {
            $row.panel.Visibility = "Collapsed"
        }
    }

    if ($control.Hint) {
        $hint = Get-ProviderHint $metadata.id $usage (Get-ObjectValue $usage "limitReachedType" $null)
        $control.Hint.Text = $hint.Text
        $control.Hint.Foreground = Get-Brush $hint.Color
        $control.Hint.ToolTip = $hint.ToolTip
    }

    if ($control.Activity) {
        $control.Activity.Text = Format-ActivityText $usage $activity
        $control.Activity.ToolTip = Format-ActivityTooltip $usage $activity
    }

    $control.Updated.Text = Format-ProviderUpdatedText $usage $metadata.id
}

function Update-LimitRow($row, $limit, $resetText, $timeText, $status = $null) {
    if (-not $limit) {
        $row.value.Text = "--"
        $row.mode.Text = Normalize-UsageDisplayMode $script:UsageDisplayMode
        $row.reset.Text = $resetText
        $row.left.Text = $timeText
        Set-StatusChipVisual $row.statusBorder $row.statusText $null $false
        Set-LimitAccent $row 0 $false
        Set-Progress $row 0
        Set-TimeProgress $row 0
        return
    }

    $display = Get-UsageDisplayData $limit.used_percent
    $percent = [Math]::Round([double]$display.percent)
    $row.value.Text = Format-DisplayPercent $percent
    $row.mode.Text = $display.mode
    $row.value.UpdateLayout()
    $row.reset.Text = $resetText
    $row.left.Text = $timeText
    Set-StatusChipVisual $row.statusBorder $row.statusText $status $row.isPrimary
    Set-LimitAccent $row $display.accentPercent $true
    Set-Progress $row $percent
    Set-TimeProgress $row (Get-TimeLeftPercent $limit)
}

# Override display helpers with ASCII-safe symbol construction and a tighter compact layout.
$script:CompactHeight = 62
$script:CompactMultiRowHeight = 116

function Format-ResetLabel($resetSeconds) {
    $resetAt = Convert-UnixSeconds $resetSeconds
    if (-not $resetAt) {
        return ("{0} --" -f (Get-UiGlyph "reset"))
    }

    return ("{0} {1}" -f (Get-UiGlyph "reset"), $resetAt.LocalDateTime.ToString("MMM d, h:mm tt", [Globalization.CultureInfo]::InvariantCulture))
}

function Format-CompactRemaining($resetSeconds, $icon = $null) {
    if ($null -eq $icon) {
        $icon = Get-UiGlyph "reset"
    }

    $value = Format-CompactDuration (Get-RemainingSpan $resetSeconds)
    if ([string]::IsNullOrWhiteSpace($icon)) {
        return $value
    }

    return "$icon $value"
}

function Get-UsageStatus($limit, $isStale = $false, $limitReachedType = $null, $projection = $null) {
    if (-not $limit) {
        return [pscustomobject]@{
            State = "wait"
            Label = "WAIT"
            Icon = Get-UiGlyph "wait"
            ChipText = ("{0} WAIT" -f (Get-UiGlyph "wait"))
            CountdownText = $null
            Palette = Get-StatusPalette "wait"
        }
    }

    if ($null -eq $projection) {
        $projection = Get-UsageProjection $limit
    }

    $remainingSpan = Get-RemainingSpan $limit.resets_at
    $remainingMinutes = if ($remainingSpan) { [Math]::Max(0, [Math]::Floor($remainingSpan.TotalMinutes)) } else { [int]::MaxValue }
    $usedPercent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$limit.used_percent))

    if (-not [string]::IsNullOrWhiteSpace($limitReachedType) -or $usedPercent -ge 100) {
        return [pscustomobject]@{
            State = "wait"
            Label = "WAIT"
            Icon = Get-UiGlyph "hourglass"
            ChipText = ("{0} WAIT" -f (Get-UiGlyph "wait"))
            CountdownText = if ($remainingSpan) { Format-CompactRemaining $limit.resets_at (Get-UiGlyph "hourglass") } else { $null }
            Palette = Get-StatusPalette "wait"
        }
    }

    if ($remainingMinutes -le 30) {
        return [pscustomobject]@{
            State = "reset_soon"
            Label = "RESET SOON"
            Icon = Get-UiGlyph "reset"
            ChipText = ("{0} RESET SOON" -f (Get-UiGlyph "reset"))
            CountdownText = $null
            Palette = Get-StatusPalette "reset_soon"
        }
    }

    $isLow = $usedPercent -ge 75 -or ($projection -and $projection.Ready -and $projection.ProjectedUsedPercent -ge 90) -or ($isStale -and $usedPercent -ge 85)
    if ($isLow) {
        return [pscustomobject]@{
            State = "low"
            Label = "LOW"
            Icon = Get-UiGlyph "low"
            ChipText = ("{0} LOW" -f (Get-UiGlyph "low"))
            CountdownText = $null
            Palette = Get-StatusPalette "low"
        }
    }

    return [pscustomobject]@{
        State = "ok"
        Label = "OK"
        Icon = Get-UiGlyph "ok"
        ChipText = ("{0} OK" -f (Get-UiGlyph "ok"))
        CountdownText = $null
        Palette = Get-StatusPalette "ok"
    }
}

function Get-WeeklyHintLimit($providerId, $usage) {
    if (-not $usage) {
        return $null
    }

    if ($usage.secondary) {
        return $usage.secondary
    }

    if (-not $usage.primary) {
        return $null
    }

    $metadata = Get-ObjectValue $script:ProviderMetadata $providerId $null
    $defaultWindows = @()
    if ($metadata) {
        $defaultWindows = @(Get-ObjectValue $metadata "defaultWindows" @())
    }

    if ($defaultWindows.Count -eq 1 -and $defaultWindows[0] -eq "Weekly") {
        return $usage.primary
    }

    $windowMinutes = Convert-ToInt64 (Get-ObjectValue $usage.primary "window_minutes" 0)
    if ($windowMinutes -ge 8640) {
        return $usage.primary
    }

    return $null
}

function Get-WeeklyHint($providerId, $usage, $limitReachedType = $null) {
    if (-not $usage -or -not $usage.ok) {
        return [pscustomobject]@{
            Text = "No weekly limit data."
            Color = "#D6E2E8"
            ToolTip = $null
        }
    }

    $weekly = Get-WeeklyHintLimit $providerId $usage
    if (-not $weekly) {
        return [pscustomobject]@{
            Text = "No weekly limit data."
            Color = "#D6E2E8"
            ToolTip = $null
        }
    }

    if ($usage.isStale) {
        return [pscustomobject]@{
            Text = "Waiting for fresh data."
            Color = "#FFC857"
            ToolTip = $null
        }
    }

    $weeklyUsedPercent = [Math]::Max([double]0, [Math]::Min([double]100, [double]$weekly.used_percent))
    if (-not [string]::IsNullOrWhiteSpace($limitReachedType) -or $weeklyUsedPercent -ge 100) {
        return [pscustomobject]@{
            Text = "Weekly limit reached, wait for reset."
            Color = "#FF8A3D"
            ToolTip = $null
        }
    }

    $remainingSpan = Get-RemainingSpan $weekly.resets_at
    if ($remainingSpan -and $remainingSpan.TotalHours -le 6) {
        $text = if ($weeklyUsedPercent -ge 80) {
            "Reset is soon, heavy tasks can wait."
        } else {
            "Reset is soon, you are fine."
        }

        return [pscustomobject]@{
            Text = $text
            Color = "#FFD4B5"
            ToolTip = $null
        }
    }

    $windowMinutes = Convert-ToInt64 (Get-ObjectValue $weekly "window_minutes" 0)
    $timingReady = $false
    $elapsedPercent = 0
    $weeklyEndEstimate = $null
    $safeDelta = $null
    if ($remainingSpan -and $windowMinutes -gt 0) {
        $elapsedPercent = [Math]::Max([double]0, [Math]::Min([double]100, 100 - (Get-TimeLeftPercent $weekly)))
        if ($elapsedPercent -ge 5) {
            $timingReady = $true
            $weeklyEndEstimate = [Math]::Max([double]0, [Math]::Min([double]150, ($weeklyUsedPercent / $elapsedPercent) * 100))
            $safeDelta = $weeklyUsedPercent - ($elapsedPercent * 0.90)
        }
    }

    $text = $null
    $color = "#D6E2E8"
    if (-not $timingReady) {
        if ($weeklyUsedPercent -lt 50) {
            $text = "Plenty of room for normal use."
        } elseif ($weeklyUsedPercent -lt 75) {
            $text = "Still healthy, keep using normally."
        } elseif ($weeklyUsedPercent -lt 90) {
            $text = "Use a bit slower, this week may get tight."
            $color = "#FFC857"
        } else {
            $text = "Save it for important tasks this week."
            $color = "#FF8A3D"
        }
    } else {
        if ($weeklyUsedPercent -ge 95) {
            $text = "Save it for important tasks this week."
            $color = "#FF8A3D"
        } elseif ($weeklyUsedPercent -ge 85) {
            $text = "Use a bit slower, this week may get tight."
            $color = "#FFC857"
        } elseif ($weeklyEndEstimate -ge 95) {
            $text = "Use a bit slower, this week may get tight."
            $color = "#FFC857"
        } elseif ($safeDelta -ge 10) {
            $text = "Use a bit slower, this week may get tight."
            $color = "#FFC857"
        } elseif ($weeklyUsedPercent -lt 50 -and $weeklyEndEstimate -lt 80) {
            $text = "Plenty of room for normal use."
        } else {
            $text = "Still healthy, keep using normally."
        }
    }

    $tooltipLines = @(
        ("Weekly used: {0:N0}%" -f $weeklyUsedPercent)
    )

    if ($null -ne $weeklyEndEstimate) {
        $tooltipLines += ("By reset: {0:N0}%" -f [Math]::Round($weeklyEndEstimate))
    }

    $resetAt = Convert-UnixSeconds $weekly.resets_at
    if ($resetAt) {
        $tooltipLines += ("Reset: {0}" -f $resetAt.LocalDateTime.ToString("MMM d, h:mm tt", [Globalization.CultureInfo]::InvariantCulture))
    }

    return [pscustomobject]@{
        Text = $text
        Color = $color
        ToolTip = ($tooltipLines -join [Environment]::NewLine)
    }
}

function Get-ProviderHint($providerId, $usage, $limitReachedType = $null) {
    return Get-WeeklyHint $providerId $usage $limitReachedType
}

function New-LimitRow($title, $large, $timeSegments) {
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = if ($large) { "0,8,0,0" } else { "0,6,0,0" }

    $header = New-Object System.Windows.Controls.Grid
    $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))

    $titleSize = if ($large) { 10.0 } else { 9.5 }
    $valueSize = if ($large) { 17.5 } else { 16.0 }
    $barHeight = if ($large) { 8 } else { 5 }
    $barRadius = $barHeight / 2

    $titleBlock = New-TextBlock $title $titleSize "SemiBold" "#D5DEE3"
    $titleBlock.Opacity = 0.66
    $titleBlock.VerticalAlignment = "Top"
    $titleBlock.Margin = "0,4,0,0"
    $value = New-NumericTextBlock "0%" $valueSize "Light" "#9DFF58"
    $value.Margin = "12,0,0,0"
    $mode = New-TextBlock "used" 8.25 "SemiBold" "#D6E1E6"
    $mode.Margin = "6,4,0,0"
    $mode.Opacity = 0.78
    $valueWrap = New-Object System.Windows.Controls.StackPanel
    $valueWrap.Orientation = "Horizontal"
    $valueWrap.HorizontalAlignment = "Right"
    $valueWrap.VerticalAlignment = "Top"
    $valueWrap.Children.Add($value) | Out-Null
    $valueWrap.Children.Add($mode) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($valueWrap, 1)

    $header.Children.Add($titleBlock) | Out-Null
    $header.Children.Add($valueWrap) | Out-Null

    $track = New-Object System.Windows.Controls.Border
    $track.Height = $barHeight
    $track.CornerRadius = $barRadius
    $track.Background = Get-Brush "#5D7F4C"
    $track.Opacity = 0.42

    $fill = New-Object System.Windows.Controls.Border
    $fill.Height = $barHeight
    $fill.CornerRadius = $barRadius
    $fill.HorizontalAlignment = "Left"
    $fill.Background = Get-Brush "#A6FF4F"
    $fill.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
        BlurRadius = 10
        ShadowDepth = 0
        Opacity = 0.42
        Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#A6FF4F")
    }

    $bar = New-Object System.Windows.Controls.Grid
    $bar.Margin = if ($large) { "0,3,0,0" } else { "0,2,0,0" }
    $bar.Children.Add($track) | Out-Null
    $bar.Children.Add($fill) | Out-Null

    $reset = New-NumericTextBlock "" 9 "Regular" "#E0E7EA"
    $reset.Margin = if ($large) { "0,5,0,0" } else { "0,3,0,0" }
    $reset.Opacity = 0.8

    $left = New-NumericTextBlock "" 9 "Regular" "#E0E7EA"
    $left.Margin = if ($large) { "0,5,0,0" } else { "0,3,0,0" }
    $left.HorizontalAlignment = "Right"
    $left.Opacity = 0.8

    $timeTextGrid = New-Object System.Windows.Controls.Grid
    $timeTextGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $timeTextGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))
    [System.Windows.Controls.Grid]::SetColumn($left, 1)
    $timeTextGrid.Children.Add($reset) | Out-Null
    $timeTextGrid.Children.Add($left) | Out-Null

    $timeTrack = New-Object System.Windows.Controls.Border
    $timeTrack.Height = 5
    $timeTrack.CornerRadius = 2.5
    $timeTrack.Background = Get-Brush "#62737D"
    $timeTrack.Opacity = 0.36

    $timeFill = New-Object System.Windows.Controls.Border
    $timeFill.Height = 5
    $timeFill.CornerRadius = 2.5
    $timeFill.HorizontalAlignment = "Left"
    $timeFill.Background = Get-Brush "#D6E2E8"
    $timeFill.Opacity = 0.64
    $timeFill.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
        BlurRadius = 8
        ShadowDepth = 0
        Opacity = 0.18
        Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#D6E2E8")
    }

    $timeElapsed = New-Object System.Windows.Controls.Border
    $timeElapsed.Height = 5
    $timeElapsed.CornerRadius = 2.5
    $timeElapsed.HorizontalAlignment = "Left"
    $timeElapsed.Background = Get-Brush "#435865"
    $timeElapsed.Opacity = 0.26

    $timeBar = New-Object System.Windows.Controls.Grid
    $timeBar.Margin = if ($large) { "0,5,0,0" } else { "0,3,0,0" }
    $timeBar.Children.Add($timeTrack) | Out-Null
    $timeBar.Children.Add($timeElapsed) | Out-Null
    $timeBar.Children.Add($timeFill) | Out-Null

    if ($timeSegments -gt 1) {
        for ($tickIndex = 1; $tickIndex -lt $timeSegments; $tickIndex++) {
            $tick = New-Object System.Windows.Controls.Border
            $tick.Width = 1
            $tick.Height = 7
            $tick.CornerRadius = 0.5
            $tick.Background = Get-Brush "#EAF3F7"
            $tick.Opacity = 0.38
            $tick.HorizontalAlignment = "Left"
            $tick.VerticalAlignment = "Center"
            $tick.Tag = [pscustomobject]@{
                Index = $tickIndex
                Segments = $timeSegments
            }
            $timeBar.Children.Add($tick) | Out-Null
        }
    }

    $panel.Children.Add($header) | Out-Null
    $panel.Children.Add($bar) | Out-Null
    $panel.Children.Add($timeTextGrid) | Out-Null
    $panel.Children.Add($timeBar) | Out-Null

    $row = [pscustomobject]@{
        panel = $panel
        isPrimary = [bool]$large
        title = $titleBlock
        value = $value
        mode = $mode
        statusBorder = $null
        statusText = $null
        track = $track
        fill = $fill
        reset = $reset
        left = $left
        percent = 0
        timeTrack = $timeTrack
        timeElapsed = $timeElapsed
        timeFill = $timeFill
        timePercent = 0
    }

    $bar.Tag = $row
    $bar.Add_SizeChanged({
        param($sender)
        $data = $sender.Tag
        Set-Progress $data $data.percent
    })

    $timeBar.Tag = $row
    $timeBar.Add_SizeChanged({
        param($sender)
        $data = $sender.Tag
        Set-TimeProgress $data $data.timePercent
        Update-TimeTicks $sender
    })

    return $row
}

function New-CompactProviderPanel($name, $accentColor) {
    $panelBorder = New-Object System.Windows.Controls.Border
    $panelBorder.Padding = "9,4,9,5"
    $panelBorder.BorderThickness = 0
    $panelBorder.CornerRadius = 0
    $panelBorder.BorderBrush = Get-Brush "#53636D"
    $panelBorder.Background = [System.Windows.Media.Brushes]::Transparent

    $grid = New-Object System.Windows.Controls.Grid
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" }))

    $label = New-TextBlock $name 9.5 "SemiBold" $accentColor
    $label.Opacity = 0.9
    $label.VerticalAlignment = "Center"

    $percentText = New-NumericTextBlock "--" 16 "Light" "#A6FF4F"
    $percentText.Margin = "6,-2,0,0"
    $percentText.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($percentText, 1)

    $timeText = New-NumericTextBlock "" 9.0 "Regular" "#D6E2E8"
    $timeText.Margin = "6,1,0,0"
    $timeText.Opacity = 0.82
    $timeText.VerticalAlignment = "Center"
    $timeText.HorizontalAlignment = "Right"
    [System.Windows.Controls.Grid]::SetColumn($timeText, 2)

    $weeklyText = New-NumericTextBlock "W --" 9.0 "SemiBold" "#D6E2E8"
    $weeklyText.Margin = "6,1,0,0"
    $weeklyText.Opacity = 0.78
    $weeklyText.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($weeklyText, 3)

    $track = New-Object System.Windows.Controls.Border
    $track.Height = 7
    $track.CornerRadius = 3.5
    $track.Background = Get-Brush "#5D7F4C"
    $track.Opacity = 0.42

    $fill = New-Object System.Windows.Controls.Border
    $fill.Height = 7
    $fill.CornerRadius = 3.5
    $fill.HorizontalAlignment = "Left"
    $fill.Background = Get-Brush "#A6FF4F"
    $fill.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
        BlurRadius = 10
        ShadowDepth = 0
        Opacity = 0.42
        Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#A6FF4F")
    }

    $bar = New-Object System.Windows.Controls.Grid
    $bar.Margin = "0,4,0,0"
    $bar.Children.Add($track) | Out-Null
    $bar.Children.Add($fill) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($bar, 1)
    [System.Windows.Controls.Grid]::SetColumnSpan($bar, 4)

    $grid.Children.Add($label) | Out-Null
    $grid.Children.Add($percentText) | Out-Null
    $grid.Children.Add($timeText) | Out-Null
    $grid.Children.Add($weeklyText) | Out-Null
    $grid.Children.Add($bar) | Out-Null

    $panelBorder.Child = $grid

    $panel = [pscustomobject]@{
        panel = $panelBorder
        label = $label
        percentText = $percentText
        statusBorder = $null
        statusText = $null
        timeText = $timeText
        weeklyText = $weeklyText
        track = $track
        fill = $fill
        percent = 0
    }

    $bar.Tag = $panel
    $bar.Add_SizeChanged({
        param($sender)
        $data = $sender.Tag
        Set-CompactProgress $data $data.percent
    })

    return $panel
}

function Update-CompactProviderPanel($panel, $metadata, $usage, $activity) {
    if (-not $usage -or -not $usage.ok -or -not $usage.primary) {
        $panel.percentText.Text = "--"
        $panel.timeText.Text = "waiting"
        $panel.weeklyText.Text = ""
        $panel.panel.ToolTip = $null
        Set-StatusChipVisual $panel.statusBorder $panel.statusText $null $false
        Set-CompactAccent $panel 0 $false
        Set-CompactWeeklyAccent $panel 0 $false
        Set-CompactProgress $panel 0
        return
    }

    $primaryDisplay = Get-UsageDisplayData $usage.primary.used_percent
    $weeklyDisplay = if ($usage.secondary) { Get-UsageDisplayData $usage.secondary.used_percent } else { $null }
    $status = Get-UsageStatus $usage.primary $usage.isStale (Get-ObjectValue $usage "limitReachedType" $null)
    $percent = [Math]::Round([double]$primaryDisplay.percent)
    $weeklyPercent = if ($weeklyDisplay) { [Math]::Round([double]$weeklyDisplay.percent) } else { $null }
    $panel.percentText.Text = Format-DisplayPercent $percent
    $panel.timeText.Text = if ($status.CountdownText) { $status.CountdownText } else { Format-CompactRemaining $usage.primary.resets_at }
    $panel.weeklyText.Text = if ($null -ne $weeklyPercent) { "W $weeklyPercent%" } else { "" }
    $panel.panel.ToolTip = $null
    Set-StatusChipVisual $panel.statusBorder $panel.statusText $status $true
    Set-CompactAccent $panel $primaryDisplay.accentPercent $true
    $weeklyAccentPercent = if ($weeklyDisplay) { $weeklyDisplay.accentPercent } else { $null }
    Set-CompactWeeklyAccent $panel $weeklyAccentPercent ($null -ne $weeklyPercent)
    Set-CompactProgress $panel $percent
}

function Update-ProviderSection($control, $usage, $activity) {
    $metadata = $control.Metadata
    $windows = @(Get-ProviderUsageWindows $metadata $usage)
    Update-ProviderActionButton $control

    if (-not $usage -or -not $usage.ok -or $windows.Count -eq 0) {
        for ($i = 0; $i -lt $control.Rows.Count; $i++) {
            $row = $control.Rows[$i]
            $row.panel.Visibility = "Visible"
            if ($i -eq 0) {
                Update-LimitRow $row $null ("Waiting for {0}" -f $metadata.label) "No fresh data"
            } else {
                Update-LimitRow $row $null "" ""
            }
        }

        if ($control.Hint) {
            $hint = Get-ProviderHint $metadata.id $null
            $control.Hint.Text = $hint.Text
            $control.Hint.Foreground = Get-Brush $hint.Color
            $control.Hint.ToolTip = $hint.ToolTip
        }

        if ($control.Activity) {
            $control.Activity.Text = Format-ActivityText $null $activity
            $control.Activity.ToolTip = Format-ActivityTooltip $null $activity
        }

        $control.Updated.Text = Format-ProviderUpdatedText $usage $metadata.id
        return
    }

    for ($i = 0; $i -lt $control.Rows.Count; $i++) {
        $row = $control.Rows[$i]
        if ($i -lt $windows.Count) {
            $window = $windows[$i]
            $row.panel.Visibility = "Visible"
            $row.title.Text = $window.title
            $status = if ($row.isPrimary) { Get-UsageStatus $window.limit $usage.isStale (Get-ObjectValue $usage "limitReachedType" $null) } else { $null }
            Update-LimitRow $row $window.limit (Format-ResetLabel $window.limit.resets_at) (Format-Remaining $window.limit.resets_at) $status
        } else {
            $row.panel.Visibility = "Collapsed"
        }
    }

    if ($control.Hint) {
        $hint = Get-ProviderHint $metadata.id $usage (Get-ObjectValue $usage "limitReachedType" $null)
        $control.Hint.Text = $hint.Text
        $control.Hint.Foreground = Get-Brush $hint.Color
        $control.Hint.ToolTip = $hint.ToolTip
    }

    if ($control.Activity) {
        $control.Activity.Text = Format-ActivityText $usage $activity
        $control.Activity.ToolTip = Format-ActivityTooltip $usage $activity
    }

    $control.Updated.Text = Format-ProviderUpdatedText $usage $metadata.id
}

function Sync-ProviderVisibility($controls) {
    if ((Get-VisibleProviderIds).Count -eq 0) {
        foreach ($providerId in (Get-ProviderIds)) {
            if ([bool](Get-ObjectValue $script:ProviderEnabledMap $providerId $false)) {
                Set-ProviderVisible $providerId $true
                break
            }
        }
    }

    $script:CodexEnabled = Test-ProviderVisible "codex"
    $script:MinimaxEnabled = Test-ProviderVisible "minimax"

    $visibleIds = Get-VisibleProviderIds
    $compactColumns = (Get-CompactLayoutMetrics $visibleIds.Count).Columns
    foreach ($providerId in (Get-ProviderIds)) {
        $isVisible = $visibleIds -contains $providerId
        $fullControl = Get-ObjectValue $controls.ProviderSections $providerId $null
        $compactControl = Get-ObjectValue $controls.CompactProviders $providerId $null

        if ($fullControl) {
            $fullControl.Section.Visibility = if ($isVisible) { "Visible" } else { "Collapsed" }
            $fullControl.Section.Margin = if ($isVisible -and $providerId -ne $visibleIds[-1]) { "0,0,0,8" } else { "0,0,0,0" }
        }

        if ($compactControl) {
            $compactControl.panel.Visibility = if ($isVisible) { "Visible" } else { "Collapsed" }
            if ($isVisible) {
                $visibleIndex = [Array]::IndexOf($visibleIds, $providerId)
                $columnIndex = if ($compactColumns -gt 0) { $visibleIndex % $compactColumns } else { 0 }
                $rowIndex = if ($compactColumns -gt 0) { [Math]::Floor($visibleIndex / $compactColumns) } else { 0 }
                $leftMargin = if ($columnIndex -gt 0) { 8 } else { 0 }
                $topMargin = if ($rowIndex -gt 0) { 6 } else { 0 }
                $compactControl.panel.Margin = "{0},{1},0,0" -f $leftMargin, $topMargin
                $compactControl.panel.BorderThickness = if ($compactColumns -gt 1 -and $columnIndex -gt 0) { "1,0,0,0" } else { "0" }
                $compactControl.panel.BorderBrush = Get-Brush "#53636D"
                $compactControl.panel.BorderBrush.Opacity = 0.45
            } else {
                $compactControl.panel.Margin = "0"
                $compactControl.panel.BorderThickness = 0
            }
        }
    }

    $controls.CompactContent.Columns = $compactColumns
    Set-WidgetMode $controls.Window $controls $script:CompactMode $false
}

function Show-UsageWindow($window) {
    $window.Show()
    $window.WindowState = "Normal"
    $window.Activate() | Out-Null
}

function Get-VisibleProviderCount {
    return [Math]::Max(1, (Get-VisibleProviderIds).Count)
}

function Get-CompactColumnCount($visibleProviderCount) {
    $count = [Math]::Max(1, [int]$visibleProviderCount)
    if ($count -le 1) {
        return 1
    }

    return 2
}

function Get-CompactLayoutMetrics($visibleProviderCount) {
    $count = [Math]::Max(1, [int]$visibleProviderCount)
    $columns = Get-CompactColumnCount $count
    $rows = [int][Math]::Ceiling($count / [double]$columns)

    return [pscustomobject]@{
        Columns = $columns
        Rows = $rows
        Width = if ($columns -le 1) { $script:CompactSingleWidth } else { $script:CompactDoubleWidth }
        Height = if ($rows -le 1) { $script:CompactHeight } else { $script:CompactMultiRowHeight }
    }
}

function Get-FullWidgetHeight($controls) {
    $availableWidth = [Math]::Max(1, $script:WidgetWidth - 36)
    $controls.FullContent.Measure([System.Windows.Size]::new($availableWidth, [double]::PositiveInfinity))
    $height = $controls.FullContent.DesiredSize.Height

    if ($height -le 0) {
        $controls.FullContent.UpdateLayout()
        $height = $controls.FullContent.ActualHeight
    }

    if ($height -le 0) {
        return $script:WidgetHeight
    }

    return [Math]::Max(120, [Math]::Min(600, [Math]::Ceiling($height + 30)))
}

function Move-WindowKeepingBottom($window, $oldBottom) {
    if ($oldBottom -le 0) {
        return
    }

    $newTop = $oldBottom - $window.Height
    if ($script:CompactMode) {
        $screenTop = [System.Windows.SystemParameters]::VirtualScreenTop
        $screenBottom = $screenTop + [System.Windows.SystemParameters]::VirtualScreenHeight
    } else {
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $screenTop = $workArea.Top
        $screenBottom = $workArea.Bottom
    }

    if ($newTop -lt $screenTop) {
        $newTop = $screenTop
    }

    $maxTop = $screenBottom - $window.Height
    if ($newTop -gt $maxTop) {
        $newTop = $maxTop
    }

    $window.Top = [Math]::Round($newTop)
}

function Set-WidgetMode($window, $controls, $compact, $saveState = $true, $preserveBottom = $false) {
    $oldHeight = if ($window.ActualHeight -gt 0) { $window.ActualHeight } else { $window.Height }
    $oldBottom = if ($preserveBottom) { $window.Top + $oldHeight } else { 0 }
    $script:CompactMode = [bool]$compact

    if ($script:CompactMode) {
        $controls.FullContent.Visibility = "Collapsed"
        $controls.CompactContent.Visibility = "Visible"
        $controls.Outer.Margin = "6"
        $controls.Outer.Padding = "8,4,8,4"
        $controls.Outer.CornerRadius = 14

        $compactLayout = Get-CompactLayoutMetrics (Get-VisibleProviderCount)
        $width = $compactLayout.Width
        $window.SizeToContent = "Manual"
        $window.Width = $width
        $window.MinWidth = $width
        $window.MaxWidth = $width
        $window.Height = $compactLayout.Height
        $window.MinHeight = $compactLayout.Height
        $window.MaxHeight = $compactLayout.Height
    } else {
        $controls.CompactContent.Visibility = "Collapsed"
        $controls.FullContent.Visibility = "Visible"
        $controls.Outer.Margin = "6"
        $controls.Outer.Padding = "10,10,10,6"
        $controls.Outer.CornerRadius = 16

        $window.SizeToContent = "Manual"
        $window.Width = $script:WidgetWidth
        $window.MinWidth = $script:WidgetWidth
        $window.MaxWidth = $script:WidgetWidth
        $height = Get-FullWidgetHeight $controls
        $script:FullWidgetHeight = $height
        $window.Height = $height
        $window.MinHeight = $height
        $window.MaxHeight = $height
    }

    if (-not $script:CompactMode) {
        Hide-HoverDetailWindow
    } else {
        Sync-HoverDetailVisibility $controls
    }

    if ($preserveBottom) {
        Move-WindowKeepingBottom $window $oldBottom
    }

    Sync-CompactTopmostTimer $window

    if ($saveState) {
        Save-State $window
    }
}

function Toggle-WidgetMode($window, $controls) {
    $wasCompact = $script:CompactMode
    Set-WidgetMode $window $controls (-not $script:CompactMode) $true $wasCompact
}

function Get-HoverDetailMeasuredHeight($outer) {
    if (-not $outer) {
        return $script:WidgetHeight
    }

    $availableWidth = [Math]::Max(1, $script:WidgetWidth - 12)
    $outer.Measure([System.Windows.Size]::new($availableWidth, [double]::PositiveInfinity))
    $height = $outer.DesiredSize.Height
    if ($height -le 0) {
        try {
            $outer.UpdateLayout()
            $height = $outer.ActualHeight
        } catch {
            $height = 0
        }
    }

    if ($height -le 0) {
        return $script:WidgetHeight
    }

    return [Math]::Max(120, [Math]::Min(600, [Math]::Ceiling($height)))
}

function Update-HoverDetailContent {
    $state = Get-HoverDetailState
    if (-not $state.PopupControl -or [string]::IsNullOrWhiteSpace($state.ProviderId)) {
        return
    }

    $usage = Get-ObjectValue $state.UsageMap $state.ProviderId $null
    Update-ProviderSection $state.PopupControl $usage $state.Activity
}

function Set-HoverDetailWindowPosition($window, $sourcePanel = $null) {
    if (-not $window) {
        return
    }

    $hoverState = Get-HoverDetailState
    $ownerWindow = if ($hoverState.Controls) { $hoverState.Controls.Window } else { $window.Owner }
    $ownerRect = if ($ownerWindow) { Get-OwnerWindowRect $ownerWindow } else { $null }
    $sourceRect = if ($sourcePanel -and $ownerWindow) { Get-ElementRectWithinOwner $sourcePanel $ownerWindow } else { $null }
    $workAreaBounds = [System.Windows.SystemParameters]::WorkArea
    $workArea = [pscustomobject]@{
        Left = [double]$workAreaBounds.Left
        Top = [double]$workAreaBounds.Top
        Width = [double]$workAreaBounds.Width
        Height = [double]$workAreaBounds.Height
        Right = [double]$workAreaBounds.Right
        Bottom = [double]$workAreaBounds.Bottom
    }

    if (-not $ownerRect -and -not $sourceRect) {
        return
    }

    $popupSize = [pscustomobject]@{
        Width = [double]$(if ($window.Width -gt 0) { $window.Width } else { $script:WidgetWidth })
        Height = [double]$(if ($window.Height -gt 0) { $window.Height } else { $script:WidgetHeight })
    }
    $placement = Get-HoverDetailPlacement $ownerRect $sourceRect $popupSize $workArea
    $window.Left = $placement.Left
    $window.Top = $placement.Top
}

function Start-HoverDetailCloseTimer {
    $state = Get-HoverDetailState
    if ($state.IsPointerOverPopup -or $state.HoverProviderId) {
        return
    }

    Stop-HoverDetailCloseTimer
    if (-not $state.CloseTimer) {
    $state.CloseTimer = New-Object System.Windows.Threading.DispatcherTimer
    $state.CloseTimer.Interval = [TimeSpan]::FromMilliseconds($script:HoverDetailCloseDelayMs)
    $state.CloseTimer.Add_Tick({
        param($sender)
        Invoke-GuardedUiAction "HoverDetailCloseTimer.Tick" {
            $sender.Stop()
            $hoverState = Get-HoverDetailState
            if ($hoverState.IsPointerOverPopup -or $hoverState.HoverProviderId) {
                return
            }

            Hide-HoverDetailWindow
        } | Out-Null
    })
    }

    $state.CloseTimer.Start()
}

function Hide-HoverDetailWindow {
    $state = Get-HoverDetailState
    Stop-HoverDetailCloseTimer
    Clear-HoverDetailPendingProvider
    $state.IsPointerOverPopup = $false
    $state.HoverProviderId = $null
    if ($state.Window) {
        try {
            $state.Window.Hide()
        } catch {
        }
    }
    $state.ProviderId = $null
    $state.SourcePanel = $null
}

function Mount-HoverDetailProvider($providerId, $controls) {
    $state = Get-HoverDetailState $controls
    $metadata = Get-ProviderMetadata $providerId
    if (-not $state.ContentHost -or -not $metadata) {
        return
    }

    $state.ContentHost.Children.Clear()
    $providerSection = New-ProviderSection $metadata
    $providerSection.Section.Margin = "0,0,0,0"
    if ($providerSection.ActionButton) {
        $providerSection.ActionButton.Tag = $providerId
        $providerSection.ActionButton.Add_Click({
            param($sender)
            Invoke-ProviderRefreshAction ([string]$sender.Tag) $controls
        })
    }

    $state.ContentHost.Children.Add($providerSection.Section) | Out-Null
    $state.PopupControl = $providerSection
    $state.ProviderId = $providerId
}

function Initialize-HoverDetailWindow($controls) {
    $state = Get-HoverDetailState $controls
    if ($state.Window) {
        return $state.Window
    }

    $window = New-Object System.Windows.Window
    $window.Title = "AI Usage Meter Hover Detail"
    $window.Width = $script:WidgetWidth
    $window.MinWidth = $script:WidgetWidth
    $window.MaxWidth = $script:WidgetWidth
    $window.SizeToContent = "Manual"
    $window.WindowStartupLocation = "Manual"
    $window.WindowStyle = "None"
    $window.AllowsTransparency = $true
    $window.Background = [System.Windows.Media.Brushes]::Transparent
    $window.UseLayoutRounding = $true
    $window.SnapsToDevicePixels = $true
    $window.ResizeMode = "NoResize"
    $window.ShowInTaskbar = $false
    $window.ShowActivated = $false
    $window.Topmost = ($script:CompactMode -or $script:TopmostEnabled)

    $outer = New-WidgetOuterBorder
    $outer.Margin = "6"
    $outer.Padding = "10"
    $contentHost = New-Object System.Windows.Controls.StackPanel
    $contentHost.Margin = "0,0,0,0"
    $outer.Child = $contentHost
    $window.Content = $outer

    $window.Add_MouseEnter({
        $hoverState = Get-HoverDetailState
        $hoverState.IsPointerOverPopup = $true
        Stop-HoverDetailCloseTimer
    })
    $window.Add_MouseLeave({
        $hoverState = Get-HoverDetailState
        $hoverState.IsPointerOverPopup = $false
        Start-HoverDetailCloseTimer
    })

    $state.Window = $window
    $state.Outer = $outer
    $state.ContentHost = $contentHost
    return $window
}

function Show-HoverDetailWindow($controls, $providerId, $sourcePanel = $null) {
    if (-not (Test-CanShowHoverDetail $providerId)) {
        return
    }

    $state = Get-HoverDetailState $controls
    Stop-HoverDetailCloseTimer
    Clear-HoverDetailPendingProvider
    $window = Initialize-HoverDetailWindow $controls
    $state.SourcePanel = $sourcePanel
    $state.IsPointerOverPopup = $false

    if ($state.ProviderId -ne $providerId -or -not $state.PopupControl) {
        Mount-HoverDetailProvider $providerId $controls
    }

    Update-HoverDetailContent
    $window.Height = Get-HoverDetailMeasuredHeight $state.Outer
    Set-HoverDetailWindowPosition $window $sourcePanel

    if (-not $window.IsVisible) {
        $window.Show()
    }

    Set-WindowTopmost $window
}

function Request-HoverDetailWindow($controls, $providerId, $sourcePanel) {
    $state = Get-HoverDetailState $controls
    Stop-HoverDetailCloseTimer
    $state.HoverProviderId = $providerId
    $state.PendingProviderId = $providerId
    $state.SourcePanel = $sourcePanel

    if ($state.Window -and $state.Window.IsVisible -and $state.ProviderId -eq $providerId) {
        Set-HoverDetailWindowPosition $state.Window $sourcePanel
        Clear-HoverDetailPendingProvider
        return
    }

    if ($state.Window -and $state.Window.IsVisible -and $state.ProviderId -and $state.ProviderId -ne $providerId) {
        Show-HoverDetailWindow $controls $providerId $sourcePanel
        return
    }

    Stop-HoverDetailOpenTimer
    if (-not $state.OpenTimer) {
        $state.OpenTimer = New-Object System.Windows.Threading.DispatcherTimer
        $state.OpenTimer.Interval = [TimeSpan]::FromMilliseconds($script:HoverDetailOpenDelayMs)
        $state.OpenTimer.Add_Tick({
            param($sender)
            Invoke-GuardedUiAction "HoverDetailOpenTimer.Tick" {
                $sender.Stop()
                $hoverState = Get-HoverDetailState
                if (-not $hoverState.Controls) {
                    return
                }

                $targetProviderId = [string]$hoverState.PendingProviderId
                $targetPanel = $hoverState.SourcePanel
                if (-not (Test-CanShowHoverDetail $targetProviderId)) {
                    Clear-HoverDetailPendingProvider
                    return
                }

                Show-HoverDetailWindow $hoverState.Controls $targetProviderId $targetPanel
            } | Out-Null
        })
    }

    $state.OpenTimer.Start()
}

function Clear-HoverProvider($providerId = $null) {
    $state = Get-HoverDetailState
    if (-not $providerId -or $state.HoverProviderId -eq $providerId) {
        $state.HoverProviderId = $null
    }
}

function Handle-CompactProviderMouseEnter($controls, $providerId, $sourcePanel) {
    if (-not (Test-CanShowHoverDetail $providerId)) {
        return
    }

    $state = Get-HoverDetailState $controls
    $state.HoverProviderId = $providerId
    Stop-HoverDetailCloseTimer
    Request-HoverDetailWindow $controls $providerId $sourcePanel
}

function Handle-CompactProviderMouseLeave($providerId) {
    Clear-HoverProvider $providerId
    Start-HoverDetailCloseTimer
}

function Update-HoverDetailSnapshot($controls, $providerUsageMap, $activity) {
    $state = Get-HoverDetailState $controls
    $state.UsageMap = $providerUsageMap
    $state.Activity = $activity
    if ($state.Window -and $state.Window.IsVisible -and $state.ProviderId) {
        Update-HoverDetailContent
        $state.Window.Height = Get-HoverDetailMeasuredHeight $state.Outer
        Set-HoverDetailWindowPosition $state.Window $state.SourcePanel
    }
}

function Sync-HoverDetailVisibility($controls = $null) {
    $state = Get-HoverDetailState $controls
    $activeProviderId = [string]$state.ProviderId
    $pendingProviderId = [string]$state.PendingProviderId
    if (($activeProviderId -and -not (Test-CanShowHoverDetail $activeProviderId)) -or
        ($pendingProviderId -and -not (Test-CanShowHoverDetail $pendingProviderId))) {
        Hide-HoverDetailWindow
    }
}

function Get-ProviderActionSummary($providerId) {
    $status = Get-ProviderActionStatus $providerId
    if (-not $status) {
        return $null
    }

    $updated = Convert-ToDateTimeOrNull (Get-ObjectValue $status "updated" $null)
    if ($updated) {
        $age = (Get-Date) - $updated
        if ($status.state -eq "success" -and $age.TotalSeconds -gt 90) {
            return $null
        }

        if ($status.state -eq "error" -and $age.TotalSeconds -gt 180) {
            return $null
        }
    }

    return Get-ObjectValue $status "summary" $null
}

function Get-ProviderActionToolTip($providerId, $defaultToolTip) {
    $status = Get-ProviderActionStatus $providerId
    if (-not $status) {
        return $defaultToolTip
    }

    return Get-ObjectValue $status "detail" $defaultToolTip
}

function Update-ProviderActionButton($control) {
    if (-not $control -or -not $control.ActionButton) {
        return
    }

    $button = $control.ActionButton
    $metadata = $control.Metadata
    $status = Get-ProviderActionStatus $metadata.id
    $button.IsEnabled = (-not $status -or $status.state -ne "running")
    $button.Content = if ($status -and $status.state -eq "running") { "..." } else { Get-ObjectValue $metadata "actionLabel" "API" }
    $button.ToolTip = Get-ProviderActionToolTip $metadata.id (Get-ObjectValue $metadata "actionToolTip" "Refresh")
}

function Format-ProviderUpdatedText($usage, $providerId = $null) {
    if (-not $usage -or -not $usage.ok -or -not $usage.updated) {
        $baseText = "not updated"
    } else {
        $updated = Convert-ToDateTimeOrNull $usage.updated
        if (-not $updated) {
            $baseText = "not updated"
        } else {
            $baseText = $updated.ToString("HH:mm:ss")
        }
    }

    if (-not $providerId) {
        return $baseText
    }

    $actionSummary = Get-ProviderActionSummary $providerId
    if ([string]::IsNullOrWhiteSpace($actionSummary)) {
        return $baseText
    }

    if ($baseText -eq "not updated") {
        return $actionSummary
    }

    return "{0} / {1}" -f $baseText, $actionSummary
}

function Apply-WidgetData($controls, $usage, $minimax, $activity, $grok = $null, $antigravity = $null) {
    $providerUsageMap = [ordered]@{
        codex = $usage
        minimax = $minimax
        grok = $grok
        antigravity = $antigravity
    }

    foreach ($providerId in (Get-ProviderIds)) {
        $metadata = Get-ProviderMetadata $providerId
        $providerUsage = Get-ObjectValue $providerUsageMap $providerId $null
        $providerActivity = if ($metadata.supportsActivity) { $activity } else { $null }
        $fullControl = Get-ObjectValue $controls.ProviderSections $providerId $null
        $compactControl = Get-ObjectValue $controls.CompactProviders $providerId $null

        if ($fullControl) {
            Update-ProviderSection $fullControl $providerUsage $providerActivity
        }

        if ($compactControl) {
            Update-CompactProviderPanel $compactControl $metadata $providerUsage $providerActivity
        }
    }

    Update-HoverDetailSnapshot $controls $providerUsageMap $activity

    $statusUsage = @($usage, $minimax, $grok, $antigravity) | Where-Object { $_ -and $_.ok } | Select-Object -First 1
    $controls.Updated.Text = if ($statusUsage) { "Updated " + (Format-ProviderUpdatedText $statusUsage) } else { "Updated " + (Get-Date).ToString("HH:mm:ss") }
}

function Apply-CachedUsageSnapshot($controls, $snapshot) {
    $restored = Restore-UsageSnapshot $snapshot
    if (-not $restored) {
        return $false
    }

    $grok = if ($restored.Providers) { Get-ObjectValue $restored.Providers "grok" $null } else { $null }
    $antigravity = if ($restored.Providers) { Get-ObjectValue $restored.Providers "antigravity" $null } else { $null }
    Apply-WidgetData $controls $restored.Codex $restored.Minimax $restored.Activity $grok $antigravity
    return $true
}

function Invoke-ProviderRefreshAction($providerId, $controls) {
    $metadata = Get-ProviderMetadata $providerId
    if (-not $metadata -or -not $metadata.supportsRefresh) {
        return
    }

    $status = Get-ProviderActionStatus $providerId
    if ($status -and $status.state -eq "running") {
        return
    }

    $actionLabel = Get-ObjectValue $metadata "actionLabel" "Refresh"
    $actionToolTip = "Checking provider API"
    if ($providerId -eq "antigravity") {
        $actionToolTip = "Reading latest AGY statusline snapshot"
    }
    $null = Set-ProviderActionStatus $providerId "running" ("{0}..." -f $actionLabel.ToLowerInvariant()) $actionToolTip
    $control = Get-ObjectValue $controls.ProviderSections $providerId $null
    if ($control) {
        Update-ProviderActionButton $control
        $providerUsage = $script:GrokRemoteState.Usage
        if ($providerId -eq "antigravity") {
            $providerUsage = $script:AntigravityRemoteState.Usage
        }
        $control.Updated.Text = Format-ProviderUpdatedText $providerUsage $providerId
        try {
            $controls.Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
        } catch {
        }
    }

    switch ($providerId) {
        "grok" {
            Invoke-GrokManualRefresh $controls | Out-Null
        }
        "antigravity" {
            Invoke-AntigravityManualRefresh $controls | Out-Null
        }
    }
}

function Update-Widget($controls) {
    $usage = Get-CodexUsage
    $activity = Get-TokenActivitySummary
    $minimax = if ([bool](Get-ObjectValue $script:ProviderEnabledMap "minimax" $false)) {
        Get-MinimaxUsage
    } else {
        $script:MinimaxRemoteState.Usage
    }
    $grok = if ([bool](Get-ObjectValue $script:ProviderEnabledMap "grok" $false)) {
        Get-GrokUsage
    } else {
        $script:GrokRemoteState.Usage
    }
    $antigravity = if ([bool](Get-ObjectValue $script:ProviderEnabledMap "antigravity" $false)) {
        Get-AntigravityUsage
    } else {
        $script:AntigravityRemoteState.Usage
    }

    Apply-WidgetData $controls $usage $minimax $activity $grok $antigravity

    if (($usage -and $usage.ok) -or ($minimax -and $minimax.ok) -or ($grok -and $grok.ok) -or ($antigravity -and $antigravity.ok)) {
        $providerUsageMap = [ordered]@{
            codex = $usage
            minimax = $minimax
            grok = $grok
            antigravity = $antigravity
        }
        $script:UsageSnapshot = New-UsageSnapshot $usage $minimax $activity $providerUsageMap
        Save-State $controls.Window
    }
}

function Get-CodexSessionChangeKey {
    try {
        $parts = @()
        if (Test-Path $script:CodexSessionsDir) {
            $files = Get-ChildItem -Path $script:CodexSessionsDir -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 3
            $parts += @($files | ForEach-Object {
                "{0}|{1}|{2}" -f $_.FullName, $_.LastWriteTimeUtc.Ticks, $_.Length
            })
        }

        foreach ($path in @($script:CodexLogsPath, $script:CodexLogsPath + "-wal")) {
            if (Test-Path $path) {
                $item = Get-Item $path -ErrorAction SilentlyContinue
                if ($item) {
                    $parts += "{0}|{1}|{2}" -f $item.FullName, $item.LastWriteTimeUtc.Ticks, $item.Length
                }
            }
        }

        if ($parts.Count -eq 0) {
            return ""
        }

        return ($parts -join ";")
    } catch {
        return ""
    }
}

function Start-CodexSessionWatcher($controls) {
    if (-not $controls) {
        return
    }

    if ($null -ne $script:CodexSessionChangeTimer) {
        return
    }

    $script:CodexLastSessionChangeKey = Get-CodexSessionChangeKey
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(700)
    $timer.Tag = $controls
    $timer.Add_Tick({
        param($sender)
        Invoke-GuardedUiAction "CodexSessionWatcher.Tick" {
            $currentKey = Get-CodexSessionChangeKey
            if ($currentKey -and $currentKey -ne $script:CodexLastSessionChangeKey) {
                $script:CodexLastSessionChangeKey = $currentKey
                Update-Widget $sender.Tag
            }
        } | Out-Null
    })
    $timer.Start()
    $script:CodexSessionChangeTimer = $timer
}

function Stop-CodexSessionWatcher {
    if ($null -ne $script:CodexSessionChangeTimer) {
        $script:CodexSessionChangeTimer.Stop()
        $script:CodexSessionChangeTimer = $null
    }

    $script:CodexLastSessionChangeKey = ""
}

function New-TrayIcon($window) {
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Text = "AI Usage Meter"
    if (Test-Path $script:IconPath) {
        $tray.Icon = New-Object System.Drawing.Icon $script:IconPath
    } else {
        $tray.Icon = [System.Drawing.SystemIcons]::Application
    }
    $tray.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $dashboardItem = New-Object System.Windows.Forms.ToolStripMenuItem "Codex Usage Dashboard"
    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem "Exit"
    $menu.Items.Add($dashboardItem) | Out-Null
    $menu.Items.Add($exitItem) | Out-Null
    $tray.ContextMenuStrip = $menu
    $tray.Tag = $menu

    $showAction = {
        Show-UsageWindow $window
    }
    $dashboardItem.Add_Click({
        [System.Diagnostics.Process]::Start($script:CodexUsageDashboardUrl) | Out-Null
    })
    $exitItem.Add_Click({
        $window.Close()
    })

    return $tray
}

function Build-Widget {
    $state = Read-State
    $config = Read-Config
    $script:ProviderEnabledMap = Get-ProviderEnabledMap $config
    $script:ProviderVisibility = Normalize-ProviderVisibilityMap (Get-ObjectValue $state "providers" $null) $script:ProviderEnabledMap
    Initialize-UsageFloorState $state

    # Compatibility bridge until rendering moves fully to the shared provider model.
    $script:CodexEnabled = Test-ProviderVisible "codex"
    $script:MinimaxEnabled = Test-ProviderVisible "minimax"
    $script:CompactMode = [bool](Get-ObjectValue $state "compactMode" $false)
    $script:UsageDisplayMode = Normalize-UsageDisplayMode (Get-ObjectValue $state "displayMode" "used")
    $script:TopmostEnabled = [bool](Get-ObjectValue $state "topmost" $true)
    $script:UsageSnapshot = Get-ObjectValue $state "usageSnapshot" $null
    Restore-GrokRuntimeUsage $script:UsageSnapshot | Out-Null
    $script:HoverDetailOpenDelayMs = [int](Get-ObjectValue $config "hoverOpenDelayMs" 2000)

    $window = New-Object System.Windows.Window
    $window.Title = "AI Usage Meter"
    if (Test-Path $script:IconPath) {
        $iconStream = [System.IO.File]::OpenRead($script:IconPath)
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconStream)
    }
    $window.Width = $script:WidgetWidth
    $window.Height = $script:WidgetHeight
    $window.MinWidth = $script:WidgetWidth
    $window.MaxWidth = $script:WidgetWidth
    $window.MinHeight = 200
    $window.MaxHeight = 600
    $window.SizeToContent = "Manual"
    $window.WindowStyle = "None"
    $window.AllowsTransparency = $true
    $window.Background = [System.Windows.Media.Brushes]::Transparent
    $window.UseLayoutRounding = $true
    $window.SnapsToDevicePixels = $true
    $window.ResizeMode = "NoResize"
    Set-WindowTopmost $window
    $window.Left = [double]$state.left
    $window.Top = [double]$state.top
    $window.Opacity = 1.0
    $window.ShowInTaskbar = $false

    $outer = New-Object System.Windows.Controls.Border
    $outer.Margin = "6"
    $outer.Padding = "10,10,10,6"
    $outer.CornerRadius = 16
    $outer.BorderThickness = 1
    $outer.BorderBrush = Get-Brush "#AAB7BD"
    $outer.Background = Get-Brush "#E00E1821"
    $outer.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
        BlurRadius = 8
        ShadowDepth = 0
        Opacity = 0.18
        Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#02080E")
    }

    $root = New-Object System.Windows.Controls.Grid
    $root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
    $root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))

    $content = New-Object System.Windows.Controls.StackPanel
    $content.Margin = "0,0,0,0"
    [System.Windows.Controls.Grid]::SetRow($content, 0)

    $sectionsPanel = New-Object System.Windows.Controls.StackPanel
    $sectionsPanel.Margin = "0,0,0,4"
    $providerSections = [ordered]@{}
    foreach ($providerId in (Get-ProviderIds)) {
        $metadata = Get-ProviderMetadata $providerId
        $providerSection = New-ProviderSection $metadata
        $providerSections[$providerId] = $providerSection
        $sectionsPanel.Children.Add($providerSection.Section) | Out-Null
    }

    $content.Children.Add($sectionsPanel) | Out-Null

    $compactContent = New-Object System.Windows.Controls.Primitives.UniformGrid
    $compactContent.Visibility = "Collapsed"
    $compactContent.Columns = (Get-CompactLayoutMetrics (Get-VisibleProviderCount)).Columns
    $compactProviders = [ordered]@{}
    foreach ($providerId in (Get-ProviderIds)) {
        $metadata = Get-ProviderMetadata $providerId
        $compactPanel = New-CompactProviderPanel $metadata.title $metadata.accent
        $compactProviders[$providerId] = $compactPanel
        $compactContent.Children.Add($compactPanel.panel) | Out-Null
    }

    $root.Children.Add($content) | Out-Null
    $root.Children.Add($compactContent) | Out-Null

    $updated = New-TextBlock "" 1 "Normal" "#AAB4BB"
    $updated.Visibility = "Collapsed"

    $outer.Child = $root
    $window.Content = $outer
    $window.Visibility = "Visible"

    $root.Add_Loaded({
        Invoke-GuardedUiAction "Root.Loaded" {
            Sync-ProviderVisibility $controls
            Apply-CachedUsageSnapshot $controls $script:UsageSnapshot | Out-Null

            $script:StartupRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:StartupRefreshTimer.Interval = [TimeSpan]::FromMilliseconds(120)
            $script:StartupRefreshTimer.Add_Tick({
                param($sender)
                Invoke-GuardedUiAction "StartupRefreshTimer.Tick" {
                    $sender.Stop()
                    $script:StartupRefreshTimer = $null
                    Update-Widget $controls
                    Start-CodexSessionWatcher $controls
                } | Out-Null
            })
            $script:StartupRefreshTimer.Start()
        } | Out-Null
    })

    $controls = [pscustomobject]@{
        Window = $window
        Outer = $outer
        FullContent = $content
        CompactContent = $compactContent
        ProviderSections = $providerSections
        CompactProviders = $compactProviders
        Updated = $updated
    }
    $null = Get-HoverDetailState $controls

    foreach ($providerId in (Get-ProviderIds)) {
        $providerSection = Get-ObjectValue $providerSections $providerId $null
        if ($providerSection -and $providerSection.ActionButton) {
            $providerSection.ActionButton.Tag = $providerId
            $providerSection.ActionButton.Add_Click({
                param($sender)
                Invoke-ProviderRefreshAction ([string]$sender.Tag) $controls
            })
        }

        $compactControl = Get-ObjectValue $compactProviders $providerId $null
        if ($compactControl) {
            $compactControl.panel.Tag = $providerId
            $compactControl.panel.Add_MouseEnter({
                param($sender)
                Invoke-GuardedUiAction "CompactProvider.MouseEnter" {
                    Handle-CompactProviderMouseEnter $controls ([string]$sender.Tag) $sender
                } | Out-Null
            })
            $compactControl.panel.Add_MouseLeave({
                param($sender)
                Invoke-GuardedUiAction "CompactProvider.MouseLeave" {
                    Handle-CompactProviderMouseLeave ([string]$sender.Tag)
                } | Out-Null
            })
        }
    }

    $tray = New-TrayIcon $window

    $contextMenuOpeningHandler = {
        param($sender, $event)
        Invoke-GuardedUiAction "ContextMenu.Opening" {
            $sender.ContextMenu = Build-ProviderContextMenu $window $controls
        } | Out-Null
    }

    $outer.ContextMenu = Build-ProviderContextMenu $window $controls
    $root.ContextMenu = Build-ProviderContextMenu $window $controls
    $content.ContextMenu = Build-ProviderContextMenu $window $controls
    $compactContent.ContextMenu = Build-ProviderContextMenu $window $controls
    $outer.Add_ContextMenuOpening($contextMenuOpeningHandler)
    $root.Add_ContextMenuOpening($contextMenuOpeningHandler)
    $content.Add_ContextMenuOpening($contextMenuOpeningHandler)
    $compactContent.Add_ContextMenuOpening($contextMenuOpeningHandler)

    $dragHandler = {
        param($sender, $event)
        Invoke-GuardedUiAction "Outer.MouseLeftButtonDown" {
            Hide-HoverDetailWindow
            if ($event.ClickCount -ge 2) {
                Toggle-WidgetMode $window $controls
                $event.Handled = $true
                return
            }

            if ([System.Windows.Input.Mouse]::LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
                try { $window.DragMove() } catch { }
            }
        } | Out-Null
    }
    $outer.Add_MouseLeftButtonDown($dragHandler)

    $window.Add_LocationChanged({
        Invoke-GuardedUiAction "Window.LocationChanged" {
            $hoverState = Get-HoverDetailState
            if ($hoverState.Window -and $hoverState.Window.IsVisible) {
                Set-HoverDetailWindowPosition $hoverState.Window $hoverState.SourcePanel
            }
            if ($script:CompactMode) {
                Sync-CompactTopmostTimer $window
            }
            Save-State $window
        } | Out-Null
    })
    $window.Add_Deactivated({
        Invoke-GuardedUiAction "Window.Deactivated" {
            Start-HoverDetailCloseTimer
            if ($script:CompactMode) {
                Sync-CompactTopmostTimer $window
            }
        } | Out-Null
    })
    $window.Add_Activated({
        Invoke-GuardedUiAction "Window.Activated" {
            if ($script:CompactMode) {
                Sync-CompactTopmostTimer $window
            }
        } | Out-Null
    })
    $window.Add_Closed({
        Invoke-GuardedUiAction "Window.Closed" {
            Hide-HoverDetailWindow
            $hoverState = Get-HoverDetailState
            Stop-DispatcherTimer $hoverState.OpenTimer
            Stop-DispatcherTimer $hoverState.CloseTimer
            if ($hoverState.Window) {
                try {
                    $hoverState.Window.Close()
                } catch {
                }
                $hoverState.Window = $null
            }
            if ($null -ne $script:CompactTopmostTimer) {
                $script:CompactTopmostTimer.Stop()
                $script:CompactTopmostTimer = $null
            }
            Stop-CodexSessionWatcher
            Save-State $window
            if ($null -ne $tray) {
                $tray.Visible = $false
                $tray.Dispose()
            }
        } | Out-Null
    })

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds([Math]::Max(1, [int]$state.refreshSeconds))
    $timer.Add_Tick({
        Invoke-GuardedUiAction "WidgetRefreshTimer.Tick" {
            Update-Widget $controls
        } | Out-Null
    })
    $timer.Start()

    $window.ShowDialog()
}

if ($env:USAGE_WIDGET_TEST_MODE -ne "1") {
    Build-Widget | Out-Null
}
