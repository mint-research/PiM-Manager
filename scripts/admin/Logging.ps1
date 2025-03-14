# Logging.ps1 - Script zum Aktivieren und Deaktivieren des Session-Loggings
# Speichert Einstellungen in config\settings.json

# Aktuelles Verzeichnis bestimmen (2 Ebenen nach oben vom scripts\admin Verzeichnis)
$rootPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path -Path $rootPath -ChildPath "config"
$settingsFile = Join-Path -Path $configPath -ChildPath "settings.json"

# UX-Modul importieren mit Fehlerbehandlung
$modulePath = Join-Path -Path $rootPath -ChildPath "modules\ux.psm1"

if (Test-Path -Path $modulePath) {
    try {
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Host "UX-Modul erfolgreich geladen." -ForegroundColor Green
    } catch {
        Write-Host "Fehler beim Laden des UX-Moduls: $_" -ForegroundColor Red
        # Fahre dennoch fort, aber ohne UX-Modul-Funktionen
    }
} else {
    Write-Host "UX-Modul konnte nicht gefunden werden: $modulePath" -ForegroundColor Red
    # Fahre dennoch fort, aber ohne UX-Modul-Funktionen
}

# Funktion zur Anzeige des aktuellen Logging-Status
function Show-LoggingStatus {
    # Überprüfen, ob die Konfigurationsdatei existiert
    if (Test-Path $settingsFile) {
        try {
            $settings = Get-Content -Path $settingsFile -Raw | ConvertFrom-Json
            
            if ($settings.Logging.Enabled) {
                $mode = $settings.Logging.Mode
                $status = if ($mode -eq "PowerShell") { "Aktiviert - PowerShell" } else { "Aktiviert - PiM-Manager" }
                $color = "Green"
            } else {
                $status = "Deaktiviert"
                $color = "Red"
            }
            
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

# Funktion zum Deaktivieren des Loggings
function Disable-Logging {
    # Überprüfen, ob die Konfigurationsdatei existiert
    if (Test-Path $settingsFile) {
        try {
            $settings = Get-Content -Path $settingsFile -Raw | ConvertFrom-Json
            $settings.Logging.Enabled = $false
            $settings | ConvertTo-Json -Depth 4 | Set-Content -Path $settingsFile
            Write-Host "Logging wurde deaktiviert." -ForegroundColor Yellow
            Write-Host "Die Änderung wird bei der nächsten Session wirksam." -ForegroundColor Cyan
        } catch {
            Write-Host "Fehler beim Aktualisieren der Einstellungen: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Keine Konfigurationsdatei gefunden. Logging ist bereits deaktiviert." -ForegroundColor Yellow
    }
}

# Funktion zum Aktivieren des Loggings für PiM-Manager
function Enable-PiMLogging {
    Enable-LoggingWithMode "PiM"
}

# Funktion zum Aktivieren des Loggings für PowerShell
function Enable-PowerShellLogging {
    Enable-LoggingWithMode "PowerShell"
}

# Hilfsfunktion zum Aktivieren des Loggings mit bestimmtem Modus
function Enable-LoggingWithMode {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Mode
    )
    
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
                    Path = "docs\logs"
                    Mode = "PiM"
                }
            }
        }
    } else {
        # Wenn die Datei nicht existiert, neue Einstellungen erstellen
        $settings = [PSCustomObject]@{
            Logging = [PSCustomObject]@{
                Enabled = $false
                Path = "docs\logs"
                Mode = "PiM"
            }
        }
    }
    
    # Logging aktivieren
    $settings.Logging.Enabled = $true
    
    # Überprüfen, ob der Mode-Parameter existiert, und wenn nicht, hinzufügen
    if (-not (Get-Member -InputObject $settings.Logging -Name "Mode" -MemberType Properties)) {
        # Wenn das Mode-Property nicht existiert, fügen wir es hinzu
        # PowerShell kann bestehende PSCustomObjects nicht direkt erweitern, also erstellen wir ein neues
        $newLogging = [PSCustomObject]@{
            Enabled = $settings.Logging.Enabled
            Path = $settings.Logging.Path
            Mode = $Mode
        }
        
        # Alte Logging-Eigenschaft entfernen und neue hinzufügen
        $settingsObj = $settings | ConvertTo-Json -Depth 4 | ConvertFrom-Json
        $settingsObj.Logging = $newLogging
        $settings = $settingsObj
    } else {
        # Wenn das Property existiert, können wir es direkt setzen
        $settings.Logging.Mode = $Mode
    }
    
    # Einstellungen speichern
    $settings | ConvertTo-Json -Depth 4 | Set-Content -Path $settingsFile
    
    # Logging-Verzeichnis erstellen, falls es nicht existiert
    $loggingPath = Join-Path -Path $rootPath -ChildPath $settings.Logging.Path
    if (-not (Test-Path $loggingPath)) {
        New-Item -ItemType Directory -Path $loggingPath -Force | Out-Null
        Write-Host "Logging-Verzeichnis erstellt: $loggingPath" -ForegroundColor Green
    }
    
    $modeDisplay = if ($Mode -eq "PowerShell") { "PowerShell" } else { "PiM-Manager" }
    Write-Host "Logging wurde aktiviert für: $modeDisplay" -ForegroundColor Green
    Write-Host "Die Änderung wird bei der nächsten Session wirksam." -ForegroundColor Cyan
}

