# ux.psm1 - UI-Funktionen für den PiM-Manager (Tokenoptimiert)
# Speicherort: modules-Verzeichnis

# Pfadmodul laden, falls verfügbar
$pathsMod = Join-Path (Split-Path -Parent $PSScriptRoot) "modules\paths.psm1"
if (Test-Path $pathsMod) {
    try { 
        Import-Module $pathsMod -Force -EA Stop 
        $p = GetPaths $PSScriptRoot
    } catch { 
        # Stille Fehlerbehandlung, da wir im Modul sind
        $p = @{
            root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            errMod = Join-Path (Split-Path -Parent $PSScriptRoot) "modules\error.psm1"
        }
    }
} else {
    # Fallback ohne Pfadmodul
    $p = @{
        root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        errMod = Join-Path (Split-Path -Parent $PSScriptRoot) "modules\error.psm1"
    }
}

# Fehlermodul laden, falls verfügbar
if (Test-Path $p.errMod) {
    try { 
        Import-Module $p.errMod -Force -EA Stop 
    } catch { 
        # Stille Fehlerbehandlung, da wir im Modul sind
    }
}

# Titel anzeigen
function Title {
    param (
        [string]$t,
        [string]$m
    )
    
    $border = "+===============================================+"
    Write-Host ""
    Write-Host "    $border"
    Write-Host "                    $t                 "
    Write-Host "                    ($m)                "
    Write-Host "    $border"
    Write-Host ""
}

# Skript-Metadaten auslesen
function GetMeta {
    param (
        [string]$path
    )
    
    # Default-Metadata
    $meta = @{
        DisplayName = [IO.Path]::GetFileNameWithoutExtension($path)
    }
    
    # Prüfen, ob Datei existiert
    if (!(Test-Path $path -PathType Leaf)) {
        return $meta
    }
    
    # Ersten 10 Zeilen auslesen mit Fehlerbehandlung
    if (Get-Command SafeOp -EA SilentlyContinue) {
        $c = SafeOp {
            Get-Content $path -TotalCount 10
        } -m "Metadaten konnten nicht gelesen werden" -def @()
    } else {
        try {
            $c = Get-Content $path -TotalCount 10
        } catch {
            Write-Host "Fehler beim Lesen der Metadaten: $_" -ForegroundColor Red
            return $meta
        }
    }
    
    # Nach Metadaten suchen
    foreach ($l in $c) {
        # DisplayName-Metadaten suchen
        if ($l -match '^\s*#\s*DisplayName\s*:\s*(.+)$') {
            $meta.DisplayName = $matches[1].Trim()
        }
    }
    
    return $meta
}

