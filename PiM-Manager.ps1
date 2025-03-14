# PiM-Manager.ps1 - Hauptskript mit ausgelagerter UI-Funktionalität und Session-Logging
# Importiert das UX-Modul aus dem modules-Verzeichnis

# Funktion zum Initialisieren des Loggings
function Initialize-Logging {
    # Konfigurationspfade definieren
    $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config"
    $settingsFile = Join-Path -Path $configPath -ChildPath "settings.json"
    
    # Standardwerte
    $loggingEnabled = $false
    $loggingPath = "docs\logging"
    
    # Überprüfen, ob die Konfigurationsdatei existiert
    if (Test-Path $settingsFile) {
        try {
            $settings = Get-Content -Path $settingsFile -Raw | ConvertFrom-Json
            $loggingEnabled = $settings.Logging.Enabled
            $loggingPath = $settings.Logging.Path
        } catch {
            Write-Host "Fehler beim Lesen der Einstellungen: $_" -ForegroundColor Red
        }
    }
    
    # Wenn Logging aktiviert ist, Transcript starten
    if ($loggingEnabled) {
        $logDir = Join-Path -Path $PSScriptRoot -ChildPath $loggingPath
        
        # Logging-Verzeichnis erstellen, falls es nicht existiert
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        # Zeitstempel für den Dateinamen generieren
        $timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
        $logFile = Join-Path -Path $logDir -ChildPath "log-$timestamp.txt"
        
        # Transcript starten
        Start-Transcript -Path $logFile -Append
        Write-Host "Logging ist aktiviert. Session wird aufgezeichnet in: $logFile" -ForegroundColor Green
    }
    
    return $loggingEnabled
}

# UX-Modul importieren mit Fehlerbehandlung
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "modules\ux.psm1"

if (Test-Path -Path $modulePath) {
    try {
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Host "Modul erfolgreich geladen: $modulePath" -ForegroundColor Green
    } catch {
        Write-Host "Fehler beim Laden des Moduls: $_" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "Modul konnte nicht gefunden werden: $modulePath" -ForegroundColor Red
    Write-Host "Aktuelles Verzeichnis: $PSScriptRoot" -ForegroundColor Yellow
    Write-Host "Bitte stellen Sie sicher, dass der Ordner 'modules' existiert und das ux.psm1 Modul enthält." -ForegroundColor Yellow
    exit
}

# Funktion zum Starten des Menüsystems
function Start-Menu {
    # Standardpfade definieren und überprüfen
    $scriptsPath = Join-Path -Path $PSScriptRoot -ChildPath "scripts"
    $adminPath = Join-Path -Path $scriptsPath -ChildPath "admin"
    
    # Überprüfen, ob die Pfade existieren
    if (-not (Test-Path -Path $scriptsPath)) {
        Write-Host "Fehler: Verzeichnis 'scripts' nicht gefunden. Wird erstellt..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $scriptsPath -Force | Out-Null
    }
    
    if (-not (Test-Path -Path $adminPath)) {
        Write-Host "Fehler: Verzeichnis 'scripts\admin' nicht gefunden. Wird erstellt..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $adminPath -Force | Out-Null
    }
    
    $isAdmin = $false
    $pathStack = New-Object System.Collections.Stack
    $currentPath = $scriptsPath

    while ($true) {
        # Aktuellen Pfad entsprechend des Modus setzen
        if ($isAdmin -and $pathStack.Count -eq 0) {
            $currentPath = $adminPath
        } elseif (-not $isAdmin -and $pathStack.Count -eq 0) {
            $currentPath = $scriptsPath
        }

        # Prüfen, ob wir uns im Hauptmenü befinden
        $isRootMenu = $pathStack.Count -eq 0
        $parentPath = if (-not $isRootMenu) { $pathStack.Peek() } else { "" }

        # Menü anzeigen und Auswahl holen
        $menu = Show-Menu $currentPath $isRootMenu $parentPath
        $choice = Read-Host "`nWähle eine Option"

        # Benutzereingabe verarbeiten
        if ($choice -match "^[Xx]$") { 
            # Beenden
            break  
        }
        elseif ($choice -match "^[Mm]$") {
            # Modus wechseln
            $isAdmin = -not $isAdmin
            # Beim Moduswechsel zum Hauptmenü zurückkehren
            $pathStack.Clear()
            $currentPath = if ($isAdmin) { $adminPath } else { $scriptsPath }
            continue
        }
        elseif ($choice -match "^[Bb]$" -and -not $isRootMenu) {
            # Zurück zum übergeordneten Verzeichnis
            $currentPath = $pathStack.Pop()
            continue
        }
        elseif ($menu.ContainsKey([int]$choice)) {
            # Menüeintrag ausführen
            $item = $menu[[int]$choice]
            if (Test-Path $item -PathType Container) {
                # In Ordner navigieren
                Write-Host "Navigiere zu: $item" -ForegroundColor Yellow
                Start-Sleep -Seconds 1  # Eine kurze Pause für die Anzeige
                $pathStack.Push($currentPath)
                $currentPath = $item
            } 
            elseif ($item -match "\.ps1$") {
                # Skript ausführen
                Write-Host "Skript ausführen: $item" -ForegroundColor Yellow
                Start-Sleep -Seconds 1  # Eine kurze Pause für die Anzeige
                # Skript ausführen
                & $item
            }
        }
    }
}

# Initialisiere Logging
$loggingEnabled = Initialize-Logging

# Prüfe, ob die UX-Funktionen verfügbar sind
if (Get-Command -Name Show-Menu -ErrorAction SilentlyContinue) {
    Write-Host "PiM-Manager wird gestartet..." -ForegroundColor Green
    Start-Menu
} else {
    Write-Host "❌ Fehler: Die Funktion 'Show-Menu' wurde nicht gefunden. Bitte überprüfe das Modul 'modules\ux.psm1'." -ForegroundColor Red
}

# Wenn Logging aktiviert war, beende das Transcript
if ($loggingEnabled) {
    Write-Host "Logging wird beendet..." -ForegroundColor Yellow
    Stop-Transcript
}