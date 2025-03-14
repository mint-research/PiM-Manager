# Logging.ps1 - Script zum Aktivieren und Deaktivieren des Session-Loggings
# Speichert Einstellungen in config\settings.json

# Aktuelles Verzeichnis bestimmen (2 Ebenen nach oben vom scripts\admin Verzeichnis)
$rootPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path -Path $rootPath -ChildPath "config"
$settingsFile = Join-Path -Path $configPath -ChildPath "settings.json"

# Funktion zur Anzeige des aktuellen Logging-Status
function Show-LoggingStatus {
    # Überprüfen, ob die Konfigurationsdatei existiert
    if (Test-Path $settingsFile) {
        try {
            $settings = Get-Content -Path $settingsFile -Raw | ConvertFrom-Json
            
            $status = if ($settings.Logging.Enabled) { "Aktiviert" } else { "Deaktiviert" }
            $color = if ($settings.Logging.Enabled) { "Green" } else { "Red" }
            
            Write-Host "`nAktueller Logging-Status: " -NoNewline
            Write-Host $status -ForegroundColor $color
            
            # Zeige Logging-Pfad an, wenn aktiviert
            if ($settings.Logging.Enabled) {
                $loggingPath = Join-Path -Path $rootPath -ChildPath $settings.Logging.Path
                Write-Host "Logs werden gespeichert unter: $loggingPath" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "Fehler beim Lesen der Einstellungen: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "`nKeine Konfigurationsdatei gefunden. Logging ist standardmäßig deaktiviert." -ForegroundColor Yellow
    }
}

# Funktion zum Aktivieren des Loggings
function Enable-Logging {
    # Überprüfen, ob das Konfigurationsverzeichnis existiert
    if (-not (Test-Path $configPath)) {
        New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    }
    
    # Überprüfen, ob die Konfigurationsdatei existiert
    if (Test-Path $settingsFile) {
        try {
            $settings = Get-Content -Path $settingsFile -Raw | ConvertFrom-Json
        } catch {
            # Wenn die Datei nicht als JSON gelesen werden kann, neue Einstellungen erstellen
            $settings = [PSCustomObject]@{
                Logging = [PSCustomObject]@{
                    Enabled = $false
                    Path = "docs\logging"
                }
            }
        }
    } else {
        # Wenn die Datei nicht existiert, neue Einstellungen erstellen
        $settings = [PSCustomObject]@{
            Logging = [PSCustomObject]@{
                Enabled = $false
                Path = "docs\logging"
            }
        }
    }
    
    # Logging aktivieren
    $settings.Logging.Enabled = $true
    
    # Einstellungen speichern
    $settings | ConvertTo-Json -Depth 4 | Set-Content -Path $settingsFile
    
    # Logging-Verzeichnis erstellen, falls es nicht existiert
    $loggingPath = Join-Path -Path $rootPath -ChildPath $settings.Logging.Path
    if (-not (Test-Path $loggingPath)) {
        New-Item -ItemType Directory -Path $loggingPath -Force | Out-Null
        Write-Host "Logging-Verzeichnis erstellt: $loggingPath" -ForegroundColor Green
    }
    
    Write-Host "Logging wurde aktiviert." -ForegroundColor Green
}

# Funktion zum Deaktivieren des Loggings
function Disable-Logging {
    # Überprüfen, ob die Konfigurationsdatei existiert
    if (Test-Path $settingsFile) {
        try {
            $settings = Get-Content -Path $settingsFile -Raw | ConvertFrom-Json
            $settings.Logging.Enabled = $false
            $settings | ConvertTo-Json -Depth 4 | Set-Content -Path $settingsFile
            Write-Host "Logging wurde deaktiviert." -ForegroundColor Yellow
        } catch {
            Write-Host "Fehler beim Aktualisieren der Einstellungen: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Keine Konfigurationsdatei gefunden. Logging ist bereits deaktiviert." -ForegroundColor Yellow
    }
}

# Hauptmenü
function Show-Menu {
    Clear-Host
    Write-Host "+===============================================+"
    Write-Host "|                Logging-Manager               |"
    Write-Host "+===============================================+"
    Write-Host ""
    Show-LoggingStatus
    Write-Host ""
    Write-Host "   [1] Logging aktivieren"
    Write-Host "   [2] Logging deaktivieren"
    Write-Host "   [3] Zurück zum Hauptmenü"
    Write-Host ""
    
    $choice = Read-Host "Wähle eine Option"
    
    switch ($choice) {
        "1" {
            Enable-Logging
            Show-LoggingStatus
            Write-Host "`nDrücke eine Taste, um zum Menü zurückzukehren..."
            [Console]::ReadKey($true) | Out-Null
            Show-Menu
        }
        "2" {
            Disable-Logging
            Show-LoggingStatus
            Write-Host "`nDrücke eine Taste, um zum Menü zurückzukehren..."
            [Console]::ReadKey($true) | Out-Null
            Show-Menu
        }
        "3" {
            return
        }
        default {
            Write-Host "Ungültige Option. Bitte erneut versuchen." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Show-Menu
        }
    }
}

# Menü starten
Show-Menu