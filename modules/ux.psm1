# ux.psm1 - Enthält alle UI-Funktionen für den PiM-Manager
# Wird im modules-Verzeichnis abgelegt

# Funktion zum Anzeigen des Titels
function Show-Title {
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

# Funktion zur Anzeige des Menüs mit korrekter Ausrichtung
function Show-Menu {
    param (
        [string]$currentPath,
        [bool]$isRootMenu = $true,
        [string]$parentPath = ""
    )

    # Lösche die Konsole für ein sauberes Menü
    Clear-Host

    # Überprüfen ob der Pfad existiert
    if (-not (Test-Path -Path $currentPath)) {
        Write-Host "Fehler: Das Verzeichnis '$currentPath' existiert nicht" -ForegroundColor Red
        Write-Host "Erstelle Verzeichnis..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $currentPath -Force | Out-Null
    }

    # Modusnamen bestimmen
    $modeName = if ($currentPath -match "admin") { "Admin-Modus" } else { "User-Modus" }

    # Header anzeigen
    Show-Title "PiM-Manager" $modeName

    # Sortierte Liste erstellen (Ordner zuerst, dann Dateien)
    $sortedItems = @()
    
    # Zuerst alle Ordner hinzufügen, außer admin im User-Modus
    Get-ChildItem -Path $currentPath | Where-Object { 
        $_.PSIsContainer -and 
        -not ($modeName -eq "User-Modus" -and $_.Name -eq "admin" -and $currentPath -match "scripts$") 
    } | Sort-Object Name | ForEach-Object {
        $sortedItems += $_
    }
    
    # Dann alle Dateien hinzufügen
    Get-ChildItem -Path $currentPath | Where-Object { -not $_.PSIsContainer } | Sort-Object Name | ForEach-Object {
        $sortedItems += $_
    }
    
    $menu = @{ }

    # Menüeinträge anzeigen mit einheitlicher Ausrichtung
    $index = 1
    foreach ($item in $sortedItems) {
        if ($item.PSIsContainer) {
            # Ordner anzeigen
            Write-Host "    $index       [folder]    $($item.Name)"
        } 
        elseif ($item.Extension -eq ".ps1") {
            # Skript anzeigen
            Write-Host "    $index       [script]    $($item.Name)"
        }
        else {
            # Andere Dateien anzeigen
            Write-Host "    $index       [file]      $($item.Name)"
        }
        
        # Speichern für späteren Zugriff
        $menu[$index] = $item.FullName
        $index++
    }

    # Falls keine Einträge vorhanden sind, Hinweis anzeigen
    if ($index -eq 1) {
        Write-Host "    (Keine Einträge vorhanden)" -ForegroundColor Yellow
    }

    # Fußzeile anzeigen mit einheitlicher Ausrichtung zu den Menüeinträgen
    Write-Host ""
    Write-Host "    M       [mode]      $(if ($modeName -eq 'Admin-Modus') {'User-Modus'} else {'Admin-Modus'})"
    
    # Zurück-Option anzeigen, wenn nicht im Hauptmenü
    if (-not $isRootMenu) {
        Write-Host "    B       [back]      Zurück"
    }
    
    Write-Host "    X       [exit]      Beenden"

    return $menu
}

# Neue Funktion: Show-ScriptMenu
# Zeigt ein Menü für Skripte mit konsistenter Formatierung wie das Hauptmenü
function Show-ScriptMenu {
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
    
    # Lösche die Konsole für ein sauberes Menü
    Clear-Host
    
    # Header anzeigen
    Show-Title $title $mode
    
    # Optionen anzeigen (in der Reihenfolge der Schlüssel)
    $sortedKeys = $options.Keys | Sort-Object
    foreach ($key in $sortedKeys) {
        Write-Host "    $key       $($options[$key].Display)"
    }
    
    # Leerzeile vor Navigation
    Write-Host ""
    
    # Navigationsoptionen
    if ($enableBack) {
        Write-Host "    B       [back]      Zurück"
    }
    
    if ($enableExit) {
        Write-Host "    X       [exit]      Beenden"
    }
    
    # Benutzereingabe abfragen
    Write-Host ""
    $choice = Read-Host "Wähle eine Option"
    
    # Eingabe verarbeiten
    if ($options.ContainsKey($choice)) {
        & $options[$choice].Action
        return $choice
    }
    elseif ($choice -match "^[Bb]$" -and $enableBack) {
        return "B"
    }
    elseif ($choice -match "^[Xx]$" -and $enableExit) {
        return "X"
    }
    else {
        Write-Host "Ungültige Option. Bitte erneut versuchen." -ForegroundColor Red
        Start-Sleep -Seconds 2
        Show-ScriptMenu -title $title -mode $mode -options $options -enableBack:$enableBack -enableExit:$enableExit
    }
}

# Exportiere die Funktionen, damit das Hauptskript sie nutzen kann
Export-ModuleMember -Function Show-Menu, Show-Title, Show-ScriptMenu