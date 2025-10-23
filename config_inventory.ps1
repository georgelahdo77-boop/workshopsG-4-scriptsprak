# Bas vägar
$root = Join-Path $PSScriptRoot 'network_configs'
if (-not (Test-Path $root)) {
    throw "Hittar inte mappen: $root"
}

# Hämtar Konfigurationsfiler
$configFiles = @()
$configFiles += Get-ChildItem -Path $root -Filter '*.conf'  -Recurse -File
$configFiles += Get-ChildItem -Path $root -Filter '*.rules' -Recurse -File

# Bygg poster för CSV
$inventory = $configFiles | ForEach-Object {
    $rel = $_.FullName.Substring($root.Length + 1)
    [PSCustomObject]@{
        Name          = $_.Name
        RelativPath   = $rel
        Extension     = $_.Extension
        SizeKB        = [Math]::Round(($_.Length / 1KB), 2)
        LastWriteTime = $_.LastWriteTime
    }
}

# Exportera CSV
$csvPath = Join-Path $PSScriptRoot 'config_inventory.csv'
$inventory |
Sort-Object RelativPath, Name |
Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

Write-Host " CSV exporterad: $csvPath" -ForegroundColor Green
Write-Host "Antal Konfigurationsfiler: $($inventory.Count)"