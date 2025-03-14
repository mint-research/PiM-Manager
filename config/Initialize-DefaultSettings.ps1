# Initialize-DefaultSettings.ps1 (Tokenoptimiert)
# Speicherort: config-Verzeichnis
# Erstellt alle erforderlichen Konfigurationsdateien

# Pfadmodul laden
$pathsMod = "$PSScriptRoot\..\modules\paths.psm1"
if (Test-Path $pathsMod) {
    try { 
        Import-Module $pathsMod -Force -EA Stop 
        $p = GetPaths $PSScriptRoot
    } catch {
        # Fallback bei Modulladefehler
        $cfgPath = $PSScriptRoot
        $rootPath = Split-Path -Parent $PSScriptRoot
        $p = @{
            root = $rootPath
            cfg = $cfgPath
            errMod = "$rootPath\modules\error.psm1"
            cfgMod = "$rootPath\modules\config.psm1"
        }
    }
} else {
    # Fallback ohne Pfadmodul
    $cfgPath = $PSScriptRoot
    $rootPath = Split-Path -Parent $PSScriptRoot
    $p = @{
        root = $rootPath
        cfg = $cfgPath
        errMod = "$rootPath\modules\error.psm1"
        cfgMod = "$rootPath\modules\config.psm1"
    }
}

# Fehlermodul laden
if (Test-Path $p.errMod) {
    try { Import-Module $p.errMod -Force -EA Stop }
    catch { 
        Write-Host "Fehlermodul konnte nicht geladen werden: $_" -ForegroundColor Red 
    }
}

# Konfigurationsmodul laden (falls verfügbar)
$useCfgMod = $false
if (Test-Path $p.cfgMod) {
    try { 
        Import-Module $p.cfgMod -Force -EA Stop 
        $useCfgMod = $true
        Write-Host "Konfigurationsmodul geladen." -ForegroundColor Gray
    } catch { 
        Write-Host "Konfigurationsmodul konnte nicht geladen werden: $_" -ForegroundColor Yellow
    }
}

# Verzeichnisprüfung
if (!(Test-Path $p.cfg)) {
    if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            md $p.cfg -Force >$null
        } -m "Konfigurationsverzeichnis konnte nicht erstellt werden" -t "Error"
        
        Write-Host "Konfigurationsverzeichnis erstellt: $($p.cfg)" -ForegroundColor Green
    } else {
        try {
            md $p.cfg -Force >$null
            Write-Host "Konfigurationsverzeichnis erstellt: $($p.cfg)" -ForegroundColor Green
        } catch {
            Write-Host "Fehler beim Erstellen des Konfigurationsverzeichnisses: $_" -ForegroundColor Red
        }
    }
}

# Konfigurationsdatei erstellen/aktualisieren
function Init {
    param (
        [Parameter(Mandatory)]
        [string]$f,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$def,
        
        [switch]$force
    )
    
    $path = Join-Path $p.cfg $f
    
    # Bei aktivem Konfigurationsmodul dieses nutzen
    if ($useCfgMod -and (Get-Command GetConfig -EA SilentlyContinue)) {
        try {
            # Konfiguration mit dem Modul laden/erstellen
            $name = [System.IO.Path]::GetFileNameWithoutExtension($f)
            
            if ($force) {
                # Bei force: Direkt mit Standardwerten speichern
                $success = SaveConfig -name $name -config $def
                
                if ($success) {
                    Write-Host "Konfiguration erstellt/überschrieben: $f" -ForegroundColor Green
                } else {
                    Write-Host "Fehler beim Erstellen der Konfiguration: $f" -ForegroundColor Red
                }
            } else {
                # Bestehende Konfiguration laden oder neue erstellen
                $cfg = GetConfig -name $name
                
                # Hinweis ausgeben
                if (!(Test-Path $path)) {
                    Write-Host "Konfiguration erstellt: $f" -ForegroundColor Green
                } else {
                    Write-Host "Konfiguration existiert: $f" -ForegroundColor Yellow
                }
            }
            
            return
        } catch {
            Write-Host "Fehler bei Verwendung des Konfigurationsmoduls: $_" -ForegroundColor Yellow
            Write-Host "Fallback auf direkte Dateioperationen..." -ForegroundColor Yellow
        }
    }
    
    # Fallback: Direkte Dateioperation, wenn Modul nicht verfügbar oder fehlschlägt
    # Erstellen wenn nicht vorhanden oder Überschreiben erzwungen
    if (!(Test-Path $path) -or $force) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                $def | ConvertTo-Json -Depth 4 | Set-Content $path
            } -m "Konfiguration konnte nicht erstellt werden: $f" -t "Error"
            
            Write-Host "Konfiguration erstellt: $f" -ForegroundColor Green
        } else {
            try {
                $def | ConvertTo-Json -Depth 4 | Set-Content $path
                Write-Host "Konfiguration erstellt: $f" -ForegroundColor Green
            } catch {
                Write-Host "Fehler: $f - $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "Konfiguration existiert: $f" -ForegroundColor Yellow
    }
}

# settings.json (Logging)
$defSettings = [PSCustomObject]@{
    Logging = [PSCustomObject]@{
        Enabled = $false
        Path = "temp\logs"
        Mode = "PiM"
    }
}

# Konfigurationen erstellen
Init -f "settings.json" -def $defSettings

# user-settings.json
$userSettings = [PSCustomObject]@{
    Theme = "Default"
    Language = "de-DE"
    AutoUpdate = $true
    LastCheck = (Get-Date).ToString("yyyy-MM-dd")
}

# Nur erstellen wenn nicht vorhanden
Init -f "user-settings.json" -def $userSettings

# Installationshinweis
Write-Host "`nKonfigurationen überprüft." -ForegroundColor Cyan
Write-Host "Dieses Skript kann bei jeder Installation ausgeführt werden," -ForegroundColor Cyan
Write-Host "um alle erforderlichen Konfigurationsdateien zu erstellen." -ForegroundColor Cyan

# Reset-Abfrage
$r = Read-Host "`nAlle Konfigurationen zurücksetzen? (j/n)"
if ($r -eq "j") {
    # Alle mit Standardwerten überschreiben
    if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            Init -f "settings.json" -def $defSettings -force
            Init -f "user-settings.json" -def $userSettings -force
        } -m "Konfigurationen konnten nicht zurückgesetzt werden" -t "Error"
    } else {
        try {
            Init -f "settings.json" -def $defSettings -force
            Init -f "user-settings.json" -def $userSettings -force
        } catch {
            Write-Host "Fehler beim Zurücksetzen: $_" -ForegroundColor Red
        }
    }
    
    Write-Host "`nAlle Konfigurationen zurückgesetzt." -ForegroundColor Green
}