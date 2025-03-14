# Backup.ps1 - Backup und Wiederherstellung für PiM-Manager
# Speicherort: scripts\admin\
# Version: 1.0

<#
.SYNOPSIS
Erstellt und verwaltet Backups des PiM-Manager-Systems.

.DESCRIPTION
Dieses Skript ermöglicht das Erstellen von Backups aller relevanten Dateien 
(unter Berücksichtigung der .gitignore-Regeln) sowie die Wiederherstellung 
aus zuvor erstellten Backups.

.NOTES
Datum: 2025-03-14
#>

# Pfadberechnung (zwei Ebenen nach oben von scripts\admin)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cfgPath = "$root\config"
$tempPath = "$root\temp"
$gitIgnore = "$root\.gitignore"

# UX-Modul laden
$modPath = "$root\modules\ux.psm1"
if (Test-Path $modPath) {
    try { Import-Module $modPath -Force -EA Stop }
    catch { Write-Host "UX-Modul-Fehler: $_" -ForegroundColor Red }
}

# Logging-Funktion
function Log($m, $t = "Info") {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $script = Split-Path -Leaf $PSCommandPath
    $logLine = "[$ts] [$script] [$t] $m"
    
    switch ($t) {
        "Error" { Write-Host $logLine -ForegroundColor Red }
        "Warning" { Write-Host $logLine -ForegroundColor Yellow }
        default { Write-Host $logLine -ForegroundColor Gray }
    }
}

# GitIgnore-Regeln parsen
function ParseGitIgnore {
    if (-not (Test-Path $gitIgnore)) {
        Log "GitIgnore nicht gefunden: $gitIgnore" "Warning"
        return @()
    }

    $rules = @()
    Get-Content $gitIgnore | ? { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#') } | % {
        if ($_.StartsWith('!')) {
            # Negation (Einschluss)
            $rules += @{Rule = $_.Substring(1).Trim(); Include = $true}
        } else {
            # Standard (Ausschluss)
            $rules += @{Rule = $_.Trim(); Include = $false}
        }
    }
    
    return $rules
}

