param(
    [Parameter(Mandatory = $true)][string]$Page,
    [string[]]$Keywords = @(),
    [int]$Context = 400,
    [int]$MaxChars = 6000
)
# Converts an SDK doc HTML page to plain text and prints snippets around keywords.
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
$path = Join-Path $sdk "doc\Toybox\$Page.html"
$html = Get-Content $path -Raw
$html = [regex]::Replace($html, '(?s)<script.*?</script>', ' ')
$html = [regex]::Replace($html, '(?s)<style.*?</style>', ' ')
$text = [regex]::Replace($html, '<[^>]+>', ' ')
$text = [System.Net.WebUtility]::HtmlDecode($text)
$text = [regex]::Replace($text, '\s+', ' ')
if ($Keywords.Count -eq 0) {
    $text.Substring(0, [Math]::Min($MaxChars, $text.Length))
    return
}
$out = ""
foreach ($k in $Keywords) {
    $idx = 0
    $hits = 0
    while (($idx = $text.IndexOf($k, $idx, [StringComparison]::OrdinalIgnoreCase)) -ge 0 -and $hits -lt 2) {
        $start = [Math]::Max(0, $idx - 80)
        $len = [Math]::Min($Context, $text.Length - $start)
        $out += "`n[[${k}]] ..." + $text.Substring($start, $len) + "...`n"
        $idx += $k.Length + $Context
        $hits++
    }
}
$out.Substring(0, [Math]::Min($MaxChars, $out.Length))
