# Template.ps1 - Skript-Vorlage für PiM-Manager (Tokenoptimiert)
# DisplayName: Mein Skript-Titel

<#
.SYNOPSIS
Kurzbeschreibung des Skripts.
#>

# Pfadberechnung nach Position
if ($PSScriptRoot -match "admin$") {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $isAdmin = $true
} else {
    $root = Split-Path -Parent $PSScriptRoot
    $isAdmin = $false
}

$cfgPath = "$root\config"
$tempPath = "$root\temp"
$logPath = "$tempPath\logs"

# UX-Modul laden
$modPath = "$root\modules\ux.psm1"

if (Test-Path $modPath) {
    try { 
        Import-Module $modPath -Force -EA Stop 
        Write-Verbose "UX-Modul geladen: $modPath"
    } catch {
        Write-Host "UX-Fehler: $_" -ForegroundColor Red
    }
} else {
    Write-Host "UX-Modul nicht gefunden: $modPath" -ForegroundColor Red
}

# Admin-Rechte prüfen
function IsAdmin {
    if ($isAdmin) {
        # Berechtigungsprüfungen hier einfügen
        return $true
    }
    return $true  # Für normale Skripte immer true
}

# Log-Funktion
function Log {
    param (
        [Parameter(Mandatory)]
        [string]$m,
        
        [ValidateSet("Information", "Warning", "Error")]
        [string]$t = "Information"
    )
    
    # Zeitstempel
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $s = Split-Path -Leaf $PSCommandPath
    
    # Log formatieren
    $l = "[$ts] [$s] [$t] $m"
    
    # Ausgabe (außer Information)
    if ($t -ne "Information") {
        $c = $t -eq "Error" ? "Red" : "Yellow"
        Write-Host $l -ForegroundColor $c
    } else {
        Write-Verbose $l
    }
    
    # Hier könnte Datei-Logging implementiert werden
}

#########################################
# FUNKTIONEN
#########################################

# Option 1
function Opt1 {
    Log "Option 1 ausgewählt"
    Write-Host "Option 1 wird ausgeführt..." -ForegroundColor Cyan
    
    # Eigene Logik implementieren
    
    # Pause danach
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    Menu
}

# Option 2
function Opt2 {
    Log "Option 2 ausgewählt"
    Write-Host "Option 2 wird ausgeführt..." -ForegroundColor Cyan
    
    # Eigene Logik implementieren
    
    # Pause danach
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    Menu
}

# Option 3
function Opt3 {
    Log "Option 3 ausgewählt"
    Write-Host "Option 3 wird ausgeführt..." -ForegroundColor Cyan
    
    # Konfigdatei-Beispiel
    $cfgFile = "$cfgPath\meinConfig.json"
    
    # Prüfen/Erstellen
    if (!(Test-Path $cfgFile)) {
        $def = @{
            Setting1 = "Wert1"
            Setting2 = $true
            Setting3 = 42
        }
        
        # Verzeichnis prüfen
        if (!(Test-Path $cfgPath)) {
            md $cfgPath -Force >$null
        }
        
        # Speichern
        $def | ConvertTo-Json -Depth 4 | Set-Content $cfgFile
        Write-Host "Konfiguration erstellt: $cfgFile" -ForegroundColor Green
    } else {
        # Lesen
        try {
            $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
            Write-Host "Aktuelle Konfiguration:" -ForegroundColor Cyan
            $cfg | Format-Table | Out-Host
        } catch {
            Log "Lesefehler: $_" -t "Error"
        }
    }
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    Menu
}

