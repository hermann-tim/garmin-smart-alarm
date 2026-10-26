param(
    [Parameter(Mandatory = $true)][string]$Out,
    [switch]$Full
)
# Captures the Connect IQ simulator window (even if covered) and saves the watch display area as PNG.
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SimWin {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hwnd, out RECT rect);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$proc = Get-Process -Name simulator -ErrorAction Stop | Select-Object -First 1
$h = $proc.MainWindowHandle
$r = New-Object SimWin+RECT
[SimWin]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.Right - $r.Left
$hh = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[SimWin]::PrintWindow($h, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"saved $Out ($w x $hh)"
