# Logging.ps1 - Aktivieren/Deaktivieren des Session-Loggings
# DisplayName: Logging-Einstellungen
# Optimiert für Tokeneffizienz

# Pfadmodul laden
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
            cfgMod = "$root\modules\config.psm1"
            settings = "$root\config\settings.json"
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
        cfgMod = "$root\modules\config.psm1"
        settings = "$root\config\settings.json"
    }
}

# Fehlermodul laden
if (Test-Path $p.errMod) {
    try { Import-Module $p.errMod -Force -EA Stop }
    catch { 
        Write-Host "Fehlermodul konnte nicht geladen werden: $_" -ForegroundColor Red 
    }
}

# UX-Modul importieren
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

# Konfigurationsmodul laden
$useCfgMod = $false
if (Test-Path $p.cfgMod) {
    if (Get-Command SafeOp -EA SilentlyContinue) {
        $useCfgMod = SafeOp {
            Import-Module $p.cfgMod -Force -EA Stop
            return $true
        } -m "Konfigurationsmodul konnte nicht geladen werden" -def $false
    } else {
        try {
            Import-Module $p.cfgMod -Force -EA Stop
            $useCfgMod = $true
        } catch {
            Write-Host "Konfigurationsmodul konnte nicht geladen werden: $_" -ForegroundColor Yellow
        }
    }
}

# Konfiguration laden mit Fehlerbehandlung
function LoadCfg($f = $p.settings) {
    # Bei aktivem Konfigurationsmodul dieses nutzen
    if ($useCfgMod -and (Get-Command GetConfig -EA SilentlyContinue)) {
        try {
            return GetConfig -name "settings"
        } catch {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Fehler beim Laden der Konfiguration über Modul" $_ "Warning"
            } else {
                Write-Host "Fehler beim Laden der Konfiguration über Modul: $_" -ForegroundColor Yellow
            }
            # Fallback auf Legacy-Methode
        }
    }
    
    # Legacy-Methode (direkte Dateioperationen)
    if (!(Test-Path $f)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Konfigurationsdatei nicht gefunden: $f" -t "Warning"
        } else {
            Write-Host "Keine Konfigurationsdatei. Logging deaktiviert." -ForegroundColor Yellow
        }
        return $null
    }
    
    if (Get-Command SafeOp -EA SilentlyContinue) {
        return SafeOp {
            Get-Content $f -Raw | ConvertFrom-Json
        } -m "Konfiguration konnte nicht geladen werden" -def $null
    } else {
        try {
            return Get-Content $f -Raw | ConvertFrom-Json
        } catch {
            Write-Host "Fehler beim Lesen: $_" -ForegroundColor Red
            return $null
        }
    }
}

# Konfiguration speichern
function SaveCfg($cfg, $f = $p.settings) {
    # Bei aktivem Konfigurationsmodul dieses nutzen
    if ($useCfgMod -and (Get-Command SaveConfig -EA SilentlyContinue)) {
        try {
            return SaveConfig -name "settings" -config $cfg
        } catch {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Fehler beim Speichern der Konfiguration über Modul" $_ "Warning"
            } else {
                Write-Host "Fehler beim Speichern der Konfiguration über Modul: $_" -ForegroundColor Yellow
            }
            # Fallback auf Legacy-Methode
        }
    }
    
    # Legacy-Methode (direkte Dateioperationen)
    if (Get-Command SafeOp -EA SilentlyContinue) {
        return SafeOp {
            $cfg | ConvertTo-Json -Depth 4 | Set-Content $f
            return $true
        } -m "Konfiguration konnte nicht gespeichert werden" -def $false
    } else {
        try {
            $cfg | ConvertTo-Json -Depth 4 | Set-Content $f
            return $true
        } catch {
            Write-Host "Fehler beim Speichern: $_" -ForegroundColor Red
            return $false
        }
    }
}

