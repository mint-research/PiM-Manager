# Logging.ps1 - Aktivieren/Deaktivieren des Session-Loggings
# Optimiert für Tokeneffizienz

# Pfadberechnung (2 Ebenen hoch vom scripts\admin)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cfgPath = "$root\config"
$cfgFile = "$cfgPath\settings.json"

# UX-Modul importieren
$modPath = "$root\modules\ux.psm1"
if (Test-Path $modPath) {
    try { Import-Module $modPath -Force -EA Stop }
    catch { Write-Host "UX-Modul-Fehler: $_" -ForegroundColor Red }
}

# Logging-Status anzeigen
function ShowStatus {
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
function DisableLog {
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
function EnablePiM { EnableLog "PiM" }

# PowerShell-Logging aktivieren
function EnablePSH { EnableLog "PowerShell" }

# Helper: Logging mit Modus aktivieren
function EnableLog($Mode) {
    # Konfigurationspfad prüfen/erstellen
    if (-not (Test-Path $cfgPath)) { mkdir $cfgPath -Force >$null }
    
    # Konfiguration laden oder erstellen
    if (Test-Path $cfgFile) {
        try { $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json }
        catch {
            $cfg = [PSCustomObject]@{
                Logging = [PSCustomObject]@{
                    Enabled = $false
                    Path = "docs\logs"
                    Mode = "PiM"
                }
            }
        }
    } else {
        $cfg = [PSCustomObject]@{
            Logging = [PSCustomObject]@{
                Enabled = $false
                Path = "docs\logs"
                Mode = "PiM"
            }
        }
    }
    
    # Logging aktivieren
    $cfg.Logging.Enabled = $true
    
    # Mode-Parameter prüfen und setzen
    if (-not (Get-Member -InputObject $cfg.Logging -Name "Mode" -MemberType Properties)) {
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
    
    # Log-Verzeichnis erstellen
    $logPath = "$root\$($cfg.Logging.Path)"
    if (-not (Test-Path $logPath)) {
        mkdir $logPath -Force >$null
        Write-Host "Log-Verzeichnis erstellt: $logPath" -ForegroundColor Green
    }
    
    $modeText = $Mode -eq "PowerShell" ? "PowerShell" : "PiM-Manager"
    Write-Host "Logging aktiviert für: $modeText" -ForegroundColor Green
    Write-Host "Änderung bei nächster Session wirksam." -ForegroundColor Cyan
}

# Hauptmenü mit optimierter Implementierung
function ShowMenu {
    $hasUX = Get-Command Show-ScriptMenu -EA SilentlyContinue
    
    # Menüoptionen
    $menu = @{
        "1" = @{
            Display = "[option]    Logging deaktivieren"
            Action = { 
                DisableLog
                ShowStatus
                Write-Host "`nTaste drücken für Menü..."
                [Console]::ReadKey($true) >$null
                ShowMenu
            }
        }
        "2" = @{
            Display = "[option]    Logging aktivieren - PiM-Manager"
            Action = { 
                EnablePiM
                ShowStatus
                Write-Host "`nTaste drücken für Menü..."
                [Console]::ReadKey($true) >$null
                ShowMenu
            }
        }
        "3" = @{
            Display = "[option]    Logging aktivieren - PowerShell"
            Action = { 
                EnablePSH
                ShowStatus
                Write-Host "`nTaste drücken für Menü..."
                [Console]::ReadKey($true) >$null
                ShowMenu
            }
        }
    }

    if ($hasUX) {
        # UX-Modul nutzen
        $result = ShowScriptMenu -title "Logging-Manager" -mode "Admin-Modus" -options $menu -enableBack -enableExit
        
        # Die ShowScriptMenu-Funktion beendet den Prozess bereits bei X 
        # Wir müssen hier nur das Ergebnis B abfangen
        if ($result -eq "B") { return }
    } else {
        # Fallback zur einfachen Methode
        cls
        
        if (Get-Command Show-Title -EA SilentlyContinue) {
            Show-Title "Logging-Manager" "Admin-Modus"
        } else {
            Write-Host "+===============================================+"
            Write-Host "|                Logging-Manager               |"
            Write-Host "+===============================================+"
        }
        
        ShowStatus
        Write-Host ""
        
        # Optionen anzeigen
        foreach ($key in ($menu.Keys | Sort-Object)) {
            Write-Host "    $key       $($menu[$key].Display)"
        }
        
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
        Write-Host ""
        $choice = Read-Host "Option wählen"
        
        if ($choice -match "^[Xx]$") {
            Write-Host "PiM-Manager wird beendet..." -ForegroundColor Yellow
            exit
        } elseif ($choice -match "^[Bb]$") {
            return
        } elseif ($menu.ContainsKey($choice)) {
            & $menu[$choice].Action
        } else {
            Write-Host "Ungültige Option." -ForegroundColor Red
            Start-Sleep -Seconds 2
            ShowMenu
        }
    }
}

# Menü starten
ShowMenu