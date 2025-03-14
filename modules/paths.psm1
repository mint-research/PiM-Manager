# paths.psm1 - Zentrale Pfadberechnung für PiM-Manager
# Speicherort: modules\paths.psm1

function GetRoot {
    param(
        [Parameter(Mandatory)]
        [string]$s
    )
    
    # Root-Pfad berechnen basierend auf der Position des aufrufenden Skripts
    if ($s -match "\\scripts\\admin\\[^\\]+\\") {
        # scripts\admin\subfolder\*.ps1 (z.B. scripts\admin\Cleanup\cleanup-pim.ps1)
        return Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $s)))
    } elseif ($s -match "\\scripts\\admin\\") {
        # scripts\admin\*.ps1
        return Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $s))
    } elseif ($s -match "\\scripts\\") {
        # scripts\*.ps1
        return Split-Path -Parent (Split-Path -Parent $s)
    } elseif ($s -match "\\modules\\") {
        # modules\*.psm1
        return Split-Path -Parent (Split-Path -Parent $s)
    } else {
        # Root-Skript oder andere Position
        return Split-Path -Parent $s
    }
}

function GetPaths {
    param(
        [string]$s = $PSScriptRoot
    )
    
    # Leeres Pfadobjekt
    $p = @{}
    
    # Root-Pfad bestimmen
    $p.root = GetRoot $s
    
    # Admin-Status erkennen
    $p.admin = $s -match "\\scripts\\admin\\"
    
    # Standardpfade berechnen
    $p.cfg = Join-Path $p.root "config"
    $p.temp = Join-Path $p.root "temp"
    $p.mod = Join-Path $p.root "modules"
    $p.scripts = Join-Path $p.root "scripts"
    $p.logs = Join-Path $p.temp "logs"
    $p.backups = Join-Path $p.temp "backups"
    
    # Modulpfade
    $p.errMod = Join-Path $p.mod "error.psm1"
    $p.uxMod = Join-Path $p.mod "ux.psm1"
    $p.pathsMod = Join-Path $p.mod "paths.psm1"
    $p.cfgMod = Join-Path $p.mod "config.psm1"
    
    # Konfigurationsdateien
    $p.settings = Join-Path $p.cfg "settings.json"
    $p.userSettings = Join-Path $p.cfg "user-settings.json"
    
    return $p
}

# Schnellzugriff-Funktion für Umgebungspfade
function P {
    param(
        [string]$key = "root"
    )
    
    # Aufrufendes Skript ermitteln
    $s = try { 
        (Get-Variable -Scope 1 -Name MyInvocation -EA Stop).Value.ScriptName 
    } catch { 
        $PSCommandPath 
    }
    
    # Pfade berechnen
    $paths = GetPaths $s
    
    # Pfad zurückgeben, oder root wenn Schlüssel nicht existiert
    return $paths.$key ?? $paths.root
}

# Prüfen, ob Skript im Admin-Bereich liegt
function IsAdminScript {
    param(
        [string]$s = $PSScriptRoot
    )
    
    return $s -match "\\scripts\\admin\\"
}

# Modul-Export
Export-ModuleMember -Function GetPaths, P, IsAdminScript