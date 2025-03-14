# Template.ps1 - Template für neue Skripte im PiM-Manager
# Speicherort: scripts\admin\ oder scripts\
# Dateinamenkonvention: BeschreibenderName.ps1 (keine Leerzeichen, PascalCase)
# Version: 1.0

<#
.SYNOPSIS
Kurze Beschreibung des Skripts.

.DESCRIPTION
Ausführliche Beschreibung der Funktionalität.

.NOTES
Erstellt: DATUM
Autor: AUTOR
#>

# Pfadberechnungen
# Wichtig: Korrekte Pfadberechnung je nach Speicherort
if ($PSScriptRoot -match "admin$") {
    # Skript ist im Admin-Ordner
    $rootPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $isAdminScript = $true
} else {
    # Skript ist im normalen scripts-Ordner
    $rootPath = Split-Path -Parent $PSScriptRoot
    $isAdminScript = $false
}

$configPath = Join-Path -Path $rootPath -ChildPath "config"
$logsPath = Join-Path -Path $rootPath -ChildPath "docs\logs"

# UX-Modul importieren mit Fehlerbehandlung
$modulePath = Join-Path -Path $rootPath -ChildPath "modules\ux.psm1"

if (Test-Path -Path $modulePath) {
    try {
        Import-Module $modulePath -Force -ErrorAction Stop
        # Erfolgsmeldung nur im Verbose-Modus anzeigen
        Write-Verbose "UX-Modul erfolgreich geladen: $modulePath"
    } catch {
        Write-Host "Fehler beim Laden des UX-Moduls: $_" -ForegroundColor Red
        # Script dennoch fortsetzen, aber ohne UX-Funktionen
    }
} else {
    Write-Host "UX-Modul konnte nicht gefunden werden: $modulePath" -ForegroundColor Red
}

# Funktion zum Prüfen von Berechtigungen bei Admin-Skripts
function Test-AdminRequirements {
    if ($isAdminScript) {
        # Hier könnten zusätzliche Berechtigungsprüfungen hinzugefügt werden
        # z.B. Prüfen, ob der Benutzer bestimmte Rechte hat
        return $true
    }
    return $true  # Für normale Scripts immer true
}

# Funktion zum Schreiben in das Logfile (falls benötigt)
function Write-CustomLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Severity = "Information"
    )
    
    # Zeitstempel
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $scriptName = Split-Path -Leaf $PSCommandPath
    
    # Logzeile formatieren
    $logLine = "[$timestamp] [$scriptName] [$Severity] $Message"
    
    # Nur zur Konsole ausgeben, wenn es kein Information-Typ ist
    if ($Severity -ne "Information") {
        $color = if ($Severity -eq "Error") { "Red" } else { "Yellow" }
        Write-Host $logLine -ForegroundColor $color
    } else {
        Write-Verbose $logLine
    }
    
    # Hier könnte auch ein Schreiben in eine separate Log-Datei implementiert werden
}

#########################################
# FUNKTIONEN - HIER EIGENE LOGIK EINFÜGEN
#########################################

# Beispielfunktion für Option 1
function Invoke-Option1 {
    Write-CustomLog "Option 1 wurde ausgewählt"
    Write-Host "Option 1 wird ausgeführt..." -ForegroundColor Cyan
    
    # Hier eigene Logik implementieren
    
    # Beispiel für eine Pause nach der Ausführung
    Write-Host "`nDrücke eine Taste, um zum Menü zurückzukehren..."
    [Console]::ReadKey($true) | Out-Null
    Show-MainMenu
}

# Beispielfunktion für Option 2
function Invoke-Option2 {
    Write-CustomLog "Option 2 wurde ausgewählt"
    Write-Host "Option 2 wird ausgeführt..." -ForegroundColor Cyan
    
    # Hier eigene Logik implementieren
    
    # Beispiel für eine Pause nach der Ausführung
    Write-Host "`nDrücke eine Taste, um zum Menü zurückzukehren..."
    [Console]::ReadKey($true) | Out-Null
    Show-MainMenu
}

# Beispielfunktion für Option 3
function Invoke-Option3 {
    Write-CustomLog "Option 3 wurde ausgewählt"
    Write-Host "Option 3 wird ausgeführt..." -ForegroundColor Cyan
    
    # Beispiel für Konfigurationsdatei-Manipulation
    $configFile = Join-Path -Path $configPath -ChildPath "meinConfig.json"
    
    # Überprüfen, ob Konfiguration existiert, sonst erstellen
    if (-not (Test-Path -Path $configFile)) {
        $defaultConfig = @{
            Setting1 = "Wert1"
            Setting2 = $true
            Setting3 = 42
        }
        
        # Sicherstellen, dass das Verzeichnis existiert
        if (-not (Test-Path -Path $configPath)) {
            New-Item -ItemType Directory -Path $configPath -Force | Out-Null
        }
        
        # Konfiguration speichern
        $defaultConfig | ConvertTo-Json -Depth 4 | Set-Content -Path $configFile
        Write-Host "Konfigurationsdatei wurde erstellt: $configFile" -ForegroundColor Green
    } else {
        # Konfiguration lesen
        try {
            $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            Write-Host "Aktuelle Konfiguration:" -ForegroundColor Cyan
            $config | Format-Table | Out-Host
        } catch {
            Write-CustomLog "Fehler beim Lesen der Konfiguration: $_" -Severity "Error"
        }
    }
    
    # Beispiel für eine Pause nach der Ausführung
    Write-Host "`nDrücke eine Taste, um zum Menü zurückzukehren..."
    [Console]::ReadKey($true) | Out-Null
    Show-MainMenu
}

