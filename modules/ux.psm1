# ux.psm1 - UI-Funktionen für den PiM-Manager (Tokenoptimiert)
# Speicherort: modules-Verzeichnis

# Titel anzeigen
function ShowTitle {
    param (
        [string]$title,
        [string]$mode
    )
    
    $border = "+===============================================+"
    Write-Host ""
    Write-Host "    $border"
    Write-Host "                    $title                 "
    Write-Host "                    ($mode)                "
    Write-Host "    $border"
    Write-Host ""
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

    # Pfad-Existenz prüfen
    if (-not (Test-Path $path)) {
        Write-Host "Fehler: Verzeichnis '$path' nicht gefunden" -ForegroundColor Red
        Write-Host "Erstelle Verzeichnis..." -ForegroundColor Yellow
        mkdir $path -Force >$null
    }

    # Modus bestimmen
    $mode = $path -match "admin" ? "Admin-Modus" : "User-Modus"

    # Header anzeigen
    ShowTitle "PiM-Manager" $mode

    # Sortierte Items erstellen (Ordner zuerst, dann Dateien)
    $items = @()
    
    # Ordner hinzufügen (außer admin im User-Modus)
    Get-ChildItem $path | ? { 
        $_.PSIsContainer -and 
        -not ($mode -eq "User-Modus" -and $_.Name -eq "admin" -and $path -match "scripts$") 
    } | Sort-Object Name | % { $items += $_ }
    
    # Dateien hinzufügen
    Get-ChildItem $path | ? { -not $_.PSIsContainer } | Sort-Object Name | % { $items += $_ }
    
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
        
        Write-Host "    $i       [$type]    $($item.Name)"
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
    if (-not $isRoot) {
        Write-Host "    B       [back]      Zurück"
    }
    
    Write-Host "    X       [exit]      Beenden"

    return $menu
}

# Skriptmenü anzeigen mit konsistenter Formatierung
function ShowScriptMenu {
    param (
        [Parameter(Mandatory=$true)]
        [string]$title,
        
        [Parameter(Mandatory=$true)]
        [string]$mode,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$options,
        
        [switch]$enableBack,
        
        [switch]$enableExit
    )
    
    # Konsole löschen
    cls
    
    # Header anzeigen
    ShowTitle $title $mode
    
    # Optionen anzeigen
    $keys = $options.Keys | Sort-Object
    foreach ($key in $keys) {
        Write-Host "    $key       $($options[$key].Display)"
    }
    
    # Leerzeile
    Write-Host ""
    
    # Navigation
    if ($enableBack) {
        Write-Host "    B       [back]      Zurück"
    }
    
    if ($enableExit) {
        Write-Host "    X       [exit]      Beenden"
    }
    
    # Eingabe
    Write-Host ""
    $choice = Read-Host "Option wählen"
    
    # Verarbeiten
    if ($choice -match "^[Xx]$" -and $enableExit) {
        Write-Host "PiM-Manager wird beendet..." -ForegroundColor Yellow
        exit
    }
    elseif ($choice -match "^[Bb]$" -and $enableBack) {
        return "B"
    }
    elseif ($options.ContainsKey($choice)) {
        & $options[$choice].Action
        return $choice
    }
    else {
        Write-Host "Ungültige Option." -ForegroundColor Red
        Start-Sleep -Seconds 2
        ShowScriptMenu -title $title -mode $mode -options $options -enableBack:$enableBack -enableExit:$enableExit
    }
}

# Funktionen exportieren
Export-ModuleMember -Function ShowMenu, ShowTitle, ShowScriptMenu