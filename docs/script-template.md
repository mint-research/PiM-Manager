# Template.ps1 - Skript-Vorlage für PiM-Manager (Tokenoptimiert)
# Pfad: scripts\admin\ oder scripts\
# Version: 1.0
# DisplayName: Mein Skript-Titel

<#
.SYNOPSIS
Kurzbeschreibung des Skripts.

.DESCRIPTION
Ausführliche Funktionsbeschreibung.

.NOTES
Datum: DATUM
Autor: AUTOR
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
        Write-Host "UX-Modulfehler: $_" -ForegroundColor Red
    }
} else {
    Write-Host "UX-Modul nicht gefunden: $modPath" -ForegroundColor Red
}

# Admin-Rechte prüfen
function CheckAdmin {
    if ($isAdmin) {
        # Berechtigungsprüfungen hier einfügen
        return $true
    }
    return $true  # Für normale Skripte immer true
}

# Log-Funktion
function Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$msg,
        
        [ValidateSet("Information", "Warning", "Error")]
        [string]$type = "Information"
    )
    
    # Zeitstempel
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $script = Split-Path -Leaf $PSCommandPath
    
    # Log formatieren
    $logLine = "[$ts] [$script] [$type] $msg"
    
    # Ausgabe (außer Information)
    if ($type -ne "Information") {
        $color = $type -eq "Error" ? "Red" : "Yellow"
        Write-Host $logLine -ForegroundColor $color
    } else {
        Write-Verbose $logLine
    }
    
    # Hier könnte Datei-Logging implementiert werden
}

#########################################
# FUNKTIONEN
#########################################

# Option 1
function Option1 {
    Log "Option 1 ausgewählt"
    Write-Host "Option 1 wird ausgeführt..." -ForegroundColor Cyan
    
    # Eigene Logik implementieren
    
    # Pause danach
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    ShowMainMenu
}

# Option 2
function Option2 {
    Log "Option 2 ausgewählt"
    Write-Host "Option 2 wird ausgeführt..." -ForegroundColor Cyan
    
    # Eigene Logik implementieren
    
    # Pause danach
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    ShowMainMenu
}

# Option 3
function Option3 {
    Log "Option 3 ausgewählt"
    Write-Host "Option 3 wird ausgeführt..." -ForegroundColor Cyan
    
    # Konfigdatei-Beispiel
    $cfgFile = "$cfgPath\meinConfig.json"
    
    # Prüfen/Erstellen
    if (-not (Test-Path $cfgFile)) {
        $defCfg = @{
            Setting1 = "Wert1"
            Setting2 = $true
            Setting3 = 42
        }
        
        # Verzeichnis prüfen
        if (-not (Test-Path $cfgPath)) {
            mkdir $cfgPath -Force >$null
        }
        
        # Speichern
        $defCfg | ConvertTo-Json -Depth 4 | Set-Content $cfgFile
        Write-Host "Konfiguration erstellt: $cfgFile" -ForegroundColor Green
    } else {
        # Lesen
        try {
            $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
            Write-Host "Aktuelle Konfiguration:" -ForegroundColor Cyan
            $cfg | Format-Table | Out-Host
        } catch {
            Log "Lesefehler: $_" -type "Error"
        }
    }
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    ShowMainMenu
}

# Untermenü
function ShowSubMenu {
    # UX-Funktion prüfen
    $hasUX = Get-Command ShowScriptMenu -EA SilentlyContinue
    
    # Untermenü-Optionen
    $subOpts = @{
        "1" = @{
            Display = "[option]    Unteroption 1"
            Action = { 
                Log "Unteroption 1 ausgewählt"
                Write-Host "Unteroption 1 wird ausgeführt..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                ShowSubMenu 
            }
        }
        "2" = @{
            Display = "[option]    Unteroption 2"
            Action = { 
                Log "Unteroption 2 ausgewählt"
                Write-Host "Unteroption 2 wird ausgeführt..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                ShowSubMenu 
            }
        }
    }
    
    if ($hasUX) {
        # UX-Funktion nutzen
        $result = ShowScriptMenu -title "Untermenü" -mode ($isAdmin ? "Admin-Modus" : "User-Modus") -options $subOpts -enableBack -enableExit
        
        # Die ShowScriptMenu-Funktion beendet den Prozess bereits bei X
        # Wir müssen hier nur das Ergebnis B abfangen
        if ($result -eq "B") {
            ShowMainMenu
        }
    } else {
        # Einfaches Menü
        cls
        
        if (Get-Command ShowTitle -EA SilentlyContinue) {
            ShowTitle "Untermenü" ($isAdmin ? "Admin-Modus" : "User-Modus")
        } else {
            Write-Host "+===============================================+"
            Write-Host "|                Untermenü                     |"
            Write-Host "|         $($isAdmin ? '(Admin-Modus)' : '(User-Modus)')        |"
            Write-Host "+===============================================+"
        }
        
        # Optionen
        foreach ($key in ($subOpts.Keys | Sort-Object)) {
            Write-Host "    $key       $($subOpts[$key].Display)"
        }
        
        # Navigation
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
        # Eingabe
        Write-Host ""
        $choice = Read-Host "Option wählen"
        
        if ($choice -match "^[Xx]$") {
            Write-Host "PiM-Manager wird beendet..." -ForegroundColor Yellow
            exit
        } elseif ($choice -match "^[Bb]$") {
            ShowMainMenu
        } elseif ($subOpts.ContainsKey($choice)) {
            & $subOpts