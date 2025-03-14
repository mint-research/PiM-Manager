# Initialize-DefaultSettings.ps1 (Tokenoptimiert)
# Speicherort: config-Verzeichnis
# Erstellt alle erforderlichen Konfigurationsdateien

# Pfade definieren
$cfgPath = $PSScriptRoot
$rootPath = Split-Path -Parent $PSScriptRoot

# Verzeichnisprüfung
if (-not (Test-Path $cfgPath)) {
    mkdir $cfgPath -Force >$null
    Write-Host "Konfigurationsverzeichnis erstellt: $cfgPath" -ForegroundColor Green
}

# Konfigurationsdatei erstellen/aktualisieren
function InitCfg {
    param (
        [Parameter(Mandatory=$true)]
        [string]$file,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$defaults,
        
        [switch]$force
    )
    
    $path = "$cfgPath\$file"
    
    # Erstellen wenn nicht vorhanden oder Überschreiben erzwungen
    if (-not (Test-Path $path) -or $force) {
        try {
            $defaults | ConvertTo-Json -Depth 4 | Set-Content $path
            Write-Host "Konfiguration erstellt: $file" -ForegroundColor Green
        } catch {
            Write-Host "Fehler: $file - $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Konfiguration existiert: $file" -ForegroundColor Yellow
    }
}

# settings.json (Logging)
$defaultSettings = [PSCustomObject]@{
    Logging = [PSCustomObject]@{
        Enabled = $false
        Path = "docs\logs"
        Mode = "PiM"
    }
}

# Konfigurationen erstellen
InitCfg -file "settings.json" -defaults $defaultSettings

# user-settings.json
$userSettings = [PSCustomObject]@{
    Theme = "Default"
    Language = "de-DE"
    AutoUpdate = $true
    LastCheck = (Get-Date).ToString("yyyy-MM-dd")
}

# Nur erstellen wenn nicht vorhanden
InitCfg -file "user-settings.json" -defaults $userSettings

# Installationshinweis
Write-Host "`nKonfigurationen überprüft." -ForegroundColor Cyan
Write-Host "Dieses Skript kann bei jeder Installation ausgeführt werden," -ForegroundColor Cyan
Write-Host "um alle erforderlichen Konfigurationsdateien zu erstellen." -ForegroundColor Cyan

# Reset-Abfrage
$reset = Read-Host "`nAlle Konfigurationen zurücksetzen? (j/n)"
if ($reset -eq "j") {
    # Alle mit Standardwerten überschreiben
    InitCfg -file "settings.json" -defaults $defaultSettings -force
    InitCfg -file "user-settings.json" -defaults $userSettings -force
    
    Write-Host "`nAlle Konfigurationen zurückgesetzt." -ForegroundColor Green
}