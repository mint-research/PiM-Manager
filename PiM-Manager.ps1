# PiM-Manager.ps1 - Hauptskript mit UI-Modul und Session-Logging (Tokenoptimiert)

# Pfadmodul erstellen/laden
$pathsMod = "$PSScriptRoot\modules\paths.psm1"
if (!(Test-Path $pathsMod)) {
    # Verzeichnis prüfen/erstellen
    $modDir = "$PSScriptRoot\modules"
    if (!(Test-Path $modDir)) {
        try { md $modDir -Force >$null }
        catch {
            Write-Host "Fehler: Modulverzeichnis konnte nicht erstellt werden: $_" -ForegroundColor Red
            exit 1
        }
    }
    
    # Pfadmodul-Inhalt aus Codierungsstandard kopieren (hier vereinfacht)
    @'
# paths.psm1 - Zentrale Pfadberechnung für PiM-Manager
function GetRoot($s) {
    if ($s -match "\\scripts\\admin\\[^\\]+\\") {
        return Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $s)))
    } elseif ($s -match "\\scripts\\admin\\") {
        return Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $s))
    } elseif ($s -match "\\scripts\\") {
        return Split-Path -Parent (Split-Path -Parent $s)
    } elseif ($s -match "\\modules\\") {
        return Split-Path -Parent (Split-Path -Parent $s)
    } else {
        return Split-Path -Parent $s
    }
}

function GetPaths([string]$s = $PSScriptRoot) {
    $p = @{}
    $p.root = GetRoot $s
    $p.admin = $s -match "\\scripts\\admin\\"
    $p.cfg = Join-Path $p.root "config"
    $p.temp = Join-Path $p.root "temp"
    $p.mod = Join-Path $p.root "modules"
    $p.scripts = Join-Path $p.root "scripts"
    $p.logs = Join-Path $p.temp "logs"
    $p.backups = Join-Path $p.temp "backups"
    $p.errMod = Join-Path $p.mod "error.psm1"
    $p.uxMod = Join-Path $p.mod "ux.psm1"
    $p.pathsMod = Join-Path $p.mod "paths.psm1"
    $p.cfgMod = Join-Path $p.mod "config.psm1"
    $p.adminMod = Join-Path $p.mod "admin.psm1"
    $p.settings = Join-Path $p.cfg "settings.json"
    $p.userSettings = Join-Path $p.cfg "user-settings.json"
    return $p
}

function P([string]$key = "root") {
    $s = try { (Get-Variable -Scope 1 -Name MyInvocation -EA Stop).Value.ScriptName } catch { $PSCommandPath }
    $paths = GetPaths $s
    return $paths.$key ?? $paths.root
}

function IsAdminScript([string]$s = $PSScriptRoot) {
    return $s -match "\\scripts\\admin\\"
}

Export-ModuleMember -Function GetPaths, P, IsAdminScript
'@ | Set-Content $pathsMod
}

# Pfade über das Modul beziehen
try {
    Import-Module $pathsMod -Force -EA Stop
    $p = GetPaths $PSScriptRoot
} catch {
    # Fallback bei Modulladefehler
    Write-Host "Fehler beim Laden des Pfadmoduls: $_" -ForegroundColor Red
    $p = @{
        root = $PSScriptRoot
        cfg = "$PSScriptRoot\config"
        temp = "$PSScriptRoot\temp"
        mod = "$PSScriptRoot\modules"
        settings = "$PSScriptRoot\config\settings.json"
        logs = "$PSScriptRoot\temp\logs"
        cfgMod = "$PSScriptRoot\modules\config.psm1"
        adminMod = "$PSScriptRoot\modules\admin.psm1"
    }
}

# Fehlerbehandlungsmodul laden
$errMod = $p.errMod
if (Test-Path $errMod) {
    try { Import-Module $errMod -Force -EA Stop }
    catch { 
        Write-Host "Fehlermodul konnte nicht geladen werden: $_" -ForegroundColor Red 
    }
}

# Admin-Modul laden
$useAdminMod = $false
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
}

