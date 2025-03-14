# PiM-Manager.ps1 - Hauptskript mit UI-Modul und Session-Logging (Tokenoptimiert)

# Pfade definieren
$cfgPath = "$PSScriptRoot\config"
$cfgFile = "$cfgPath\settings.json"
$tempPath = "$PSScriptRoot\temp"

# Erstinitialisierung prüfen
if (!(Test-Path $cfgFile)) {
    Write-Host "Erststart erkannt. Konfiguration wird initialisiert..." -ForegroundColor Yellow
    $initScript = "$cfgPath\Initialize-DefaultSettings.ps1"
    if (Test-Path $initScript) {
        & $initScript
    } else {
        Write-Host "Initialisierungsskript nicht gefunden: $initScript" -ForegroundColor Red
        # Einfache Standardkonfiguration
        if (!(Test-Path $cfgPath)) { md $cfgPath -Force >$null }
        @{
            Logging = @{
                Enabled = $false
                Path = "temp\logs"
                Mode = "PiM"
            }
        } | ConvertTo-Json -Depth 4 | Set-Content $cfgFile
        Write-Host "Standardkonfiguration erstellt." -ForegroundColor Green
    }
}

# Temp-Verzeichnis prüfen/erstellen
if (!(Test-Path $tempPath)) {
    md $tempPath -Force >$null
    Write-Host "Temp-Verzeichnis erstellt: $tempPath" -ForegroundColor Green
}

# Logging initialisieren
function ILog {
    # Standardwerte
    $en = $false
    $p = "temp\logs"
    $m = "PiM"
    
    # Konfiguration laden
    if (Test-Path $cfgFile) {
        try {
            $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
            $en = $cfg.Logging.Enabled
            $p = $cfg.Logging.Path
            
            # Mode-Parameter prüfen
            if (Get-Member -InputObject $cfg.Logging -Name "Mode" -MemberType Properties) {
                $m = $cfg.Logging.Mode
            }
        } catch {
            Write-Host "Fehler beim Lesen: $_" -ForegroundColor Red
        }
    }
    
    # Logging starten wenn aktiviert
    if ($en) {
        $logDir = "$PSScriptRoot\$p"
        
        # Verzeichnis erstellen
        if (!(Test-Path $logDir)) { md $logDir -Force >$null }
        
        # Dateiname mit Zeitstempel
        $ts = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
        $sfx = $m -eq "PowerShell" ? "psh" : "pim"
        $logFile = "$logDir\log-$ts-$sfx.txt"
        
        # Transcript starten
        Start-Transcript -Path $logFile -Append
        
        $mText = $m -eq "PowerShell" ? "PowerShell" : "PiM-Manager"
        Write-Host "Logging aktiviert für: $mText" -ForegroundColor Green
        Write-Host "Session wird aufgezeichnet: $logFile" -ForegroundColor Green
    }
    
    # Logging-Info zurückgeben
    return [PSCustomObject]@{
        Enabled = $en
        Mode = $m
    }
}

# UX-Modul laden
$modPath = "$PSScriptRoot\modules\ux.psm1"

if (Test-Path $modPath) {
    try {
        Import-Module $modPath -Force -EA Stop
        Write-Host "Modul geladen: $modPath" -ForegroundColor Green
    } catch {
        Write-Host "Modulfehler: $_" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "Modul nicht gefunden: $modPath" -ForegroundColor Red
    Write-Host "Verzeichnis: $PSScriptRoot" -ForegroundColor Yellow
    Write-Host "Stellen Sie sicher, dass 'modules\ux.psm1' existiert." -ForegroundColor Yellow
    exit
}

# Menüsystem starten
function Menu {
    # Pfade definieren
    $sPath = "$PSScriptRoot\scripts"
    $aPath = "$sPath\admin"
    
    # Verzeichnisse prüfen/erstellen
    if (!(Test-Path $sPath)) {
        Write-Host "Verzeichnis 'scripts' nicht gefunden. Wird erstellt..." -ForegroundColor Yellow
        md $sPath -Force >$null
    }
    
    if (!(Test-Path $aPath)) {
        Write-Host "Verzeichnis 'scripts\admin' nicht gefunden. Wird erstellt..." -ForegroundColor Yellow
        md $aPath -Force >$null
    }
    
    $isAdmin = $false
    $pStack = New-Object System.Collections.Stack
    $curPath = $sPath

    while ($true) {
        # Pfad nach Modus setzen
        if ($isAdmin -and $pStack.Count -eq 0) {
            $curPath = $aPath
        } elseif (!$isAdmin -and $pStack.Count -eq 0) {
            $curPath = $sPath
        }

        # Hauptmenü-Check
        $isRoot = $pStack.Count -eq 0
        $parent = if (!$isRoot) { $pStack.Peek() } else { "" }

        # Menü anzeigen
        $menu = ShowMenu $curPath $isRoot $parent
        $ch = Read-Host "`nOption wählen"

        # Eingabe verarbeiten
        if ($ch -match "^[Xx]$") { 
            # Beenden
            break  
        }
        elseif ($ch -match "^[Mm]$") {
            # Modus wechseln
            $isAdmin = !$isAdmin
            $pStack.Clear()
            $curPath = $isAdmin ? $aPath : $sPath
        }
        elseif ($ch -match "^[Bb]$" -and !$isRoot) {
            # Zurück
            $curPath = $pStack.Pop()
        }
        elseif ($menu.ContainsKey([int]$ch)) {
            # Menüeintrag
            $item = $menu[[int]$ch]
            if (Test-Path $item -PathType Container) {
                # In Ordner navigieren
                Write-Host "Navigiere zu: $item" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                $pStack.Push($curPath)
                $curPath = $item
            } 
            elseif ($item -match "\.ps1$") {
                # Skript ausführen
                Write-Host "Ausführen: $item" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                & $item
            }
        }
    }
}

# Logging initialisieren
$logInfo = ILog
$logEnabled = $logInfo.Enabled
$logMode = $logInfo.Mode

# UX-Funktionen prüfen und starten
if (Get-Command ShowMenu -EA SilentlyContinue) {
    Write-Host "PiM-Manager wird gestartet..." -ForegroundColor Green
    Menu
} else {
    Write-Host "❌ Fehler: Funktion 'ShowMenu' nicht gefunden. Prüfe 'modules\ux.psm1'." -ForegroundColor Red
}

# Logging beenden
if ($logEnabled) {
    Write-Host "Logging wird beendet..." -ForegroundColor Yellow
    Stop-Transcript
}