# Logging-Status anzeigen
function Status {
    $cfg = LoadCfg
    
    if ($cfg -eq $null) {
        Write-Host "`nKeine Konfigurationsdatei. Logging deaktiviert." -ForegroundColor Yellow
        return
    }
    
    if ($cfg.Logging.Enabled) {
        $mode = $cfg.Logging.Mode
        $status = $mode -eq "PowerShell" ? "Aktiviert - PowerShell" : "Aktiviert - PiM-Manager"
        $color = "Green"
    } else {
        $status = "Deaktiviert"
        $color = "Red"
    }
    
    Write-Host "`nAktueller Logging-Status: " -NoNewline
    Write-Host $status -ForegroundColor $color
    
    # Log-Pfad bei aktiviertem Logging anzeigen
    if ($cfg.Logging.Enabled) {
        $logPath = Join-Path $p.root $cfg.Logging.Path
        Write-Host "Logs: $logPath" -ForegroundColor Cyan
    }
}

# Logging deaktivieren
function Disable {
    if (!(Test-Path $p.settings)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Konfigurationsdatei nicht gefunden. Logging bereits deaktiviert." -t "Info"
        } else {
            Write-Host "Keine Konfigurationsdatei. Logging bereits deaktiviert." -ForegroundColor Yellow
        }
        return
    }
    
    $cfg = LoadCfg
    if ($cfg -eq $null) { return }
    
    $cfg.Logging.Enabled = $false
    
    $success = SaveCfg -cfg $cfg
    
    if ($success) {
        Write-Host "Logging deaktiviert." -ForegroundColor Yellow
        Write-Host "Änderung bei nächster Session wirksam." -ForegroundColor Cyan
    }
}

# PiM-Logging aktivieren
function EnablePiM { Enable "PiM" }

# PowerShell-Logging aktivieren
function EnablePSH { Enable "PowerShell" }

# Helper: Logging mit Modus aktivieren
function Enable($Mode) {
    # Konfigurationspfad prüfen/erstellen
    if (!(Test-Path $p.cfg)) { 
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                md $p.cfg -Force >$null
            } -m "Konfigurationsverzeichnis konnte nicht erstellt werden" -t "Error"
        } else {
            try {
                md $p.cfg -Force >$null
            } catch {
                Write-Host "Fehler beim Erstellen des Konfigurationsverzeichnisses: $_" -ForegroundColor Red
                return
            }
        }
    }
    
    # Konfiguration laden oder erstellen
    $cfg = LoadCfg
    
    if ($cfg -eq $null) {
        # Bei aktivem Konfigurationsmodul wird die Standardkonfiguration bereits geladen
        # Hier nur für Legacy-Fall eine neue Konfiguration erstellen
        $cfg = [PSCustomObject]@{
            Logging = [PSCustomObject]@{
                Enabled = $false
                Path = "temp\logs"
                Mode = "PiM"
            }
        }
    }
    
    # Logging aktivieren
    $cfg.Logging.Enabled = $true
    
    # Mode-Parameter prüfen und setzen
    if (!(Get-Member -InputObject $cfg.Logging -Name "Mode" -MemberType Properties)) {
        $newLog = [PSCustomObject]@{
            Enabled = $cfg.Logging.Enabled
            Path = $cfg.Logging.Path
            Mode = $Mode
        }
        
        if (Get-Command SafeOp -EA SilentlyContinue) {
            $cfgObj = SafeOp {
                $cfg | ConvertTo-Json -Depth 4 | ConvertFrom-Json
            } -m "Konfigurationsobjekt konnte nicht konvertiert werden" -def $cfg
        } else {
            try {
                $cfgObj = $cfg | ConvertTo-Json -Depth 4 | ConvertFrom-Json
            } catch {
                Write-Host "Fehler bei der Konvertierung: $_" -ForegroundColor Red
                $cfgObj = $cfg
            }
        }
        
        $cfgObj.Logging = $newLog
        $cfg = $cfgObj
    } else {
        $cfg.Logging.Mode = $Mode
    }
    
    # Speichern
    $success = SaveCfg -cfg $cfg
    
    if (!$success) {
        return
    }
    
    # Temp-Verzeichnis prüfen/erstellen
    if (!(Test-Path $p.temp)) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                md $p.temp -Force >$null
            } -m "Temp-Verzeichnis konnte nicht erstellt werden" -t "Warning"
        } else {
            try {
                md $p.temp -Force >$null
                Write-Host "Temp-Verzeichnis erstellt: $($p.temp)" -ForegroundColor Green
            } catch {
                Write-Host "Fehler beim Erstellen des Temp-Verzeichnisses: $_" -ForegroundColor Red
            }
        }
    }
    
    # Log-Verzeichnis erstellen
    $logPath = Join-Path $p.root $cfg.Logging.Path
    if (!(Test-Path $logPath)) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                md $logPath -Force >$null
            } -m "Log-Verzeichnis konnte nicht erstellt werden" -t "Warning"
        } else {
            try {
                md $logPath -Force >$null
                Write-Host "Log-Verzeichnis erstellt: $logPath" -ForegroundColor Green
            } catch {
                Write-Host "Fehler beim Erstellen des Log-Verzeichnisses: $_" -ForegroundColor Red
            }
        }
    }
    
    $mText = $Mode -eq "PowerShell" ? "PowerShell" : "PiM-Manager"
    Write-Host "Logging aktiviert für: $mText" -ForegroundColor Green
    Write-Host "Änderung bei nächster Session wirksam." -ForegroundColor Cyan
}