# Konfigurationsmodul laden
$useCfgMod = $false
if (Test-Path $p.cfgMod) {
    try { 
        Import-Module $p.cfgMod -Force -EA Stop 
        $useCfgMod = $true
        Write-Verbose "Konfigurationsmodul geladen."
    } catch { 
        Write-Host "Konfigurationsmodul konnte nicht geladen werden: $_" -ForegroundColor Yellow 
    }
}

# Erstinitialisierung prüfen
if (!(Test-Path $p.settings)) {
    Write-Host "Erststart erkannt. Konfiguration wird initialisiert..." -ForegroundColor Yellow
    $initScript = Join-Path $p.cfg "Initialize-DefaultSettings.ps1"
    
    if (Test-Path $initScript) {
        SafeOp {
            & $initScript
        } -m "Initialisierung fehlgeschlagen" -t "Warning"
    } else {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Initialisierungsskript nicht gefunden: $initScript" -t "Warning"
        } else {
            Write-Host "Initialisierungsskript nicht gefunden: $initScript" -ForegroundColor Red
        }
        
        # Einfache Standardkonfiguration
        if (!(Test-Path $p.cfg)) { 
            SafeOp {
                md $p.cfg -Force >$null
            } -m "Konfigurationsordner konnte nicht erstellt werden" -t "Warning"
        }
        
        # Konfiguration erstellen - entweder mit Modul oder direkt
        if ($useCfgMod -and (Get-Command GetConfig -EA SilentlyContinue)) {
            # Verwende das Konfigurationsmodul
            GetConfig -name "settings"
        } else {
            # Direkte Methode
            SafeOp {
                @{
                    Logging = @{
                        Enabled = $false
                        Path = "temp\logs"
                        Mode = "PiM"
                    }
                } | ConvertTo-Json -Depth 4 | Set-Content $p.settings
                
                Write-Host "Standardkonfiguration erstellt." -ForegroundColor Green
            } -m "Standardkonfiguration konnte nicht erstellt werden" -t "Warning"
        }
    }
}

# Temp-Verzeichnis prüfen/erstellen
if (!(Test-Path $p.temp)) {
    SafeOp {
        md $p.temp -Force >$null
        Write-Host "Temp-Verzeichnis erstellt: $($p.temp)" -ForegroundColor Green
    } -m "Temp-Verzeichnis konnte nicht erstellt werden" -t "Warning"
}

# Konfiguration laden mit Fehlerbehandlung
function LoadCfg {
    # Bei aktivem Konfigurationsmodul dieses nutzen
    if ($useCfgMod -and (Get-Command GetConfig -EA SilentlyContinue)) {
        return SafeOp {
            GetConfig -name "settings"
        } -m "Konfiguration konnte nicht über Modul geladen werden" -def @{
            Logging = @{Enabled = $false; Path = "temp\logs"; Mode = "PiM"}
        }
    }
    
    # Legacy-Methode (direkte Dateioperationen)
    if (!(Test-Path $p.settings)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Konfigurationsdatei nicht gefunden: $($p.settings)" -t "Warning"
        } else {
            Write-Host "Konfigurationsdatei nicht gefunden: $($p.settings)" -ForegroundColor Yellow
        }
        return @{Logging = @{Enabled = $false; Path = "temp\logs"; Mode = "PiM"}}
    }
    
    if (Get-Command SafeOp -EA SilentlyContinue) {
        return SafeOp {
            Get-Content $p.settings -Raw | ConvertFrom-Json
        } -m "Konfiguration konnte nicht geladen werden" -def @{
            Logging = @{Enabled = $false; Path = "temp\logs"; Mode = "PiM"}
        }
    } else {
        try {
            return Get-Content $p.settings -Raw | ConvertFrom-Json
        } catch {
            Write-Host "Fehler beim Lesen der Konfiguration: $_" -ForegroundColor Red
            return @{Logging = @{Enabled = $false; Path = "temp\logs"; Mode = "PiM"}}
        }
    }
}