# Test, ob Pfad auf Basis der GitIgnore-Regeln ignoriert werden soll
function ShouldIgnore($path, $rules) {
    # Relativen Pfad bestimmen
    $relPath = $path.Replace($root, "").TrimStart("\")
    
    # Standardmäßig nicht ignorieren
    $ignore = $false
    
    foreach ($r in $rules) {
        $pattern = $r.Rule
        $include = $r.Include
        
        # Unterstützt grundlegende Glob-Patterns
        if ($pattern.EndsWith("/**")) {
            # Verzeichnis und alle Unterverzeichnisse
            $dirPattern = $pattern.Substring(0, $pattern.Length - 3)
            if ($relPath.StartsWith($dirPattern) -or $relPath -eq $dirPattern.TrimEnd('/')) {
                $ignore = -not $include
            }
        } elseif ($pattern.EndsWith("/")) {
            # Nur Verzeichnis
            $dirPattern = $pattern.TrimEnd("/")
            if ($relPath.StartsWith("$dirPattern\") -or $relPath -eq $dirPattern) {
                $ignore = -not $include
            }
        } elseif ($pattern.EndsWith("/*")) {
            # Nur Dateien in Verzeichnis (nicht Unterverzeichnisse)
            $dirPattern = $pattern.Substring(0, $pattern.Length - 2)
            $parent = Split-Path -Parent $relPath
            if ($parent -eq $dirPattern.TrimEnd('/')) {
                $ignore = -not $include
            }
        } elseif ($pattern.Contains("*")) {
            # Wildcard-Pattern
            $regex = "^" + [regex]::Escape($pattern).Replace("\*", ".*") + "$"
            if ($relPath -match $regex) {
                $ignore = -not $include
            }
        } else {
            # Exakte Übereinstimmung
            if ($relPath -eq $pattern -or $relPath.StartsWith("$pattern\")) {
                $ignore = -not $include
            }
        }
    }
    
    return $ignore
}

# Backup erstellen
function CreateBackup {
    Log "Backup wird vorbereitet..."
    
    # Zeitstempel für Backup-Verzeichnis
    $ts = Get-Date -Format "yyyy-MM-dd-HH-mm"
    $backupName = "backup-$ts"
    $backupPath = "$tempPath\$backupName"
    
    # Temp-Verzeichnis prüfen/erstellen
    if (-not (Test-Path $tempPath)) {
        mkdir $tempPath -Force >$null
        Log "Temp-Verzeichnis erstellt: $tempPath"
    }
    
    # Backup-Verzeichnis erstellen
    mkdir $backupPath -Force >$null
    Log "Backup-Verzeichnis erstellt: $backupPath"
    
    # GitIgnore-Regeln laden
    $rules = ParseGitIgnore
    Log "GitIgnore-Regeln geladen: $($rules.Count) Einträge"
    
    # Alle Dateien und Verzeichnisse im Root-Verzeichnis
    $allItems = Get-ChildItem $root -Recurse -File
    
    # Zu sichernde Dateien ermitteln
    $backupItems = $allItems | ? {
        # Backup-Verzeichnis selbst ausschließen
        if ($_.FullName.StartsWith($backupPath)) { return $false }
        # Nach GitIgnore-Regeln filtern
        return -not (ShouldIgnore $_.FullName $rules)
    }
    
    $totalFiles = $backupItems.Count
    Log "Zu sichernde Dateien: $totalFiles"
    
    # Fortschrittsanzeige vorbereiten
    $progress = 0
    $activity = "Backup erstellen"
    
    foreach ($item in $backupItems) {
        # Relativen Pfad bestimmen
        $relPath = $item.FullName.Replace($root, "").TrimStart("\")
        $targetPath = "$backupPath\$relPath"
        
        # Zielverzeichnis erstellen
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path $targetDir)) {
            mkdir $targetDir -Force >$null
        }
        
        # Datei kopieren
        Copy-Item -Path $item.FullName -Destination $targetPath -Force
        
        # Fortschritt anzeigen
        $progress++
        $percent = [math]::Round(($progress / $totalFiles) * 100)
        Write-Progress -Activity $activity -Status "$percent% abgeschlossen" -PercentComplete $percent -CurrentOperation $relPath
    }
    
    Write-Progress -Activity $activity -Completed
    
    # Erfolgsmeldung
    Log "Backup abgeschlossen: $backupPath" "Info"
    Write-Host "`nBackup wurde erfolgreich erstellt:" -ForegroundColor Green
    Write-Host "Speicherort: $backupPath" -ForegroundColor Cyan
    Write-Host "Gesicherte Dateien: $totalFiles" -ForegroundColor Cyan
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    ShowMainMenu
}

# Backup wiederherstellen
function RestoreBackup {
    # Prüfen auf vorhandene Backups
    if (-not (Test-Path $tempPath)) {
        Log "Keine Backups gefunden" "Warning"
        Write-Host "`nEs wurden keine Backups gefunden.`nErstellen Sie zuerst ein Backup." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        ShowMainMenu
        return
    }
    
    # Verfügbare Backups suchen
    $backups = Get-ChildItem $tempPath -Directory | ? { $_.Name -match "^backup-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$" } | Sort-Object Name -Descending
    
    if ($backups.Count -eq 0) {
        Log "Keine Backups gefunden" "Warning"
        Write-Host "`nEs wurden keine Backups gefunden.`nErstellen Sie zuerst ein Backup." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        ShowMainMenu
        return
    }
    
    # Backups anzeigen
    cls
    $hasUX = Get-Command ShowTitle -EA SilentlyContinue
    if ($hasUX) {
        ShowTitle "Backup wiederherstellen" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|          Backup wiederherstellen             |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    Write-Host "`nVerfügbare Backups:`n" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b = $backups[$i]
        $date = $b.Name.Substring(7)  # "backup-" entfernen
        $files = (Get-ChildItem $b.FullName -Recurse -File).Count
        Write-Host "  $($i+1). $date - $files Dateien"
    }
    
    # Auswahl
    Write-Host "`nGeben Sie die Nummer des wiederherzustellenden Backups ein"
    Write-Host "oder 'B' für zurück zum Hauptmenü."
    $choice = Read-Host "`nAuswahl"
    
    if ($choice -match "^[Bb]$") {
        ShowMainMenu
        return
    }
    
    # Numerischen Wert validieren
    if (-not ($choice -match "^\d+$")) {
        Log "Ungültige Eingabe: $choice" "Warning"
        Write-Host "`nUngültige Eingabe. Bitte eine Zahl eingeben." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        RestoreBackup
        return
    }
    
    $index = [int]$choice - 1
    
    # Index-Bereichsprüfung
    if ($index -lt 0 -or $index -ge $backups.Count) {
        Log "Ungültiger Index: $index" "Warning"
        Write-Host "`nUngültige Auswahl. Bitte wählen Sie eine Zahl zwischen 1 und $($backups.Count)." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        RestoreBackup
        return
    }
    
    # Bestätigung
    $selectedBackup = $backups[$index]
    $backupDate = $selectedBackup.Name.Substring(7)
    Write-Host "`nSie haben folgendes Backup ausgewählt:"
    Write-Host "Datum: $backupDate" -ForegroundColor Cyan
    Write-Host "Pfad: $($selectedBackup.FullName)" -ForegroundColor Cyan
    
    $confirm = Read-Host "`nMöchten Sie fortfahren? (j/n)"
    
    if ($confirm -ne "j") {
        Log "Wiederherstellung abgebrochen" "Warning"
        Write-Host "`nWiederherstellung abgebrochen." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        ShowMainMenu
        return
    }
    
    # Wiederherstellung durchführen
    Log "Beginne Wiederherstellung von: $($selectedBackup.FullName)" "Info"
    
    # Alle Dateien im Backup
    $backupFiles = Get-ChildItem $selectedBackup.FullName -Recurse -File
    $totalFiles = $backupFiles.Count
    $progress = 0
    $activity = "Backup wiederherstellen"
    
    foreach ($file in $backupFiles) {
        # Relativen Pfad im Backup bestimmen
        $relPath = $file.FullName.Replace($selectedBackup.FullName, "").TrimStart("\")
        $targetPath = "$root\$relPath"
        
        # Zielverzeichnis erstellen
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path $targetDir)) {
            mkdir $targetDir -Force >$null
        }
        
        # Datei kopieren
        Copy-Item -Path $file.FullName -Destination $targetPath -Force
        
        # Fortschritt anzeigen
        $progress++
        $percent = [math]::Round(($progress / $totalFiles) * 100)
        Write-Progress -Activity $activity -Status "$percent% abgeschlossen" -PercentComplete $percent -CurrentOperation $relPath
    }
    
    Write-Progress -Activity $activity -Completed
    
    # Erfolgsmeldung
    Log "Wiederherstellung abgeschlossen" "Info"
    Write-Host "`nWiederherstellung wurde erfolgreich abgeschlossen!" -ForegroundColor Green
    Write-Host "Wiederhergestellte Dateien: $totalFiles" -ForegroundColor Cyan
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    ShowMainMenu
}

# Backup-Verwaltung
function ManageBackups {
    # Prüfen auf vorhandene Backups
    if (-not (Test-Path $tempPath)) {
        Log "Keine Backups gefunden" "Warning"
        Write-Host "`nEs wurden keine Backups gefunden." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        ShowMainMenu
        return
    }
    
    # Verfügbare Backups suchen
    $backups = Get-ChildItem $tempPath -Directory | ? { $_.Name -match "^backup-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$" } | Sort-Object Name -Descending
    
    if ($backups.Count -eq 0) {
        Log "Keine Backups gefunden" "Warning"
        Write-Host "`nEs wurden keine Backups gefunden." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        ShowMainMenu
        return
    }
    
    # Backups anzeigen
    cls
    $hasUX = Get-Command ShowTitle -EA SilentlyContinue
    if ($hasUX) {
        ShowTitle "Backup-Verwaltung" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|            Backup-Verwaltung                 |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    Write-Host "`nVerfügbare Backups:`n" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b = $backups[$i]
        $date = $b.Name.Substring(7)  # "backup-" entfernen
        $files = (Get-ChildItem $b.FullName -Recurse -File).Count
        $size = "{0:N2} MB" -f ((Get-ChildItem $b.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB)
        Write-Host "  $($i+1). $date - $files Dateien - $size"
    }
    
    # Auswahl
    Write-Host "`nGeben Sie die Nummer des zu löschenden Backups ein"
    Write-Host "oder 'A' um alle Backups zu löschen,"
    Write-Host "oder 'B' für zurück zum Hauptmenü."
    $choice = Read-Host "`nAuswahl"
    
    if ($choice -match "^[Bb]$") {
        ShowMainMenu
        return
    }
    
    if ($choice -match "^[Aa]$") {
        # Bestätigung für Löschung aller Backups
        Write-Host "`nSind Sie sicher, dass Sie ALLE Backups löschen möchten?" -ForegroundColor Red
        Write-Host "Diese Aktion kann nicht rückgängig gemacht werden!" -ForegroundColor Red
        $confirm = Read-Host "Bestätigen Sie mit 'ja'"
        
        if ($confirm -eq "ja") {
            Log "Lösche alle Backups" "Warning"
            
            foreach ($b in $backups) {
                Remove-Item $b.FullName -Recurse -Force
                Log "Backup gelöscht: $($b.Name)" "Info"
            }
            
            Write-Host "`nAlle Backups wurden gelöscht." -ForegroundColor Green
        } else {
            Write-Host "`nLöschung abgebrochen." -ForegroundColor Yellow
        }
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        ShowMainMenu
        return
    }
    
    # Numerischen Wert validieren
    if (-not ($choice -match "^\d+$")) {
        Log "Ungültige Eingabe: $choice" "Warning"
        Write-Host "`nUngültige Eingabe. Bitte eine Zahl eingeben." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        ManageBackups
        return
    }
    
    $index = [int]$choice - 1
    
    # Index-Bereichsprüfung
    if ($index -lt 0 -or $index -ge $backups.Count) {
        Log "Ungültiger Index: $index" "Warning"
        Write-Host "`nUngültige Auswahl. Bitte wählen Sie eine Zahl zwischen 1 und $($backups.Count)." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        ManageBackups
        return
    }
    
    # Bestätigung
    $selectedBackup = $backups[$index]
    $backupDate = $selectedBackup.Name.Substring(7)
    Write-Host "`nSie haben folgendes Backup ausgewählt:"
    Write-Host "Datum: $backupDate" -ForegroundColor Cyan
    Write-Host "Pfad: $($selectedBackup.FullName)" -ForegroundColor Cyan
    
    Write-Host "`nMöchten Sie dieses Backup löschen?" -ForegroundColor Yellow
    $confirm = Read-Host "Bestätigen Sie mit 'j'"
    
    if ($confirm -eq "j") {
        Log "Lösche Backup: $($selectedBackup.Name)" "Warning"
        Remove-Item $selectedBackup.FullName -Recurse -Force
        Write-Host "`nBackup wurde gelöscht." -ForegroundColor Green
    } else {
        Write-Host "`nLöschung abgebrochen." -ForegroundColor Yellow
    }
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    ShowMainMenu
}

# Hauptmenü anzeigen
function ShowMainMenu {
    # UX-Funktion prüfen
    $hasUX = Get-Command ShowScriptMenu -EA SilentlyContinue
    
    # Menüoptionen
    $opts = @{
        "1" = @{
            Display = "[option]    Backup erstellen"
            Action = { CreateBackup }
        }
        "2" = @{
            Display = "[option]    Backup wiederherstellen"
            Action = { RestoreBackup }
        }
        "3" = @{
            Display = "[option]    Backup-Verwaltung"
            Action = { ManageBackups }
        }
    }
    
    if ($hasUX) {
        # UX-Modul nutzen
        $result = ShowScriptMenu -title "Backup-Manager" -mode "Admin-Modus" -options $opts -enableBack -enableExit
        
        if ($result -eq "B") {
            return
        }
    } else {
        # Fallback-Menü
        cls
        Write-Host "+===============================================+"
        Write-Host "|              Backup-Manager                  |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
        
        # Optionen anzeigen
        foreach ($key in ($opts.Keys | Sort-Object)) {
            Write-Host "    $key       $($opts[$key].Display)"
        }
        
        # Navigation
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
        # Eingabe
        Write-Host ""
        $choice = Read-Host "Option wählen"
        
        if ($choice -match "^[Xx]$") {
            Write-Host "PiM-Manager wird beendet..." -ForegroundColor Yellow
            exit
        } elseif ($choice -match "^[Bb]$") {
            return
        } elseif ($opts.ContainsKey($choice)) {
            & $opts[$choice].Action
        } else {
            Write-Host "Ungültige Option." -ForegroundColor Red
            Start-Sleep -Seconds 2
            ShowMainMenu
        }
    }
}

# Skriptstart
Log "Backup-Manager gestartet"
ShowMainMenu
Log "Backup-Manager beendet"