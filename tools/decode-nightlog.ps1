param(
    [Parameter(Mandatory = $true)][string[]]$Files,
    [string]$CsvOut = ""
)
# Decodes SmartWake night protocol lines ("SW D<min>:...") into minute rows.
# 7 chars per minute: movement, pulse, HRV, stress, breathing, score, stage.
$alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
function Dec([char]$c) { if ($c -eq '.') { return $null }; return $alphabet.IndexOf($c) }

$lines = @()
foreach ($f in $Files) { if (Test-Path $f) { $lines += Get-Content $f } }
$rows = @()
$nights = 0
foreach ($line in $lines) {
    $l = $line.Trim()
    if ($l -match '^SW START') { $nights++ }
    if ($l -match '^SW (START|MODEL|RESTART|RING|CYC|WAKE|LEARN|SNOOZE|OFF|FEEL|CANCEL)') { "[night $nights] $l" }
    if ($l -match '^SW D(\d+):(.*)$') {
        $start = [int]$Matches[1]; $data = $Matches[2]
        for ($i = 0; $i + 7 -le $data.Length; $i += 7) {
            $m = Dec $data[$i]; $hr = Dec $data[$i + 1]; $rm = Dec $data[$i + 2]; $st = Dec $data[$i + 3]
            $rr = Dec $data[$i + 4]; $sc = Dec $data[$i + 5]; $sg = Dec $data[$i + 6]
            $rows += [pscustomobject]@{
                night  = $nights
                min    = $start + $i / 7
                move   = [math]::Round($m * 100 / 63)
                pulse  = $(if ($null -ne $hr) { $hr + 30 } else { $null })
                hrv    = $(if ($null -ne $rm) { $rm * 3 } else { $null })
                stress = $(if ($null -ne $st) { $st * 2 } else { $null })
                breath = $(if ($null -ne $rr) { [math]::Round(4 + $rr / 4, 2) } else { $null })
                score  = [math]::Round($sc * 100 / 63)
                stage  = @('tief', 'leicht', 'wach')[$sg]
            }
        }
    }
}
"--- $($rows.Count) minutes decoded"
if ($CsvOut) { $rows | Export-Csv -Path $CsvOut -NoTypeInformation -Encoding UTF8; "csv: $CsvOut" }
$rows