# Hauptmenü mit neuer UX-Modul-Integration
function Show-LoggingMenu {
    # Prüfen, ob die erweiterte UX-Modul-Funktion verfügbar ist
    $useExtendedUX = Get-Command -Name Show-ScriptMenu -ErrorAction SilentlyContinue
    
    # Menüoptionen für beide Darstellungsarten
    $menuOptions = @{
        "1" = @{
            "Display" = "[option]    Logging deaktivieren"
            "Action" = { 
                Disable-Logging
                Show-LoggingStatus
                Write-Host "`nDrücke eine Taste, um zum Menü zurückzukehren..."
                [Console]::ReadKey($true) | Out-Null
                Show-LoggingMenu
            }
        }
        "2" = @{
            "Display" = "[option]    Logging aktivieren - PiM-Manager"
            "Action" = { 
                Enable-PiMLogging
                Show-LoggingStatus
                Write-Host "`nDrücke eine Taste, um zum Menü zurückzukehren..."
                [Console]::ReadKey($true) | Out-Null
                Show-LoggingMenu
            }
        }
        "3" = @{
            "Display" = "[option]    Logging aktivieren - PowerShell"
            "Action" = { 
                Enable-PowerShellLogging
                Show-LoggingStatus
                Write-Host "`nDrücke eine Taste, um zum Menü zurückzukehren..."
                [Console]::ReadKey($true) | Out-Null
                Show-LoggingMenu
            }
        }
    }

    if ($useExtendedUX) {
        # Nutze die neue erweiterte UX-Funktion
        $result = Show-ScriptMenu -title "Logging-Manager" -mode "Admin-Modus" -options $menuOptions -enableBack -enableExit
        
        # Zurück-Button wurde gedrückt
        if ($result -eq "B") {
            return
        }
        # Exit-Button wurde gedrückt
        elseif ($result -eq "X") {
            exit
        }
    } else {
        # Fallback zur alten Methode, nur mit modifizierter Anzeige
        Clear-Host
        
        # Versuche, zumindest die Titel-Funktion zu verwenden, wenn vorhanden
        if (Get-Command -Name Show-Title -ErrorAction SilentlyContinue) {
            Show-Title "Logging-Manager" "Admin-Modus"
        } else {
            Write-Host "+===============================================+"
            Write-Host "|                Logging-Manager               |"
            Write-Host "+===============================================+"
        }
        
        # Status anzeigen
        Show-LoggingStatus
        Write-Host ""
        
        # Menüoptionen anzeigen
        foreach ($key in ($menuOptions.Keys | Sort-Object)) {
            Write-Host "    $key       $($menuOptions[$key].Display)"
        }
        
        # Leerzeile vor Navigationsoptionen
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
        # Benutzereingabe
        Write-Host ""
        $choice = Read-Host "Wähle eine Option"
        
        if ($menuOptions.ContainsKey($choice)) {
            & $menuOptions[$choice].Action
        } elseif ($choice -match "^[Bb]$") {
            return
        } elseif ($choice -match "^[Xx]$") {
            exit
        } else {
            Write-Host "Ungültige Option. Bitte erneut versuchen." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Show-LoggingMenu
        }
    }
}

# Menü starten
Show-LoggingMenu