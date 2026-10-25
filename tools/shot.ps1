# Screenshot a visible window, or -List visible windows.
# Windows are matched in Z-order (topmost first): title contains -Title, process name equals -Process.
param([string]$Title = '', [string]$Process = '', [string]$Out, [switch]$List)
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # non-ASCII window titles
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
}
'@
[W]::SetProcessDPIAware() | Out-Null

# collect visible titled windows in Z-order (output from inside the callback is swallowed)
$wins = New-Object Collections.Generic.List[object]
[W]::EnumWindows({ param($h,$l)
  if ([W]::IsWindowVisible($h)) {
    $sb = New-Object Text.StringBuilder 512; [W]::GetWindowText($h,$sb,512) | Out-Null
    if ($sb.Length -gt 0) {
      $p = [uint32]0; [W]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
      $r = New-Object W+RECT; [W]::DwmGetWindowAttribute($h, 9, [ref]$r, 16) | Out-Null
      $wins.Add([pscustomobject]@{ H=$h; Title=$sb.ToString(); Min=[W]::IsIconic($h);
        Proc=(Get-Process -Id $p -ErrorAction SilentlyContinue).ProcessName; W=$r.R-$r.L; Ht=$r.B-$r.T }) } }
  return $true }, [IntPtr]::Zero) | Out-Null

if ($List) {
  foreach ($w in $wins) { "{0,-22} {1,10} {2,-3} {3}" -f $w.Proc, "$($w.W)x$($w.Ht)", $(if ($w.Min) {'MIN'} else {'-'}), $w.Title }
  exit 0
}
$match = @($wins | Where-Object { $_.Title -like "*$Title*" -and (-not $Process -or $_.Proc -eq $Process) })
$w = $match | Where-Object { -not $_.Min } | Select-Object -First 1
if (-not $w) {
  if ($match) { "MINIMIZED: '$($match[0].Title)' - restore it first"; exit 3 }
  "NOT FOUND"; exit 2
}
$bmp = New-Object Drawing.Bitmap $w.W, $w.Ht
$g = [Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
[W]::PrintWindow($w.H, $hdc, 2) | Out-Null; $g.ReleaseHdc($hdc)
$bmp.Save($Out); "OK $($w.W)x$($w.Ht) [$($w.Proc)] $($w.Title)"
