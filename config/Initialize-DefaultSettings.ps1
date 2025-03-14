# Initialize-DefaultSettings.ps1 (Tokenoptimiert)
# Speicherort: config-Verzeichnis
# Erstellt alle erforderlichen Konfigurationsdateien

# Pfade definieren
$cfgPath = $PSScriptRoot
$rootPath = Split-Path -Parent $PSScriptRoot

# Verzeichnisprüfung
if (!(Test-Path $cfgPath)) {
    md $cfgPath -Force >$null
    Write-Host "Konfigurationsverzeichnis erstellt: $cfgPath" -ForegroundColor Green
}

# Konfigurationsdatei erstellen/aktualisieren
function Init {
    param (
        [Parameter(Mandatory)]
        [string]$f,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$def,
        
        [switch]$force
    )
    
    $p = "$cfgPath\$f"
    
    # Erstellen wenn nicht vorhanden oder Überschreiben erzwungen
    if (!(Test-Path $p) -or $force) {
        try {
            $def | ConvertTo-Json -Depth 4 | Set-Content $p
            Write-Host "Konfiguration erstellt: $f" -ForegroundColor Green
        } catch {
            Write-Host "Fehler: $f - $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Konfiguration existiert: $f" -ForegroundColor Yellow
    }
}

# settings.json (Logging)
$defSettings = [PSCustomObject]@{
    Logging = [PSCustomObject]@{
        Enabled = $false
        Path = "temp\logs"
        Mode = "PiM"
    }
}

# Konfigurationen erstellen
Init -f "settings.json" -def $defSettings

# user-settings.json
$userSettings = [PSCustomObject]@{
    Theme = "Default"
    Language = "de-DE"
    AutoUpdate = $true
    LastCheck = (Get-Date).ToString("yyyy-MM-dd")
}

# Nur erstellen wenn nicht vorhanden
Init -f "user-settings.json" -def $userSettings

# Installationshinweis
Write-Host "`nKonfigurationen überprüft." -ForegroundColor Cyan
Write-Host "Dieses Skript kann bei jeder Installation ausgeführt werden," -ForegroundColor Cyan
Write-Host "um alle erforderlichen Konfigurationsdateien zu erstellen." -ForegroundColor Cyan

# Reset-Abfrage
$r = Read-Host "`nAlle Konfigurationen zurücksetzen? (j/n)"
if ($r -eq "j") {
    # Alle mit Standardwerten überschreiben
    Init -f "settings.json" -def $defSettings -force
    Init -f "user-settings.json" -def $userSettings -force
    
    Write-Host "`nAlle Konfigurationen zurückgesetzt." -ForegroundColor Green
}