# Beispiel für ein Untermenü
function Show-SubMenu {
    # Prüfen, ob die erweiterte UX-Modul-Funktion verfügbar ist
    $useExtendedUX = Get-Command -Name Show-ScriptMenu -ErrorAction SilentlyContinue
    
    # Untermenü-Optionen definieren
    $subOptions = @{
        "1" = @{
            "Display" = "[option]    Unteroption 1"
            "Action" = { 
                Write-CustomLog "Unteroption 1 wurde ausgewählt"
                Write-Host "Unteroption 1 wird ausgeführt..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                Show-SubMenu 
            }
        }
        "2" = @{
            "Display" = "[option]    Unteroption 2"
            "Action" = { 
                Write-CustomLog "Unteroption 2 wurde ausgewählt"
                Write-Host "Unteroption 2 wird ausgeführt..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                Show-SubMenu 
            }
        }
    }
    
    if ($useExtendedUX) {
        # Nutze die erweiterte UX-Funktion
        $result = Show-ScriptMenu -title "Untermenü" -mode "Admin-Modus" -options $subOptions -enableBack -enableExit
        
        # Zurück-Button wurde gedrückt
        if ($result -eq "B") {
            Show-MainMenu
        }
        # Exit-Button wurde gedrückt
        elseif ($result -eq "X") {
            exit
        }
    } else {
        # Fallback zur einfachen Menüdarstellung
        Clear-Host
        
        # Versuche, zumindest die Titel-Funktion zu verwenden, wenn vorhanden
        if (Get-Command -Name Show-Title -ErrorAction SilentlyContinue) {
            Show-Title "Untermenü" ($isAdminScript ? "Admin-Modus" : "User-Modus")
        } else {
            Write-Host "+===============================================+"
            Write-Host "|                Untermenü                     |"
            Write-Host "|         $($isAdminScript ? '(Admin-Modus)' : '(User-Modus)')        |"
            Write-Host "+===============================================+"
        }
        
        # Menüoptionen anzeigen
        foreach ($key in ($subOptions.Keys | Sort-Object)) {
            Write-Host "    $key       $($subOptions[$key].Display)"
        }
        
        # Leerzeile vor Navigationsoptionen
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
        # Benutzereingabe
        Write-Host ""
        $choice = Read-Host "Wähle eine Option"
        
        if ($subOptions.ContainsKey($choice)) {
            & $subOptions[$choice].Action
        } elseif ($choice -match "^[Bb]$") {
            Show-MainMenu
        } elseif ($choice -match "^[Xx]$") {
            exit
        } else {
            Write-Host "Ungültige Option. Bitte erneut versuchen." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Show-SubMenu
        }
    }
}

#########################################
# HAUPTMENÜ
#########################################

# Funktion für das Hauptmenü
function Show-MainMenu {
    # Prüfen, ob die erweiterte UX-Modul-Funktion verfügbar ist
    $useExtendedUX = Get-Command -Name Show-ScriptMenu -ErrorAction SilentlyContinue
    
    # Titel für das Skript - ANPASSEN!
    $scriptTitle = "Template-Skript"
    
    # Aktuellen Modus bestimmen
    $currentMode = if ($isAdminScript) { "Admin-Modus" } else { "User-Modus" }
    
    # Menüoptionen für beide Darstellungsarten
    $menuOptions = @{
        "1" = @{
            "Display" = "[option]    Option 1 Beschreibung"
            "Action" = { Invoke-Option1 }
        }
        "2" = @{
            "Display" = "[option]    Option 2 Beschreibung"
            "Action" = { Invoke-Option2 }
        }
        "3" = @{
            "Display" = "[option]    Option 3 mit Konfiguration"
            "Action" = { Invoke-Option3 }
        }
        "4" = @{
            "Display" = "[option]    Untermenü anzeigen"
            "Action" = { Show-SubMenu }
        }
    }

    if ($useExtendedUX) {
        # Nutze die neue erweiterte UX-Funktion
        $result = Show-ScriptMenu -title $scriptTitle -mode $currentMode -options $menuOptions -enableBack -enableExit
        
        # Zurück-Button wurde gedrückt
        if ($result -eq "B") {
            return
        }
        # Exit-Button wurde gedrückt
        elseif ($result -eq "X") {
            exit
        }
    } else {
        # Fallback zur einfachen Menüdarstellung
        Clear-Host
        
        # Versuche, zumindest die Titel-Funktion zu verwenden, wenn vorhanden
        if (Get-Command -Name Show-Title -ErrorAction SilentlyContinue) {
            Show-Title $scriptTitle $currentMode
        } else {
            Write-Host "+===============================================+"
            Write-Host "|             $scriptTitle                      |"
            Write-Host "|             ($currentMode)                    |"
            Write-Host "+===============================================+"
        }
        
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
            Show-MainMenu
        }
    }
}

#########################################
# SCRIPT-START
#########################################

# Überprüfen, ob alle Anforderungen erfüllt sind (für Admin-Skripte)
if (-not (Test-AdminRequirements)) {
    Write-CustomLog "Erforderliche Berechtigungen fehlen. Das Skript wird beendet." -Severity "Error"
    exit
}

# Skript-Information ausgeben
$scriptName = Split-Path -Leaf $PSCommandPath
Write-CustomLog "Skript wird gestartet: $scriptName" -Severity "Information"

# Hauptmenü starten
Show-MainMenu

# Skript-Ende
Write-CustomLog "Skript wurde beendet: $scriptName" -Severity "Information"