# Untermenü
function SubMenu {
    # UX-Funktion prüfen
    $hasUX = Get-Command SMenu -EA SilentlyContinue
    
    # Untermenü-Optionen
    $opts = @{
        "1" = @{
            Display = "[option]    Unteroption 1"
            Action = { 
                Log "Unteroption 1 ausgewählt"
                Write-Host "Unteroption 1 wird ausgeführt..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                SubMenu 
            }
        }
        "2" = @{
            Display = "[option]    Unteroption 2"
            Action = { 
                Log "Unteroption 2 ausgewählt"
                Write-Host "Unteroption 2 wird ausgeführt..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                SubMenu 
            }
        }
    }
    
    if ($hasUX) {
        # UX-Funktion nutzen
        $r = SMenu -t "Untermenü" -m ($isAdmin ? "Admin-Modus" : "User-Modus") -opts $opts -back -exit
        
        # Die SMenu-Funktion beendet den Prozess bereits bei X
        # Wir müssen hier nur das Ergebnis B abfangen
        if ($r -eq "B") {
            Menu
        }
    } else {
        # Einfaches Menü
        cls
        
        if (Get-Command Title -EA SilentlyContinue) {
            Title "Untermenü" ($isAdmin ? "Admin-Modus" : "User-Modus")
        } else {
            Write-Host "+===============================================+"
            Write-Host "|                Untermenü                     |"
            Write-Host "|         $($isAdmin ? '(Admin-Modus)' : '(User-Modus)')        |"
            Write-Host "+===============================================+"
        }
        
        # Optionen
        foreach ($k in ($opts.Keys | Sort)) {
            Write-Host "    $k       $($opts[$k].Display)"
        }
        
        # Navigation
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
        # Eingabe
        Write-Host ""
        $ch = Read-Host "Option wählen"
        
        if ($ch -match "^[Xx]$") {
            Write-Host "PiM-Manager wird beendet..." -ForegroundColor Yellow
            exit
        } elseif ($ch -match "^[Bb]$") {
            Menu
        } elseif ($opts.ContainsKey($ch)) {
            & $opts[$ch].Action
        } else {
            Write-Host "Ungültige Option." -ForegroundColor Red
            Start-Sleep -Seconds 2
            SubMenu
        }
    }
}

# Hauptmenü
function Menu {
    # UX-Funktion prüfen
    $hasUX = Get-Command SMenu -EA SilentlyContinue
    
    # Menüoptionen
    $opts = @{
        "1" = @{
            Display = "[option]    Option 1"
            Action = { Opt1 }
        }
        "2" = @{
            Display = "[option]    Option 2"
            Action = { Opt2 }
        }
        "3" = @{
            Display = "[option]    Option 3 (Konfiguration)"
            Action = { Opt3 }
        }
        "4" = @{
            Display = "[option]    Untermenü"
            Action = { SubMenu }
        }
    }
    
    if ($hasUX) {
        # UX-Modul nutzen
        $r = SMenu -t "Mein Skript-Titel" -m ($isAdmin ? "Admin-Modus" : "User-Modus") -opts $opts -back -exit
        
        if ($r -eq "B") {
            return
        }
    } else {
        # Fallback-Menü
        cls
        Write-Host "+===============================================+"
        Write-Host "|             Mein Skript-Titel                |"
        Write-Host "|         $($isAdmin ? '(Admin-Modus)' : '(User-Modus)')        |"
        Write-Host "+===============================================+"
        
        # Optionen anzeigen
        foreach ($k in ($opts.Keys | Sort)) {
            Write-Host "    $k       $($opts[$k].Display)"
        }
        
        # Navigation
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
        # Eingabe
        Write-Host ""
        $ch = Read-Host "Option wählen"
        
        if ($ch -match "^[Xx]$") {
            Write-Host "PiM-Manager wird beendet..." -ForegroundColor Yellow
            exit
        } elseif ($ch -match "^[Bb]$") {
            return
        } elseif ($opts.ContainsKey($ch)) {
            & $opts[$ch].Action
        } else {
            Write-Host "Ungültige Option." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Menu
        }
    }
}

# Skriptstart
Log "Skript gestartet" -t "Information"
Menu
Log "Skript beendet" -t "Information"