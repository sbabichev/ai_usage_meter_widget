Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$outDir = Join-Path $root "assets"
$outPath = Join-Path $outDir "codex-usage-meter.ico"

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

function New-TrayGaugeBitmap($size) {
    $bitmap = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $scale = $size / 24.0
    $stroke = [Math]::Max(1.35, 2.15 * $scale)
    $corner = 5 * $scale
    $bounds = New-Object System.Drawing.RectangleF (1.5 * $scale), (1.5 * $scale), (21 * $scale), (21 * $scale)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $corner * 2
    $path.AddArc($bounds.X, $bounds.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($bounds.Right - $diameter, $bounds.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($bounds.Right - $diameter, $bounds.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($bounds.X, $bounds.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()

    $bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 11, 18, 25))
    $graphics.FillPath($bgBrush, $path)

    $rimPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(150, 111, 232, 255)), ([Math]::Max(1.0, 0.9 * $scale))
    $graphics.DrawPath($rimPen, $path)

    # Lucide gauge icon, adapted to remain legible in the Windows tray.
    $arcPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(235, 238, 247, 250)), $stroke
    $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $arcRect = New-Object System.Drawing.RectangleF (4 * $scale), (6 * $scale), (16 * $scale), (16 * $scale)
    $graphics.DrawArc($arcPen, $arcRect, 205, 130)

    $needlePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 138, 61)), ([Math]::Max(1.25, 2.0 * $scale))
    $needlePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $needlePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLine($needlePen, (12 * $scale), (14 * $scale), (16 * $scale), (10 * $scale))

    $graphics.Dispose()
    return $bitmap
}

function Convert-BitmapToIconBytes($bitmap) {
    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter $stream
    try {
        $width = $bitmap.Width
        $height = $bitmap.Height
        $xorBytes = $width * $height * 4
        $maskStride = [int]([Math]::Ceiling($width / 32.0) * 4)
        $maskBytes = $maskStride * $height

        $writer.Write([UInt32]40)
        $writer.Write([Int32]$width)
        $writer.Write([Int32]($height * 2))
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]0)
        $writer.Write([UInt32]$xorBytes)
        $writer.Write([Int32]0)
        $writer.Write([Int32]0)
        $writer.Write([UInt32]0)
        $writer.Write([UInt32]0)

        for ($y = $height - 1; $y -ge 0; $y--) {
            for ($x = 0; $x -lt $width; $x++) {
                $pixel = $bitmap.GetPixel($x, $y)
                $writer.Write([byte]$pixel.B)
                $writer.Write([byte]$pixel.G)
                $writer.Write([byte]$pixel.R)
                $writer.Write([byte]$pixel.A)
            }
        }

        if ($maskBytes -gt 0) {
            $writer.Write((New-Object byte[] $maskBytes))
        }

        $writer.Flush()
        return ,$stream.ToArray()
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Write-IconFile($path, $sizes) {
    $entries = @()
    foreach ($size in $sizes) {
        $bitmap = New-TrayGaugeBitmap $size
        $entries += [pscustomobject]@{
            Size = $size
            Bytes = Convert-BitmapToIconBytes $bitmap
        }
        $bitmap.Dispose()
    }

    $stream = [System.IO.File]::Create($path)
    $writer = New-Object System.IO.BinaryWriter $stream
    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$entries.Count)

        $offset = 6 + ($entries.Count * 16)
        foreach ($entry in $entries) {
            $writer.Write([byte]$(if ($entry.Size -ge 256) { 0 } else { $entry.Size }))
            $writer.Write([byte]$(if ($entry.Size -ge 256) { 0 } else { $entry.Size }))
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$entry.Bytes.Length)
            $writer.Write([UInt32]$offset)
            $offset += $entry.Bytes.Length
        }

        foreach ($entry in $entries) {
            $writer.Write($entry.Bytes)
        }
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

Write-IconFile $outPath @(16, 32, 48)

Write-Host "Created $outPath"
