param(
    # Button: enter, up, down, esc, menu (= hold up), or "tap" with -X/-Y in watch display pixels (0..415)
    [Parameter(Mandatory = $true)][string]$Button,
    [int]$X = 208,
    [int]$Y = 208,
    [int]$HoldMs = 120
)
# Sends mouse clicks to the Connect IQ simulator without moving the real cursor.
# The simulator draws the device image (fr265.png) 1:1 at the top-left of its client area.
# The target child window is searched inside the simulator window, so it also works when covered.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SimIn3 {
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hwnd, ref POINT p);
    [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr hwnd, ref POINT p);
    [DllImport("user32.dll")] public static extern IntPtr ChildWindowFromPointEx(IntPtr parent, POINT p, uint flags);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@
$proc = Get-Process -Name simulator -ErrorAction Stop | Select-Object -First 1
$h = $proc.MainWindowHandle
$buttons = @{
    "enter" = @(571, 308); "up" = @(37, 437); "menu" = @(37, 437); "down" = @(73, 578); "esc" = @(563, 575)
}
if ($Button -eq "tap") {
    $ix = 114 + $X; $iy = 231 + $Y
} else {
    $ix = $buttons[$Button][0]; $iy = $buttons[$Button][1]
}
if ($Button -eq "menu" -and $HoldMs -lt 1500) { $HoldMs = 1800 }

# screen position of the point
$screen = New-Object SimIn3+POINT
$screen.X = $ix; $screen.Y = $iy
[SimIn3]::ClientToScreen($h, [ref]$screen) | Out-Null

# walk down the child windows of the simulator that contain the point
$target = $h
for ($depth = 0; $depth -lt 10; $depth++) {
    $cp = New-Object SimIn3+POINT
    $cp.X = $screen.X; $cp.Y = $screen.Y
    [SimIn3]::ScreenToClient($target, [ref]$cp) | Out-Null
    $child = [SimIn3]::ChildWindowFromPointEx($target, $cp, 1 + 4)   # skip invisible + transparent
    if ($child -eq [IntPtr]::Zero -or $child -eq $target) { break }
    $target = $child
}
$cp = New-Object SimIn3+POINT
$cp.X = $screen.X; $cp.Y = $screen.Y
[SimIn3]::ScreenToClient($target, [ref]$cp) | Out-Null
$lparam = [IntPtr](($cp.Y -shl 16) -bor ($cp.X -band 0xFFFF))
[SimIn3]::PostMessage($target, 0x0200, [IntPtr]0, $lparam) | Out-Null   # WM_MOUSEMOVE
[SimIn3]::PostMessage($target, 0x0201, [IntPtr]1, $lparam) | Out-Null   # WM_LBUTTONDOWN
Start-Sleep -Milliseconds $HoldMs
[SimIn3]::PostMessage($target, 0x0202, [IntPtr]0, $lparam) | Out-Null   # WM_LBUTTONUP
"clicked $Button -> target client ($($cp.X),$($cp.Y)) hwnd=$target main=$h"