# Menü anzeigen mit korrekter Ausrichtung
function ShowMenu {
    param (
        [string]$path,
        [bool]$isRoot = $true,
        [string]$parent = ""
    )

    # Konsole löschen
    cls

    # Pfad-Existenz prüfen mit verbesserter Fehlerbehandlung
    if (!(Test-Path $path)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Verzeichnis nicht gefunden: $path" -t "Warning"
        } else {
            Write-Host "Fehler: Verzeichnis '$path' nicht gefunden" -ForegroundColor Red
        }
        
        Write-Host "Erstelle Verzeichnis..." -ForegroundColor Yellow
        
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                md $path -Force >$null
            } -m "Verzeichnis konnte nicht erstellt werden: $path" -t "Error"
        } else {
            try {
                md $path -Force >$null
            } catch {
                Write-Host "Kritischer Fehler: Verzeichnis konnte nicht erstellt werden: $_" -ForegroundColor Red
            }
        }
    }

    # Modus bestimmen - mit Pfadmodul falls verfügbar
    if (Get-Command IsAdminScript -EA SilentlyContinue) {
        $mode = IsAdminScript $path ? "Admin-Modus" : "User-Modus"
    } else {
        $mode = $path -match "admin" ? "Admin-Modus" : "User-Modus"
    }

    # Header anzeigen
    Title "PiM-Manager" $mode

    # Sortierte Items erstellen (Ordner zuerst, dann Dateien)
    $items = @()
    
    # Ordner und Dateien einlesen mit Fehlerbehandlung
    if (Get-Command SafeOp -EA SilentlyContinue) {
        # Ordner hinzufügen (außer admin im User-Modus)
        $folders = SafeOp {
            Get-ChildItem $path | ? { 
                $_.PSIsContainer -and 
                !($mode -eq "User-Modus" -and $_.Name -eq "admin" -and $path -match "scripts$") 
            } | Sort-Object Name
        } -m "Ordner konnten nicht gelesen werden" -def @()
        
        foreach ($folder in $folders) {
            $items += $folder
        }
        
        # Dateien hinzufügen
        $files = SafeOp {
            Get-ChildItem $path | ? { !$_.PSIsContainer } | Sort-Object Name
        } -m "Dateien konnten nicht gelesen werden" -def @()
        
        foreach ($file in $files) {
            $items += $file
        }
    } else {
        try {
            # Ordner hinzufügen (außer admin im User-Modus)
            Get-ChildItem $path | ? { 
                $_.PSIsContainer -and 
                !($mode -eq "User-Modus" -and $_.Name -eq "admin" -and $path -match "scripts$") 
            } | Sort-Object Name | % { $items += $_ }
            
            # Dateien hinzufügen
            Get-ChildItem $path | ? { !$_.PSIsContainer } | Sort-Object Name | % { $items += $_ }
        } catch {
            Write-Host "Fehler beim Einlesen des Verzeichnisses: $_" -ForegroundColor Red
        }
    }
    
    $menu = @{}

    # Einträge anzeigen
    $i = 1
    foreach ($item in $items) {
        $type = if ($item.PSIsContainer) {
            "folder"
        } elseif ($item.Extension -eq ".ps1") {
            "script"
        } else {
            "file"
        }
        
        $name = $item.Name
        
        # Bei PS1-Dateien nach DisplayName-Metadaten suchen
        if ($type -eq "script") {
            $meta = GetMeta -path $item.FullName
            $name = $meta.DisplayName
        }
        
        Write-Host "    $i       [$type]    $name"
        $menu[$i] = $item.FullName
        $i++
    }

    # Leere Menü-Info
    if ($i -eq 1) {
        Write-Host "    (Keine Einträge vorhanden)" -ForegroundColor Yellow
    }

    # Fußzeile mit Optionen
    Write-Host ""
    Write-Host "    M       [mode]      $(if ($mode -eq 'Admin-Modus') {'User-Modus'} else {'Admin-Modus'})"
    
    # Zurück-Option
    if (!$isRoot) {
        Write-Host "    B       [back]      Zurück"
    }
    
    Write-Host "    X       [exit]      Beenden"

    return $menu
}

# Skriptmenü anzeigen mit konsistenter Formatierung
function SMenu {
    param (
        [Parameter(Mandatory)]
        [string]$t,
        
        [Parameter(Mandatory)]
        [string]$m,
        
        [Parameter(Mandatory)]
        [hashtable]$opts,
        
        [switch]$back,
        
        [switch]$exit
    )
    
    # Konsole löschen
    cls
    
    # Header anzeigen
    Title $t $m
    
    # Optionen anzeigen
    $keys = $opts.Keys | Sort-Object
    foreach ($k in $keys) {
        Write-Host "    $k       $($opts[$k].Display)"
    }
    
    # Leerzeile
    Write-Host ""
    
    # Navigation
    if ($back) {
        Write-Host "    B       [back]      Zurück"
    }
    
    if ($exit) {
        Write-Host "    X       [exit]      Beenden"
    }
    
    # Eingabe
    Write-Host ""
    $ch = Read-Host "Option wählen"
    
    # Verarbeiten
    if ($ch -match "^[Xx]$" -and $exit) {
        Write-Host "PiM-Manager wird beendet..." -ForegroundColor Yellow
        exit
    }
    elseif ($ch -match "^[Bb]$" -and $back) {
        return "B"
    }
    elseif ($opts.ContainsKey($ch)) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                & $opts[$ch].Action
            } -m "Aktion konnte nicht ausgeführt werden" -t "Warning"
        } else {
            try {
                & $opts[$ch].Action
            } catch {
                Write-Host "Fehler bei der Ausführung: $_" -ForegroundColor Red
            }
        }
        return $ch
    }
    else {
        Write-Host "Ungültige Option." -ForegroundColor Red
        Start-Sleep -Seconds 2
        SMenu -t $t -m $m -opts $opts -back:$back -exit:$exit
    }
}

# Aliasse für Abwärtskompatibilität
Set-Alias ShowTitle Title
Set-Alias ShowScriptMenu SMenu
Set-Alias GetScriptMetadata GetMeta

# Funktionen exportieren
Export-ModuleMember -Function ShowMenu, Title, SMenu, GetMeta -Alias ShowTitle, ShowScriptMenu, GetScriptMetadata