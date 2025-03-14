# Initialize-DefaultSettings.ps1
# Sollte im config Verzeichnis abgelegt werden
# Dieses Skript stellt sicher, dass alle erforderlichen Konfigurationsdateien existieren

# Aktuelles Verzeichnis bestimmen (Das config-Verzeichnis)
$configPath = $PSScriptRoot
$rootPath = Split-Path -Parent $PSScriptRoot

# Sicherstellen, dass das Konfigurationsverzeichnis existiert
if (-not (Test-Path -Path $configPath)) {
    New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    Write-Host "Konfigurationsverzeichnis erstellt: $configPath" -ForegroundColor Green
}

# Funktion zum Erstellen oder Aktualisieren einer Konfigurationsdatei
function Initialize-ConfigFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FileName,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$DefaultSettings,
        
        [switch]$ForceOverwrite
    )
    
    $filePath = Join-Path -Path $configPath -ChildPath $FileName
    
    # Prüfen, ob die Datei existiert
    if (-not (Test-Path -Path $filePath) -or $ForceOverwrite) {
        try {
            # Konfiguration als JSON speichern
            $DefaultSettings | ConvertTo-Json -Depth 4 | Set-Content -Path $filePath
            Write-Host "Konfigurationsdatei erstellt/aktualisiert: $FileName" -ForegroundColor Green
        } catch {
            Write-Host "Fehler beim Erstellen der Konfigurationsdatei $FileName`: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Konfigurationsdatei existiert bereits: $FileName" -ForegroundColor Yellow
    }
}

# Standardwerte für settings.json (Logging-Einstellungen)
$defaultSettings = [PSCustomObject]@{
    Logging = [PSCustomObject]@{
        Enabled = $false
        Path = "docs\logs"
        Mode = "PiM"
    }
}

# Konfigurationsdatei erstellen/prüfen
Initialize-ConfigFile -FileName "settings.json" -DefaultSettings $defaultSettings

# Beispiel für eine weitere Konfigurationsdatei
$defaultUserSettings = [PSCustomObject]@{
    Theme = "Default"
    Language = "de-DE"
    AutoUpdate = $true
    LastCheck = (Get-Date).ToString("yyyy-MM-dd")
}

# Diese Konfigurationsdatei nur erstellen, wenn sie noch nicht existiert
Initialize-ConfigFile -FileName "user-settings.json" -DefaultSettings $defaultUserSettings

# Hinweis zur Verwendung bei der Installation ausgeben
Write-Host "`nAlle Standard-Konfigurationsdateien wurden überprüft und ggf. erstellt." -ForegroundColor Cyan
Write-Host "Dieses Skript kann bei jeder frischen Installation ausgeführt werden," -ForegroundColor Cyan
Write-Host "um sicherzustellen, dass alle erforderlichen Konfigurationsdateien vorhanden sind." -ForegroundColor Cyan

# Fragen, ob bestehende Konfigurationsdateien zurückgesetzt werden sollen
$resetExisting = Read-Host "`nMöchten Sie alle bestehenden Konfigurationsdateien zurücksetzen? (j/n)"
if ($resetExisting -eq "j") {
    # Alle Konfigurationsdateien mit Standard-Werten überschreiben
    Initialize-ConfigFile -FileName "settings.json" -DefaultSettings $defaultSettings -ForceOverwrite
    Initialize-ConfigFile -FileName "user-settings.json" -DefaultSettings $defaultUserSettings -ForceOverwrite
    
    Write-Host "`nAlle Konfigurationsdateien wurden auf Standardwerte zurückgesetzt." -ForegroundColor Green
}