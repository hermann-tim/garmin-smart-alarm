param(
    [Parameter(Mandatory = $true)][string]$Page,
    [Parameter(Mandatory = $true)][string[]]$Members,
    [string]$Device = 'Forerunner.{0,3}265(?![0-9A-Za-z])'
)
# For each member's detail section in an SDK doc page, report "Since" and whether the device is listed as supported.
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
$path = Join-Path $sdk "doc\Toybox\$Page.html"
$html = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$html = [regex]::Replace($html, '(?s)<script.*?</script>', ' ')
$text = [regex]::Replace($html, '<[^>]+>', ' ')
$text = [System.Net.WebUtility]::HtmlDecode($text)
$text = [regex]::Replace($text, '\s+', ' ')
$detailStart = $text.IndexOf("Details")
foreach ($m in $Members) {
    # find the detail section (last occurrence pattern: "<member>(" or "var <member>")
    $candidates = @()
    foreach ($pat in @("var $m as", "$m(", "const $m =", "$m =")) {
        $i = $text.LastIndexOf($pat)
        if ($i -ge 0) { $candidates += $i }
    }
    if ($candidates.Count -eq 0) { "$m : NOT FOUND"; continue }
    $i = ($candidates | Measure-Object -Maximum).Maximum
    $seg = $text.Substring($i, [Math]::Min(12000, $text.Length - $i))
    # cut at the next member detail (heuristic: next "Since: API Level" after the supported devices list)
    $since = [regex]::Match($seg, 'Since: API Level ([0-9.]+)').Groups[1].Value
    $supIdx = $seg.IndexOf("Supported Devices:")
    $supported = "n/a"
    if ($supIdx -ge 0) {
        $rest = $seg.Substring($supIdx)
        $end = $rest.IndexOf(" Since:", 20)
        $end2 = $rest.IndexOf("Returns:", 20)
        $cut = @($end, $end2) | Where-Object { $_ -gt 0 } | Measure-Object -Minimum
        if ($cut.Count -gt 0) { $rest = $rest.Substring(0, $cut.Minimum) }
        $supported = [regex]::IsMatch($rest, $Device)
    }
    "$m : since=$since supported($Device)=$supported"
}
