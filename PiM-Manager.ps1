# PiM-Manager.ps1 - Hauptskript mit UI-Modul und Session-Logging (Tokenoptimiert)

# Pfade definieren
$cfgPath = "$PSScriptRoot\config"
$cfgFile = "$cfgPath\settings.json"

# Erstinitialisierung prüfen
if (-not (Test-Path $cfgFile)) {
    Write-Host "Erststart erkannt. Konfiguration wird initialisiert..." -ForegroundColor Yellow
    $initScript = "$cfgPath\Initialize-DefaultSettings.ps1"
    if (Test-Path $initScript) {
        & $initScript
    } else {
        Write-Host "Initialisierungsskript nicht gefunden: $initScript" -ForegroundColor Red
        # Einfache Standardkonfiguration
        if (-not (Test-Path $cfgPath)) { mkdir $cfgPath -Force >$null }
        @{
            Logging = @{
                Enabled = $false
                Path = "docs\logs"
                Mode = "PiM"
            }
        } | ConvertTo-Json -Depth 4 | Set-Content $cfgFile
        Write-Host "Standardkonfiguration erstellt." -ForegroundColor Green
    }
}

# Logging initialisieren
function InitLog {
    # Standardwerte
    $enabled = $false
    $path = "docs\logs"
    $mode = "PiM"
    
    # Konfiguration laden
    if (Test-Path $cfgFile) {
        try {
            $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
            $enabled = $cfg.Logging.Enabled
            $path = $cfg.Logging.Path
            
            # Mode-Parameter prüfen
            if (Get-Member -InputObject $cfg.Logging -Name "Mode" -MemberType Properties) {
                $mode = $cfg.Logging.Mode
            }
        } catch {
            Write-Host "Fehler beim Lesen: $_" -ForegroundColor Red
        }
    }
    
    # Logging starten wenn aktiviert
    if ($enabled) {
        $logDir = "$PSScriptRoot\$path"
        
        # Verzeichnis erstellen
        if (-not (Test-Path $logDir)) { mkdir $logDir -Force >$null }
        
        # Dateiname mit Zeitstempel
        $ts = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
        $suffix = $mode -eq "PowerShell" ? "psh" : "pim"
        $logFile = "$logDir\log-$ts-$suffix.txt"
        
        # Transcript starten
        Start-Transcript -Path $logFile -Append
        
        $modeText = $mode -eq "PowerShell" ? "PowerShell" : "PiM-Manager"
        Write-Host "Logging aktiviert für: $modeText" -ForegroundColor Green
        Write-Host "Session wird aufgezeichnet: $logFile" -ForegroundColor Green
    }
    
    # Logging-Info zurückgeben
    return [PSCustomObject]@{
        Enabled = $enabled
        Mode = $mode
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
function StartMenu {
    # Pfade definieren
    $scriptsPath = "$PSScriptRoot\scripts"
    $adminPath = "$scriptsPath\admin"
    
    # Verzeichnisse prüfen/erstellen
    if (-not (Test-Path $scriptsPath)) {
        Write-Host "Verzeichnis 'scripts' nicht gefunden. Wird erstellt..." -ForegroundColor Yellow
        mkdir $scriptsPath -Force >$null
    }
    
    if (-not (Test-Path $adminPath)) {
        Write-Host "Verzeichnis 'scripts\admin' nicht gefunden. Wird erstellt..." -ForegroundColor Yellow
        mkdir $adminPath -Force >$null
    }
    
    $isAdmin = $false
    $pathStack = New-Object System.Collections.Stack
    $curPath = $scriptsPath

    while ($true) {
        # Pfad nach Modus setzen
        if ($isAdmin -and $pathStack.Count -eq 0) {
            $curPath = $adminPath
        } elseif (-not $isAdmin -and $pathStack.Count -eq 0) {
            $curPath = $scriptsPath
        }

        # Hauptmenü-Check
        $isRoot = $pathStack.Count -eq 0
        $parent = if (-not $isRoot) { $pathStack.Peek() } else { "" }

        # Menü anzeigen
        $menu = ShowMenu $curPath $isRoot $parent
        $choice = Read-Host "`nOption wählen"

        # Eingabe verarbeiten
        if ($choice -match "^[Xx]$") { 
            # Beenden
            break  
        }
        elseif ($choice -match "^[Mm]$") {
            # Modus wechseln
            $isAdmin = -not $isAdmin
            $pathStack.Clear()
            $curPath = $isAdmin ? $adminPath : $scriptsPath
        }
        elseif ($choice -match "^[Bb]$" -and -not $isRoot) {
            # Zurück
            $curPath = $pathStack.Pop()
        }
        elseif ($menu.ContainsKey([int]$choice)) {
            # Menüeintrag
            $item = $menu[[int]$choice]
            if (Test-Path $item -PathType Container) {
                # In Ordner navigieren
                Write-Host "Navigiere zu: $item" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                $pathStack.Push($curPath)
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
$logInfo = InitLog
$logEnabled = $logInfo.Enabled
$logMode = $logInfo.Mode

# UX-Funktionen prüfen und starten
if (Get-Command ShowMenu -EA SilentlyContinue) {
    Write-Host "PiM-Manager wird gestartet..." -ForegroundColor Green
    StartMenu
} else {
    Write-Host "❌ Fehler: Funktion 'ShowMenu' nicht gefunden. Prüfe 'modules\ux.psm1'." -ForegroundColor Red
}

# Logging beenden
if ($logEnabled) {
    Write-Host "Logging wird beendet..." -ForegroundColor Yellow
    Stop-Transcript
}