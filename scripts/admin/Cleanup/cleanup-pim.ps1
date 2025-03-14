# cleanup-pim.ps1 - Bereinigung temporärer Dateien im PiM-Manager
# Speicherort: scripts\admin\Cleanup\
# Version: 1.0
# DisplayName: Temporäre Dateien bereinigen

function PerformCleanup($selectedFolders, $cutoffDate) {
    if ($selectedFolders.Count -eq 0 -or $null -eq $cutoffDate) {
        Log "Keine Bereinigung durchgeführt" "Warning"
        return
    }
    
    Log "Beginne Bereinigung..." "Info"
    $totalDeleted = 0
    $totalSize = 0
    
    # Debug-Info: Zeige Cutoff-Datum an, um Zeitvergleich nachzuvollziehen
    Log "Cutoff-Datum für Löschung: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
    
    foreach ($folder in $selectedFolders) {
        $folderPath = "$tempPath\$folder"
        
        if (-not (Test-Path $folderPath)) {
            Log "Verzeichnis nicht gefunden: $folderPath" "Warning"
            continue
        }
        
        Log "Suche zu löschende Dateien in: $folder" "Info"
        
        # Alle Dateien auflisten und Debug-Info ausgeben
        $allFiles = Get-ChildItem $folderPath -Recurse -File
        Log "Gesamt Dateien gefunden: $($allFiles.Count)" "Info"
        
        if ($allFiles.Count -gt 0) {
            $oldestFile = $allFiles | Sort-Object LastWriteTime | Select-Object -First 1
            $newestFile = $allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            
            Log "Älteste Datei: $($oldestFile.Name) - $($oldestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
            Log "Neueste Datei: $($newestFile.Name) - $($newestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
        }
        
        # Spezialfall für Backups: Wenn im Backup-Ordner und Option "Alle" gewählt,
        # dann komplette Backup-Verzeichnisse löschen anstatt nur einzelne Dateien
        if ($folder -eq "backups" -and $cutoffDate -eq [DateTime]::MinValue) {
            $backupFolders = Get-ChildItem $folderPath -Directory
            $folderFiles = $allFiles.Count  # Für die Berichterstattung
            $folderSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
            
            Log "Löschung von Backup-Ordnern: $($backupFolders.Count) Ordner" "Info"
            
            # Fortschritt für Backup-Ordner
            $progress = 0
            $activity = "Bereinige Backup-Ordner"
            
            foreach ($backupFolder in $backupFolders) {
                try {
                    Log "Lösche Backup-Ordner: $($backupFolder.FullName)" "Info"
                    Remove-Item $backupFolder.FullName -Recurse -Force
                    
                    # Fortschritt anzeigen
                    $progress++
                    $percent = [math]::Round(($progress / $backupFolders.Count) * 100)
                    Write-Progress -Activity $activity -Status "$percent% abgeschlossen" -PercentComplete $percent
                }
                catch {
                    Log "Fehler beim Löschen des Backup-Ordners: $($backupFolder.FullName) - $_" "Error"
                }
            }
            
            Write-Progress -Activity $activity -Completed
            $totalDeleted += $folderFiles
            $totalSize += $folderSize
        }
        else {
            # Standardverhalten für andere Ordner: Dateien für Löschung auswählen
            $filesToDelete = if ($cutoffDate -eq [DateTime]::MinValue) {
                # Bei 'Alle' auswählen einfach alle Dateien zurückgeben
                $allFiles
            } else {
                # Sonst normal nach Datum filtern
                $allFiles | Where-Object { $_.LastWriteTime -le $cutoffDate }
            }
            
            $folderFiles = $filesToDelete.Count
            Log "Zum Löschen markierte Dateien: $folderFiles" "Info"
            
            if ($folderFiles -eq 0) {
                Log "Keine zu löschenden Dateien in: $folder" "Info"
                continue
            }
            
            # Größe berechnen
            $folderSize = ($filesToDelete | Measure-Object -Property Length -Sum).Sum
            $totalSize += $folderSize
            
            # Lösch-Fortschritt
            $progress = 0
            $activity = "Bereinige $folder"
            
            foreach ($file in $filesToDelete) {
                try {
                    # Ignoriere Dateien, die gerade in Benutzung sind (z.B. aktuelle Logs)
                    $inUse = $false
                    try {
                        $fileStream = [System.IO.File]::Open($file.FullName, 
                                      [System.IO.FileMode]::Open, 
                                      [System.IO.FileAccess]::ReadWrite, 
                                      [System.IO.FileShare]::None)
                        $fileStream.Close()
                        $fileStream.Dispose()
                    }
                    catch {
                        $inUse = $true
                        Log "Datei in Benutzung, wird übersprungen: $($file.FullName)" "Warning"
                    }
                    
                    if (-not $inUse) {
                        Remove-Item $file.FullName -Force
                        $totalDeleted++
                    }
                    
                    # Fortschritt anzeigen
                    $progress++
                    $percent = [math]::Round(($progress / $folderFiles) * 100)
                    Write-Progress -Activity $activity -Status "$percent% abgeschlossen" -PercentComplete $percent
                }
                catch {
                    Log "Fehler beim Löschen: $($file.FullName) - $_" "Error"
                }
            }
            
            Write-Progress -Activity $activity -Completed
            
            # Leere Verzeichnisse entfernen (falls keine Dateien oder Unterverzeichnisse)
            Get-ChildItem $folderPath -Directory -Recurse | 
                Where-Object { 
                    (Get-ChildItem $_.FullName -Recurse -File).Count -eq 0 -and
                    (Get-ChildItem $_.FullName -Directory).Count -eq 0
                } |
                ForEach-Object {
                    try {
                        Log "Entferne leeres Verzeichnis: $($_.FullName)" "Info"
                        Remove-Item $_.FullName -Force
                    }
                    catch {
                        Log "Fehler beim Entfernen des Verzeichnisses: $($_.FullName) - $_" "Error"
                    }
                }
        }
        
        # Ausgabe pro Ordner
        $sizeInMB = [math]::Round($folderSize / 1MB, 2)
        Log "Bereinigt in '$folder': $folderFiles Dateien ($sizeInMB MB)" "Info"
    }
    
    # Ergebnisanzeige mit konsistenter Formatierung
    cls
    $hasUX = Get-Command ShowTitle -EA SilentlyContinue
    if ($# cleanup-pim.ps1 - Bereinigung temporärer Dateien im PiM-Manager
# Speicherort: scripts\admin\Cleanup\
# Version: 1.0
# DisplayName: Temporäre Dateien bereinigen

<#
.SYNOPSIS
Bereinigt temporäre Dateien und Verzeichnisse des PiM-Managers.

.DESCRIPTION
Dieses Skript durchsucht den temp-Ordner des PiM-Managers und bietet
die Möglichkeit, verschiedene Dateitypen (basierend auf Unterordnern)
und Zeitspannen für die Bereinigung auszuwählen.

.NOTES
Datum: 2025-03-14
#>

# Pfadberechnung (drei Ebenen nach oben von scripts\admin\Cleanup)
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$tempPath = "$root\temp"

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

# Dateitypen (Unterordner) im temp-Verzeichnis ermitteln
function GetTempSubfolders {
    if (-not (Test-Path $tempPath)) {
        Log "Temp-Verzeichnis nicht gefunden: $tempPath" "Warning"
        return @()
    }
    
    $folders = Get-ChildItem $tempPath -Directory | Select-Object -ExpandProperty Name
    return $folders
}

# Verfügbare Dateitypen zur Auswahl anbieten
function SelectFileTypes {
    $folders = GetTempSubfolders
    
    if ($folders.Count -eq 0) {
        Log "Keine Unterordner im temp-Verzeichnis gefunden" "Warning"
        return @()
    }
    
    $selections = @()
    
    cls
    $hasUX = Get-Command ShowTitle -EA SilentlyContinue
    if ($hasUX) {
        try {
            ShowTitle "Dateitypen auswählen" "Admin-Modus"
        } catch {
            Log "Fehler bei Titelanzeige: $_" "Warning"
            Write-Host "+===============================================+"
            Write-Host "|            Dateitypen auswählen              |"
            Write-Host "|             (Admin-Modus)                    |"
            Write-Host "+===============================================+"
        }
    } else {
        Write-Host "+===============================================+"
        Write-Host "|            Dateitypen auswählen              |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    # Klare Überschrift
    Write-Host ""
    Write-Host "Verfügbare Dateitypen zum Bereinigen:" -ForegroundColor Cyan 
    Write-Host ""
    
    # Nummerierte Liste erstellen - mit konsistenter Formatierung (4 Leerzeichen)
    for ($i = 0; $i -lt $folders.Count; $i++) {
        $folderName = $folders[$i]
        $itemCount = (Get-ChildItem "$tempPath\$folderName" -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host "    $($i+1)       [folder]    $folderName - $itemCount Dateien"
    }
    
    # Navigation (konsistent mit PiM-Manager-Format)
    Write-Host ""
    Write-Host "    A       [all]       Alle auswählen"
    Write-Host "    B       [back]      Zurück"
    
    # Eingabe mit klarer Aufforderung
    Write-Host ""
    $choice = Read-Host "Option wählen oder Nummern durch Komma getrennt (z.B. '1,3')"
    
    # "B" als explizite Option für "Zurück"
    if ($choice -match "^[Bb]$") {
        Log "Benutzer hat Auswahl abgebrochen" "Info"
        return "B"  # Spezielle Markierung für "Zurück"
    }
    
    if ([string]::IsNullOrWhiteSpace($choice)) {
        # Leere Eingabe - zurück zum Menü
        Log "Keine Eingabe - Zurück zum Hauptmenü" "Info"
        return "B"
    }
    
    if ($choice -match "^[Aa]$") {
        # Alle auswählen
        Log "Benutzer hat alle Dateitypen ausgewählt" "Info"
        return $folders
    }
    
    # Mehrfachauswahl verarbeiten
    $selectedIndices = $choice -split ',' | ForEach-Object { $_.Trim() }
    
    foreach ($index in $selectedIndices) {
        if ($index -match "^\d+$") {
            $i = [int]$index - 1
            if ($i -ge 0 -and $i -lt $folders.Count) {
                $selections += $folders[$i]
                Log "Dateityp ausgewählt: $($folders[$i])" "Info"
            }
        }
    }
    
    return $selections
}

# Zeitspanne zur Auswahl anbieten
function SelectTimeframe {
    cls
    $hasUX = Get-Command ShowTitle -EA SilentlyContinue
    if ($hasUX) {
        ShowTitle "Zeitraum auswählen" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|             Zeitraum auswählen               |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    Write-Host "`nWelche Dateien sollen bereinigt werden?`n" -ForegroundColor Cyan
    Write-Host "    1       [option]    Aus der letzten Stunde"
    Write-Host "    2       [option]    Aus den letzten 24 Stunden"
    Write-Host "    3       [option]    Aus der letzten Woche"
    Write-Host "    4       [option]    Alle"
    
    # Navigation (konsistent mit PiM-Manager-Format)
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    
    Write-Host ""
    $choice = Read-Host "Option wählen"
    
    # Konsistentes Zurück-Verhalten
    if ($choice -match "^[Bb]$") {
        Log "Benutzer hat Zurück gewählt" "Info"
        return $null
    }
    
    # WICHTIG: Bei der Option "Alle" geben wir jetzt das aktuelle Datum zurück
    # damit der Vergleich mit -le (less or equal) alle Dateien einschließt
    switch ($choice) {
        "1" { return (Get-Date).AddHours(-1) }
        "2" { return (Get-Date).AddHours(-24) }
        "3" { return (Get-Date).AddDays(-7) }
        "4" { return [DateTime]::MinValue } # Bleibt für "Alle" bei MinValue
        default { 
            Write-Host "`nUngültige Eingabe." -ForegroundColor Red 
            Start-Sleep -Seconds 2
            return SelectTimeframe  # Erneut versuchen
        }
    }
}

# Bereinigung durchführen
function PerformCleanup($selectedFolders, $cutoffDate) {
    if ($selectedFolders.Count -eq 0 -or $null -eq $cutoffDate) {
        Log "Keine Bereinigung durchgeführt" "Warning"
        return
    }
    
    Log "Beginne Bereinigung..." "Info"
    $totalDeleted = 0
    $totalSize = 0
    
    # Debug-Info: Zeige Cutoff-Datum an, um Zeitvergleich nachzuvollziehen
    Log "Cutoff-Datum für Löschung: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
    
    foreach ($folder in $selectedFolders) {
        $folderPath = "$tempPath\$folder"
        
        if (-not (Test-Path $folderPath)) {
            Log "Verzeichnis nicht gefunden: $folderPath" "Warning"
            continue
        }
        
        Log "Suche zu löschende Dateien in: $folder" "Info"
        
        # Alle Dateien auflisten und Debug-Info ausgeben
        $allFiles = Get-ChildItem $folderPath -Recurse -File
        Log "Gesamt Dateien gefunden: $($allFiles.Count)" "Info"
        
        if ($allFiles.Count -gt 0) {
            $oldestFile = $allFiles | Sort-Object LastWriteTime | Select-Object -First 1
            $newestFile = $allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            
            Log "Älteste Datei: $($oldestFile.Name) - $($oldestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
            Log "Neueste Datei: $($newestFile.Name) - $($newestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
        }
        
        # Spezialfall für Backups: Wenn im Backup-Ordner und Option "Alle" gewählt,
        # dann komplette Backup-Verzeichnisse löschen anstatt nur einzelne Dateien
        if ($folder -eq "backups" -and $cutoffDate -eq [DateTime]::MinValue) {
            $backupFolders = Get-ChildItem $folderPath -Directory
            $folderFiles = $allFiles.Count  # Für die Berichterstattung
            $folderSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
            
            Log "Löschung von Backup-Ordnern: $($backupFolders.Count) Ordner" "Info"
            
            # Fortschritt für Backup-Ordner
            $progress = 0
            $activity = "Bereinige Backup-Ordner"
            
            foreach ($backupFolder in $backupFolders) {
                try {
                    Log "Lösche Backup-Ordner: $($backupFolder.FullName)" "Info"
                    Remove-Item $backupFolder.FullName -Recurse -Force
                    
                    # Fortschritt anzeigen
                    $progress++
                    $percent = [math]::Round(($progress / $backupFolders.Count) * 100)
                    Write-Progress -Activity $activity -Status "$percent% abgeschlossen" -PercentComplete $percent
                }
                catch {
                    Log "Fehler beim Löschen des Backup-Ordners: $($backupFolder.FullName) - $_" "Error"
                }
            }
            
            Write-Progress -Activity $activity -Completed
            $totalDeleted += $folderFiles
            $totalSize += $folderSize
        }
        else {
            # Standardverhalten für andere Ordner: Dateien für Löschung auswählen
            $filesToDelete = if ($cutoffDate -eq [DateTime]::MinValue) {
                # Bei 'Alle' auswählen einfach alle Dateien zurückgeben
                $allFiles
            } else {
                # Sonst normal nach Datum filtern
                $allFiles | Where-Object { $_.LastWriteTime -le $cutoffDate }
            }
            
            $folderFiles = $filesToDelete.Count
            Log "Zum Löschen markierte Dateien: $folderFiles" "Info"
            
            if ($folderFiles -eq 0) {
                Log "Keine zu löschenden Dateien in: $folder" "Info"
                continue
            }
            
            # Größe berechnen
            $folderSize = ($filesToDelete | Measure-Object -Property Length -Sum).Sum
            $totalSize += $folderSize
            
            # Lösch-Fortschritt
            $progress = 0
            $activity = "Bereinige $folder"
            
            foreach ($file in $filesToDelete) {
                try {
                    # Ignoriere Dateien, die gerade in Benutzung sind (z.B. aktuelle Logs)
                    $inUse = $false
                    try {
                        $fileStream = [System.IO.File]::Open($file.FullName, 
                                      [System.IO.FileMode]::Open, 
                                      [System.IO.FileAccess]::ReadWrite, 
                                      [System.IO.FileShare]::None)
                        $fileStream.Close()
                        $fileStream.Dispose()
                    }
                    catch {
                        $inUse = $true
                        Log "Datei in Benutzung, wird übersprungen: $($file.FullName)" "Warning"
                    }
                    
                    if (-not $inUse) {
                        Remove-Item $file.FullName -Force
                        $totalDeleted++
                    }
                    
                    # Fortschritt anzeigen
                    $progress++
                    $percent = [math]::Round(($progress / $folderFiles) * 100)
                    Write-Progress -Activity $activity -Status "$percent% abgeschlossen" -PercentComplete $percent
                }
                catch {
                    Log "Fehler beim Löschen: $($file.FullName) - $_" "Error"
                }
            }
            
            Write-Progress -Activity $activity -Completed
            
            # Leere Verzeichnisse entfernen (falls keine Dateien oder Unterverzeichnisse)
            Get-ChildItem $folderPath -Directory -Recurse | 
                Where-Object { 
                    (Get-ChildItem $_.FullName -Recurse -File).Count -eq 0 -and
                    (Get-ChildItem $_.FullName -Directory).Count -eq 0
                } |
                ForEach-Object {
                    try {
                        Log "Entferne leeres Verzeichnis: $($_.FullName)" "Info"
                        Remove-Item $_.FullName -Force
                    }
                    catch {
                        Log "Fehler beim Entfernen des Verzeichnisses: $($_.FullName) - $_" "Error"
                    }
                }
        }
        
        # Ausgabe pro Ordner
        $sizeInMB = [math]::Round($folderSize / 1MB, 2)
        Log "Bereinigt in '$folder': $folderFiles Dateien ($sizeInMB MB)" "Info"
    }
    
    # Ergebnisanzeige mit konsistenter Formatierung
    cls
    $hasUX = Get-Command ShowTitle -EA SilentlyContinue
    if ($hasUX) {
        ShowTitle "Bereinigung abgeschlossen" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|          Bereinigung abgeschlossen           |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    # Gesamtausgabe
    $totalSizeInMB = [math]::Round($totalSize / 1MB, 2)
    Log "Bereinigung abgeschlossen:" "Info"
    
    Write-Host "`nErgebnis der Bereinigung:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Gelöschte Dateien:         $totalDeleted"
    Write-Host "    Freigegebener Speicherplatz: $totalSizeInMB MB"
    
    # Konsistentes UX mit Zurück-Option
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host ""
    $choice = Read-Host "Option wählen"
    
    # Zurück zum Hauptmenü ohne ShowMainMenu-Aufruf
    # Die Rückkehr zum Startmenü wird von der aufrufenden Funktion übernommen
    return
}

# Hauptmenü anzeigen
function ShowMainMenu {
    # UX-Funktion prüfen
    $hasUX = Get-Command ShowScriptMenu -EA SilentlyContinue
    
    # Menüoptionen
    $opts = @{
        "1" = @{
            Display = "[option]    Temporäre Dateien bereinigen"
            Action = { StartCleanup }
        }
        "2" = @{
            Display = "[option]    Statistik anzeigen"
            Action = { ShowStatistics }
        }
    }
    
    if ($hasUX) {
        # UX-Modul nutzen
        try {
            $result = ShowScriptMenu -title "PiM-Bereinigung" -mode "Admin-Modus" -options $opts -enableBack -enableExit
            
            # Die Funktion sollte ein "B" zurückgeben, wenn der Benutzer zurück möchte
            if ($result -eq "B") {
                return
            }
        }
        catch {
            Log "Fehler bei Menüanzeige: $_" "Error"
            # Fallback zur einfachen Methode, wenn etwas schiefgeht
            FallbackMenu $opts
        }
    } else {
        # Fallback-Menü
        FallbackMenu $opts
    }
}

# Fallback-Menü für den Fall, dass UX-Modul nicht verfügbar oder fehlerhaft ist
function FallbackMenu($options) {
    cls
    Write-Host "+===============================================+"
    Write-Host "|             PiM-Bereinigung                  |"
    Write-Host "|             (Admin-Modus)                    |"
    Write-Host "+===============================================+"
    
    # Optionen anzeigen
    foreach ($key in ($options.Keys | Sort-Object)) {
        Write-Host "    $key       $($options[$key].Display)"
    }
    
    # Navigation
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host "    X       [exit]      Beenden"
    
    # Eingabe
    Write-Host ""
    $choice = Read-Host "Option wählen"
    
    if ($choice -match "^[Xx]$") {
        # Statt exit nutzen wir return, um sauberes Beenden zu ermöglichen
        # Der Aufrufstack kümmert sich dann um den Rest
        Log "Beende Skript auf Benutzerwunsch" "Info"
        return
    } elseif ($choice -match "^[Bb]$") {
        return
    } elseif ($options.ContainsKey($choice)) {
        & $options[$choice].Action
    } else {
        Write-Host "Ungültige Option." -ForegroundColor Red
        Start-Sleep -Seconds 2
        FallbackMenu $options
    }
}

# Bereinigungsprozess starten
function StartCleanup {
    # Zuerst prüfen, ob Statistiken angezeigt werden sollen
    cls
    $hasUX = Get-Command ShowTitle -EA SilentlyContinue
    if ($hasUX) {
        ShowTitle "Temp-Bereinigung" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|            Temp-Bereinigung                  |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    Write-Host "`nWählen Sie eine Option:`n" -ForegroundColor Cyan
    Write-Host "    1       [option]    Dateien bereinigen"
    Write-Host "    2       [option]    Statistik anzeigen"
    
    # Navigation (konsistent mit PiM-Manager-Format)
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host "    X       [exit]      Beenden"
    
    Write-Host ""
    $choice = Read-Host "Option wählen"
    
    if ($choice -match "^[Xx]$") {
        # Beenden ohne Fehlermeldung
        Log "Benutzer hat Beenden gewählt" "Info"
        return
    }
    elseif ($choice -match "^[Bb]$") {
        # Zurück zum aufrufenden Menü
        Log "Benutzer hat Zurück gewählt" "Info"
        return
    }
    else {
        switch ($choice) {
            "1" { ContinueCleanup }
            "2" { ShowStatistics }
            default { 
                Write-Host "`nUngültige Eingabe." -ForegroundColor Red 
                Start-Sleep -Seconds 2
                StartCleanup
            }
        }
    }
}

# Eigentliche Bereinigungslogik (ausgelagert aus StartCleanup)
function ContinueCleanup {
    # Temp-Verzeichnis prüfen
    if (-not (Test-Path $tempPath)) {
        Log "Temp-Verzeichnis nicht gefunden: $tempPath" "Error"
        mkdir $tempPath -Force >$null
        Log "Temp-Verzeichnis erstellt: $tempPath" "Info"
        
        Write-Host "`nEs gibt noch keine temporären Dateien zu bereinigen." -ForegroundColor Yellow
        Write-Host "Taste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        StartCleanup
        return
    }
    
    # Dateitypen auswählen
    $selectedFolders = SelectFileTypes
    
    # Prüfen auf Zurück-Signal (B)
    if ($selectedFolders -eq "B") {
        Log "Zurück zum Hauptmenü von Dateitypen-Auswahl" "Info"
        StartCleanup
        return
    }
    
    if ($selectedFolders.Count -eq 0) {
        Log "Keine Dateitypen ausgewählt" "Warning"
        StartCleanup
        return
    }
    
    # Zeitrahmen auswählen
    $cutoffDate = SelectTimeframe
    
    if ($null -eq $cutoffDate) {
        Log "Kein Zeitrahmen ausgewählt" "Warning"
        StartCleanup
        return
    }
    
    # Bereinigung durchführen
    PerformCleanup $selectedFolders $cutoffDate
    
    # Nach der Bereinigung zurück zum Hauptmenü
    StartCleanup
}

# Statistik über temporäre Dateien anzeigen
function ShowStatistics {
    cls
    $hasUX = Get-Command ShowTitle -EA SilentlyContinue
    if ($hasUX) {
        ShowTitle "Temp-Statistik" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|             Temp-Statistik                   |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    # Temp-Verzeichnis prüfen
    if (-not (Test-Path $tempPath)) {
        Log "Temp-Verzeichnis nicht gefunden: $tempPath" "Warning"
        mkdir $tempPath -Force >$null
        Log "Temp-Verzeichnis erstellt: $tempPath" "Info"
        
        Write-Host "`nEs gibt noch keine temporären Dateien zu analysieren." -ForegroundColor Yellow
        
        # Konsistentes UX mit Zurück-Option
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host ""
        $choice = Read-Host "Option wählen"
        
        return  # Direkt zurück ohne ShowMainMenu
    }
    
    $folders = GetTempSubfolders
    
    if ($folders.Count -eq 0) {
        Write-Host "`nKeine Unterordner im temp-Verzeichnis gefunden." -ForegroundColor Yellow
        
        # Konsistentes UX mit Zurück-Option
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host ""
        $choice = Read-Host "Option wählen"
        
        return  # Direkt zurück ohne ShowMainMenu
    }
    
    Write-Host "`nStatistik der temporären Dateien:" -ForegroundColor Cyan
    
    $totalFiles = 0
    $totalSize = 0
    
    # Tabellenkopf
    Write-Host "`n  Ordner                    Dateien        Größe        Älteste Datei"
    Write-Host "  --------------------------------------------------------------------"
    
    foreach ($folder in $folders) {
        $folderPath = "$tempPath\$folder"
        
        if (-not (Test-Path $folderPath)) {
            continue
        }
        
        $files = Get-ChildItem $folderPath -Recurse -File
        $fileCount = $files.Count
        $totalFiles += $fileCount
        
        $size = ($files | Measure-Object -Property Length -Sum).Sum
        $totalSize += $size
        $sizeInMB = [math]::Round($size / 1MB, 2)
        
        # Älteste Datei finden
        $oldestFile = $files | Sort-Object LastWriteTime | Select-Object -First 1
        $oldestDate = if ($oldestFile) { $oldestFile.LastWriteTime.ToString("yyyy-MM-dd") } else { "N/A" }
        
        # Ausgabe
        Write-Host ("  {0,-25} {1,7} {2,12} MB   {3,-10}" -f $folder, $fileCount, $sizeInMB, $oldestDate)
    }
    
    # Gesamtstatistik
    $totalSizeInMB = [math]::Round($totalSize / 1MB, 2)
    Write-Host "  --------------------------------------------------------------------"
    Write-Host ("  {0,-25} {1,7} {2,12} MB" -f "Gesamt:", $totalFiles, $totalSizeInMB)
    
    # Konsistentes UX mit Zurück-Option
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host ""
    $choice = Read-Host "Option wählen"
    
    # Zurück zum Startmenü
    StartCleanup
}

# Skriptstart
Log "PiM-Bereinigung gestartet"

# Direkt den Bereinigungsprozess starten, ohne Hauptmenü
StartCleanup

Log "PiM-Bereinigung beendet"