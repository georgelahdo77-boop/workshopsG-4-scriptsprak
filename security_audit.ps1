# Basvägar
$root = Join-Path $PSScriptRoot 'network_configs'
if (-not(Test-Path $root)) {
    throw "Hittar inte mappen: $root"
}

# Datum
$now = Get-Date "2024-10-14"
$weekAgo = $now.AddDays(-7)

# Hämtar filer
$configConf = Get-ChildItem -Path $root -Filter '*.conf'  -Recurse  -File
$configRules = Get-ChildItem -Path $root -Filter '*.rules' -Recurse  -File
$logFiles = Get-ChildItem -Path $root -Filter '*.log'   -Recurse  -File

$allFiles = @()
$allFiles += $configConf
$allFiles += $configRules
$allFiles += $logFiles

# Använda hjälpfunktion: relativ sökväg inne i network_configs
function Get-RelPath([string]$full) {
    try {
        return [System.IO.Path]::GetRelativePath($root, $full)
    }
    catch {
        return $full
    }
}

# Lista alla .conf/.rules/.log
$listing = $allFiles | ForEach-Object {
    [PSCustomObject]@{
        Name          = $_.Name
        Ext           = $_.Extension
        SizeKB        = [Math]::Round(($_.Length / 1KB), 2)
        LastWriteTime = $_.LastWriteTime
        RelativePath  = (Get-RelPath $_.FullName)
    }
} | Sort-Object RelativePath, Name
    
# Nyligen ändrade filer senaste 7 dagar tills nu
$recent = $allFiles |
Where-Object { $_.LastWriteTime -ge $weekAgo -and $_.LastWriteTime -le $now } |
Sort-Object LastWriteTime -Descending |
ForEach-Object {
    [PSCustomObject]@{
        Name          = $_.Name
        EXT           = $_.Extension
        LastWriteTime = $_.LastWriteTime
        RelativePath  = (Get-RelPath $_.FullName) 
    }
}

# Grupperar efter filtyp
$byType = $allFiles |
Group-Object Extension |
ForEach-Object {
    $sum = ($_.Group | Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        Extension = if ($_.Name) { $_.Name } else { '(ingen)' }
        Count     = $_.Count
        TotalMB   = [Math]::Round(($sum / 1MB), 2)
    }
} | Sort-Object Extension

# 5 största loggfiler
$largestLogs = $logFiles |
Sort-Object Length -Descending |
Select-Object -First 5 |
ForEach-Object {
    [PSCustomObject]@{
        Name         = $_.Name
        RelativePath = (Get-RelPath $_.FullName)
        SizeMB       = [Math]::Round(($_.Length / 1MB), 2)
    }
}

# IP-adresser i .conf - en lista med unika IP-adresser
$ipv4pattern = '\b(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}\b'

$ipMatches = Select-String -Path $configConf.FullName -Pattern $ipv4pattern -AllMatches | ForEach-Object {
    $_.Matches.Value
}

$uniqueIPs = $ipMatches | Where-Object { $_ } | Sort-Object -Unique

# Säkerhetsproblem i loggar: Error - Failed - Denied per fil
$incidentpattern = 'ERROR|FAILED|DENIED'

$logIncidents = Get-ChildItem -Path $root -Filter '*.log' -Recurse -File |
ForEach-Object {
    $content = Get-Content -Path $_.FullName -Raw
    $errCount = ([regex]'ERROR').Matches($content).Count
    $failed = ([regex]'FAILED').Matches($content).Count
    $denied = ([regex]'DENIED').Matches($content).Count
    $total = $errCount + $failed + $denied

    [PSCustomObject]@{
        LogFile      = $_.Name
        RelativePath = [System.IO.Path]::GetRelativePath($root, $_.FullName)
        ERROR        = $errCount
        FAILED       = $failed
        DENIED       = $denied
        Total        = $total
    }
} | 
Sort-Object -Property Total, LogFile -Descending

# Bygg rapporten
$reportpath = Join-Path $PSScriptRoot 'security_audit.txt'

$sb = New-Object System.Text.StringBuilder

# Rubrik
[void]$sb.AppendLine("Security Audit Report - TechCorp AB")
[void]$sb.AppendLine(("Generated: {2025-10-25 17:20:36}"))
[void]$sb.AppendLine("Root: network_configs")
[void]$sb.AppendLine(('-' * 72))

# Lista alla konfigurationsfiler
[void]$sb.AppendLine("FILE INVENTORY - Alla .conf/.rules/.log")
[void]$sb.AppendLine(($listing | Format-Table Name, Ext, SizeKB, LastWriteTime, RelativePath -AutoSize | Out-String -Width 4096))
[void]$sb.AppendLine(('-' * 72))

# Nyligen ändrade filer
[void]$sb.AppendLine(("Nyligen ändrade filer (senaste 7 dagar t.o.m. {0:yyyy-MM-dd})" -f $now))
if ($recent.Count -gt 0) {
    [void]$sb.AppendLine(($recent | Format-Table Name, Ext, LastWriteTime, RelativePath -AutoSize | Out-String -Width 4096))
}
else {
    [void]$sb.AppendLine("Inga filer ändrade i perioden $($weekAgo.ToString('yyyy-MM-dd')) - $($now.ToString('yyyy-MM-dd')).")
}
[void]$sb.AppendLine(('-' * 72))

# Grupperar filer efter typ
[void]$sb.AppendLine("Filer per type - antal och total storlek")
[void]$sb.AppendLine(($byType | Format-Table Extension, Count, TotalMB -AutoSize | Out-String -Width 4096))
[void]$sb.AppendLine(('-' * 72))

# 5 största loggfiler
[void]$sb.AppendLine(" 5 största loggfiler (MB)")
[void]$sb.AppendLine(($largestLogs | Format-Table Name, RelativePath, SizeMB -AutoSize | Out-String -Width 4096))
[void]$sb.AppendLine(('-' * 72))

# IP-adresser i .conf-filer
[void]$sb.AppendLine("Unika IP-adresser i .conf-filer")
if ($uniqueIPs.Count -ge 0) {
    $uniqueIPs | ForEach-Object { [void]$sb.AppendLine($_) }
}
else {
    [void]$sb.AppendLine("Inga IP-adresser hittades.")
}
[void]$sb.AppendLine(('-' * 72))


# Säkerhetsproblem i loggar
[void]$sb.AppendLine('Säkerhetsproblem i loggar: förekomster av "ERROR", "FAILED", "DENIED" per fil')
[void]$sb.AppendLine(
    ($logIncidents |
    Format-Table LogFile, RelativePath, ERROR, FAILED, DENIED, Total -AutoSize |
    Out-String -Width 4096)
)

# Spara
$sb.ToString() | Out-File -FilePath $reportpath -Encoding utf8

Write-Host "Rapport skapad: $reportpath" -ForegroundColor Green