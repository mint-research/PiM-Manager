# Template.ps1 - Skript-Vorlage für PiM-Manager (Tokenoptimiert)
# DisplayName: Mein Skript-Titel

<#
.SYNOPSIS
Kurzbeschreibung des Skripts.
#>

# Pfadberechnung nach Position
$pathsMod = "$PSScriptRoot\..\..\modules\paths.psm1"
if (Test-Path $pathsMod) {
    try { 
        Import-Module $pathsMod -Force -EA Stop 
        $p = GetPaths $PSScriptRoot
    } catch {
        # Fallback bei Modulladefehler
        $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $p = @{
            root = $root
            cfg = "$root\config"
            temp = "$root\temp"
            errMod = "$root\modules\error.psm1"
            uxMod = "$root\modules\ux.psm1"
            adminMod = "$root\modules\admin.psm1"
        }
    }
} else {
    # Fallback ohne Pfadmodul
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $p = @{
        root = $root
        cfg = "$root\config"
        temp = "$root\temp"
        errMod = "$root\modules\error.psm1"
        uxMod = "$root\modules\ux.psm1"
        adminMod = "$root\modules\admin.psm1"
    }
}

$logPath = "$p.temp\logs"

# Fehlermodul laden
if (Test-Path $p.errMod) {
    try { Import-Module $p.errMod -Force -EA Stop }
    catch { 
        Write-Host "Fehlermodul konnte nicht geladen werden: $_" -ForegroundColor Red 
    }
}

# UX-Modul laden
if (Test-Path $p.uxMod) {
    if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            Import-Module $p.uxMod -Force -EA Stop
        } -m "UX-Modul konnte nicht geladen werden" -t "Warning"
    } else {
        try { 
            Import-Module $p.uxMod -Force -EA Stop 
        } catch { 
            Write-Host "UX-Fehler: $_" -ForegroundColor Red 
        }
    }
}

# Admin-Modul laden und Administratorrechte prüfen
$useAdminMod = $false
$hasAdminRights = $false

if (Test-Path $p.adminMod) {
    if (Get-Command SafeOp -EA SilentlyContinue) {
        $useAdminMod = SafeOp {
            Import-Module $p.adminMod -Force -EA Stop
            return $true
        } -m "Admin-Modul konnte nicht geladen werden" -def $false
    } else {
        try {
            Import-Module $p.adminMod -Force -EA Stop
            $useAdminMod = $true
        } catch {
            Write-Host "Admin-Modul konnte nicht geladen werden: $_" -ForegroundColor Yellow
        }
    }
    
    # Administratorrechte prüfen falls Admin-Modul geladen wurde
    if ($useAdminMod -and (Get-Command IsAdmin -EA SilentlyContinue)) {
        $hasAdminRights = IsAdmin
        # Bei Admin-Skripten Rechte ggf. anfordern
        if (!$hasAdminRights -and $PSScriptRoot -match "\\admin\\") {
            if (Get-Command RequireAdmin -EA SilentlyContinue) {
                RequireAdmin -message "Dieses Skript erfordert Administratorrechte."
                # Nach RequireAdmin Aufruf nochmals prüfen
                $hasAdminRights = IsAdmin
            } else {
                Write-Host "Warnung: Dieses Skript erfordert Administratorrechte!" -ForegroundColor Yellow
            }
        }
    }
}

# Admin-Rechte prüfen (Legacy-Methode als Fallback)
function IsAdmin {
    # Neue Methode über Admin-Modul nutzen, falls verfügbar
    if ($useAdminMod -and (Get-Command IsAdmin -EA SilentlyContinue)) {
        return IsAdmin
    }
    
    # Legacy-Methode 1: Pfadbasierte Prüfung
    if ($PSScriptRoot -match "admin$") {
        return $true
    }
    
    # Legacy-Methode 2: Einfache .NET-Prüfung
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Host "Fehler bei Windows-Berechtigungsprüfung: $_" -ForegroundColor Red
        return $false
    }
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
    
    # Status-Text basierend auf Admin-Rechten
    $statusText = $hasAdminRights ? "Mit Admin-Rechten" : "Ohne Admin-Rechte"
    Write-Host "Ausführungsmodus: $statusText" -ForegroundColor Cyan
    
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
    
    # Admin-Rechte prüfen falls erforderlich
    if (!$hasAdminRights -and $useAdminMod -and (Get-Command RequireAdmin -EA SilentlyContinue)) {
        RequireAdmin -message "Diese Option erfordert Administratorrechte."
        # Nach RequireAdmin Aufruf nochmals prüfen
        $hasAdminRights = IsAdmin
    }
    
    # Status-Text basierend auf Admin-Rechten
    $statusText = $hasAdminRights ? "Mit Admin-Rechten" : "Ohne Admin-Rechte"
    Write-Host "Ausführungsmodus: $statusText" -ForegroundColor Cyan
    
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
    $cfgFile = "$p.cfg\meinConfig.json"
    
    # Prüfen/Erstellen
    if (!(Test-Path $cfgFile)) {
        $def = @{
            Setting1 = "Wert1"
            Setting2 = $true
            Setting3 = 42
        }
        
        # Verzeichnis prüfen
        if (!(Test-Path $p.cfg)) {
            md $p.cfg -Force >$null
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
    # Status-Text basierend auf Admin-Rechten
    $statusText = $hasAdminRights ? "Admin-Modus" : "Eingeschränkter Modus"
    
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
        $r = SMenu -t "Untermenü" -m $statusText -opts $opts -back -exit
        
        # Die SMenu-Funktion beendet den Prozess bereits bei X
        # Wir müssen hier nur das Ergebnis B abfangen
        if ($r -eq "B") {
            Menu
        }
    } else {
        # Einfaches Menü
        cls
        
        if (Get-Command Title -EA SilentlyContinue) {
            Title "Untermenü" $statusText
        } else {
            Write-Host "+===============================================+"
            Write-Host "|                Untermenü                     |"
            Write-Host "|         ($statusText)        |"
            Write-Host "+===============================================+"
        }
        
        # Adminrechte-Warnung anzeigen
        if (!$hasAdminRights) {
            Write-Host "`nHinweis: Keine Administratorrechte. Einige Funktionen könnten eingeschränkt sein." -ForegroundColor Yellow
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
    
    # Status-Text basierend auf Admin-Rechten
    $statusText = $hasAdminRights ? "Admin-Modus" : "Eingeschränkter Modus"
    
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
        $r = SMenu -t "Mein Skript-Titel" -m $statusText -opts $opts -back -exit
        
        if ($r -eq "B") {
            return
        }
    } else {
        # Fallback-Menü
        cls
        Write-Host "+===============================================+"
        Write-Host "|             Mein Skript-Titel                |"
        Write-Host "|         ($statusText)        |"
        Write-Host "+===============================================+"
        
        # Adminrechte-Warnung anzeigen
        if (!$hasAdminRights) {
            Write-Host "`nHinweis: Keine Administratorrechte. Einige Funktionen könnten eingeschränkt sein." -ForegroundColor Yellow
        }
        
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

# Admin-Rechte anzeigen
if ($useAdminMod -and (Get-Command IsAdmin -EA SilentlyContinue)) {
    $adminStatus = $hasAdminRights ? "Ja" : "Nein"
    Log "Admin-Rechte: $adminStatus" ($hasAdminRights ? "Information" : "Warning")
}

Menu
Log "Skript beendet" -t "Information"