# Hauptmenü mit optimierter Implementierung
function Menu {
    $hasUX = Get-Command SMenu -EA SilentlyContinue
    
    # Menüoptionen
    $menu = @{
        "1" = @{
            Display = "[option]    Logging deaktivieren"
            Action = { 
                Disable
                Status
                Write-Host "`nTaste drücken für Menü..."
                [Console]::ReadKey($true) >$null
                Menu
            }
        }
        "2" = @{
            Display = "[option]    Logging aktivieren - PiM-Manager"
            Action = { 
                EnablePiM
                Status
                Write-Host "`nTaste drücken für Menü..."
                [Console]::ReadKey($true) >$null
                Menu
            }
        }
        "3" = @{
            Display = "[option]    Logging aktivieren - PowerShell"
            Action = { 
                EnablePSH
                Status
                Write-Host "`nTaste drücken für Menü..."
                [Console]::ReadKey($true) >$null
                Menu
            }
        }
    }

    if ($hasUX) {
        # UX-Modul nutzen
        if (Get-Command SafeOp -EA SilentlyContinue) {
            $result = SafeOp {
                SMenu -t "Logging-Manager" -m "Admin-Modus" -opts $menu -back -exit
            } -m "Menü konnte nicht angezeigt werden" -def "B"
        } else {
            $result = SMenu -t "Logging-Manager" -m "Admin-Modus" -opts $menu -back -exit
        }
        
        # Die SMenu-Funktion beendet den Prozess bereits bei X 
        # Wir müssen hier nur das Ergebnis B abfangen
        if ($result -eq "B") { return }
    } else {
        # Fallback zur einfachen Methode
        cls
        
        if (Get-Command Title -EA SilentlyContinue) {
            Title "Logging-Manager" "Admin-Modus"
        } else {
            Write-Host "+===============================================+"
            Write-Host "|                Logging-Manager               |"
            Write-Host "+===============================================+"
        }
        
        Status
        Write-Host ""
        
        # Optionen anzeigen
        foreach ($k in ($menu.Keys | Sort-Object)) {
            Write-Host "    $k       $($menu[$k].Display)"
        }
        
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
        Write-Host ""
        $ch = Read-Host "Option wählen"
        
        if ($ch -match "^[Xx]$") {
            Write-Host "PiM-Manager wird beendet..." -ForegroundColor Yellow
            exit
        } elseif ($ch -match "^[Bb]$") {
            return
        } elseif ($menu.ContainsKey($ch)) {
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    & $menu[$ch].Action
                } -m "Aktion konnte nicht ausgeführt werden" -t "Warning"
            } else {
                try {
                    & $menu[$ch].Action
                } catch {
                    Write-Host "Fehler bei der Ausführung: $_" -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    Menu
                }
            }
        } else {
            Write-Host "Ungültige Option." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Menu
        }
    }
}

# Menü starten
Menu