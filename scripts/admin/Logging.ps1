# Logging.ps1 - Aktivieren/Deaktivieren des Session-Loggings
# DisplayName: Logging-Einstellungen
# Optimiert für Tokeneffizienz

# Pfadberechnung (2 Ebenen hoch vom scripts\admin)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cfgPath = "$root\config"
$cfgFile = "$cfgPath\settings.json"
$tempPath = "$root\temp"

# UX-Modul importieren
$modPath = "$root\modules\ux.psm1"
if (Test-Path $modPath) {
    try { Import-Module $modPath -Force -EA Stop }
    catch { Write-Host "UX-Fehler: $_" -ForegroundColor Red }
}

# Logging-Status anzeigen
function Status {
    if (Test-Path $cfgFile) {
        try {
            $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
            
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
                Write-Host "Logs: $root\$($cfg.Logging.Path)" -ForegroundColor Cyan
            }
        } catch { Write-Host "Fehler beim Lesen: $_" -ForegroundColor Red }
    } else {
        Write-Host "`nKeine Konfigurationsdatei. Logging deaktiviert." -ForegroundColor Yellow
    }
}

# Logging deaktivieren
function Disable {
    if (Test-Path $cfgFile) {
        try {
            $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
            $cfg.Logging.Enabled = $false
            $cfg | ConvertTo-Json -Depth 4 | Set-Content $cfgFile
            Write-Host "Logging deaktiviert." -ForegroundColor Yellow
            Write-Host "Änderung bei nächster Session wirksam." -ForegroundColor Cyan
        } catch { Write-Host "Fehler: $_" -ForegroundColor Red }
    } else {
        Write-Host "Keine Konfigurationsdatei. Logging bereits deaktiviert." -ForegroundColor Yellow
    }
}

# PiM-Logging aktivieren
function EnablePiM { Enable "PiM" }

# PowerShell-Logging aktivieren
function EnablePSH { Enable "PowerShell" }

# Helper: Logging mit Modus aktivieren
function Enable($Mode) {
    # Konfigurationspfad prüfen/erstellen
    if (!(Test-Path $cfgPath)) { md $cfgPath -Force >$null }
    
    # Konfiguration laden oder erstellen
    if (Test-Path $cfgFile) {
        try { $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json }
        catch {
            $cfg = [PSCustomObject]@{
                Logging = [PSCustomObject]@{
                    Enabled = $false
                    Path = "temp\logs"
                    Mode = "PiM"
                }
            }
        }
    } else {
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
        
        $cfgObj = $cfg | ConvertTo-Json -Depth 4 | ConvertFrom-Json
        $cfgObj.Logging = $newLog
        $cfg = $cfgObj
    } else {
        $cfg.Logging.Mode = $Mode
    }
    
    # Speichern
    $cfg | ConvertTo-Json -Depth 4 | Set-Content $cfgFile
    
    # Temp-Verzeichnis prüfen/erstellen
    if (!(Test-Path $tempPath)) {
        md $tempPath -Force >$null
        Write-Host "Temp-Verzeichnis erstellt: $tempPath" -ForegroundColor Green
    }
    
    # Log-Verzeichnis erstellen
    $logPath = "$root\$($cfg.Logging.Path)"
    if (!(Test-Path $logPath)) {
        md $logPath -Force >$null
        Write-Host "Log-Verzeichnis erstellt: $logPath" -ForegroundColor Green
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
        $result = SMenu -t "Logging-Manager" -m "Admin-Modus" -opts $menu -back -exit
        
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
        foreach ($k in ($menu.Keys | Sort)) {
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
            & $menu[$ch].Action
        } else {
            Write-Host "Ungültige Option." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Menu
        }
    }
}

# Menü starten
Menu