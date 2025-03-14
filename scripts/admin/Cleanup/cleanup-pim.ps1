# cleanup-pim.ps1 - Temp-Dateien bereinigen (Tokenoptimiert)
# Speicherort: scripts\admin\Cleanup\
# Version: 1.0
# DisplayName: Temporäre Dateien bereinigen

<#
.SYNOPSIS
Bereinigt temporäre Dateien des PiM-Managers.
#>

# Pfadberechnung (3 Ebenen hoch für admin\Cleanup)
$root = $PSScriptRoot -match "admin\\Cleanup$" ? 
    (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) : 
    (Split-Path -Parent $PSScriptRoot)
$tempPath = "$root\temp"
$isAdmin = $true

# UX-Modul laden
$modPath = "$root\modules\ux.psm1"
if (Test-Path $modPath) {
    try { Import-Module $modPath -Force -EA Stop }
    catch { Write-Host "UX-Fehler: $_" -ForegroundColor Red }
}

# Log-Funktion
function Log($m, $t = "Info") {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $s = Split-Path -Leaf $PSCommandPath
    $l = "[$ts] [$s] [$t] $m"
    
    switch ($t) {
        "Error" { Write-Host $l -ForegroundColor Red }
        "Warning" { Write-Host $l -ForegroundColor Yellow }
        default { Write-Host $l -ForegroundColor Gray }
    }
}

# Unterordner im temp-Verzeichnis ermitteln
function GetDirs {
    if (!(Test-Path $tempPath)) { return @() }
    Get-ChildItem $tempPath -Directory | Select-Object -ExpandProperty Name
}

# Dateitypen auswählen
function SelTypes {
    $dirs = GetDirs
    
    # Wenn keine Verzeichnisse vorhanden sind, aber temp-Verzeichnis existiert
    if ($dirs.Count -eq 0 && (Test-Path $tempPath)) { 
        Log "Keine Ordner im temp-Verzeichnis" "Warning"
        Write-Host "`nEs sind keine Unterordner im temp-Verzeichnis vorhanden." -ForegroundColor Yellow
        Write-Host "Diese werden automatisch erstellt, wenn sie benötigt werden." -ForegroundColor Cyan
        
        # Navigation
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host ""
        Read-Host "Option wählen"
        
        return "B"
    }
    
    $sel = @()
    cls
    
    if (Get-Command ShowTitle -EA SilentlyContinue) {
        try { ShowTitle "Dateitypen auswählen" "Admin-Modus" }
        catch {
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
    
    # Liste der Ordner
    Write-Host ""
    Write-Host "Verfügbare Dateitypen zum Bereinigen:" -ForegroundColor Cyan 
    Write-Host ""
    
    for ($i = 0; $i -lt $dirs.Count; $i++) {
        $d = $dirs[$i]
        $cnt = (Get-ChildItem "$tempPath\$d" -Recurse -File -EA SilentlyContinue).Count
        Write-Host "    $($i+1)       [folder]    $d - $cnt Dateien"
    }
    
    # Navigation
    Write-Host ""
    Write-Host "    A       [all]       Alle auswählen"
    Write-Host "    B       [back]      Zurück"
    
    # Eingabe
    Write-Host ""
    $choice = Read-Host "Option wählen oder Nummern durch Komma getrennt (z.B. '1,3')"
    
    if ($choice -match "^[Bb]$") {
        Log "Auswahl abgebrochen" "Info"
        return "B"
    }
    
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Log "Keine Eingabe - Zurück" "Info"
        return "B"
    }
    
    if ($choice -match "^[Aa]$") {
        Log "Alle Typen ausgewählt" "Info"
        return $dirs
    }
    
    # Mehrfachauswahl
    $choice -split ',' | % { $_.Trim() } | ? { $_ -match "^\d+$" } | % {
        $i = [int]$_ - 1
        if ($i -ge 0 -and $i -lt $dirs.Count) {
            $sel += $dirs[$i]
            Log "Typ ausgewählt: $($dirs[$i])" "Info"
        }
    }
    
    return $sel
}

# Zeitraum auswählen
function SelTime {
    cls
    
    if (Get-Command ShowTitle -EA SilentlyContinue) {
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
    
    # Navigation
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    
    Write-Host ""
    $c = Read-Host "Option wählen"
    
    if ($c -match "^[Bb]$") {
        Log "Zurück gewählt" "Info"
        return $null
    }
    
    switch ($c) {
        "1" { return (Get-Date).AddHours(-1) }
        "2" { return (Get-Date).AddHours(-24) }
        "3" { return (Get-Date).AddDays(-7) }
        "4" { return [DateTime]::MinValue }
        default { 
            Write-Host "`nUngültige Eingabe." -ForegroundColor Red 
            Start-Sleep -Seconds 2
            return SelTime
        }
    }
}

# Bereinigen
function DoCleanup($dirs, $cutoffDate) {
    if ($dirs.Count -eq 0 -or $null -eq $cutoffDate) {
        Log "Keine Bereinigung durchgeführt" "Warning"
        return
    }
    
    Log "Beginne Bereinigung..." "Info"
    $totalFiles = 0
    $totalSize = 0
    
    Log "Cutoff-Datum: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
    
    foreach ($d in $dirs) {
        $path = "$tempPath\$d"
        
        if (!(Test-Path $path)) {
            Log "Ordner nicht gefunden: $path" "Warning"
            continue
        }
        
        Log "Prüfe: $d" "Info"
        
        # Dateien auflisten
        $files = Get-ChildItem $path -Recurse -File
        Log "Dateien: $($files.Count)" "Info"
        
        if ($files.Count -gt 0) {
            $oldest = $files | Sort-Object LastWriteTime | Select-Object -First 1
            $newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            
            Log "Älteste: $($oldest.Name) - $($oldest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
            Log "Neueste: $($newest.Name) - $($newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
        }
        
        # Spezialfall für Backups
        if ($d -eq "backups" -and $cutoffDate -eq [DateTime]::MinValue) {
            $bkpDirs = Get-ChildItem $path -Directory
            $fCount = $files.Count  # Für Bericht
            $fSize = ($files | Measure-Object -Property Length -Sum).Sum
            
            Log "Backup-Ordner: $($bkpDirs.Count)" "Info"
            
            # Fortschritt
            $prog = 0
            $act = "Bereinige Backup-Ordner"
            
            foreach ($bkp in $bkpDirs) {
                try {
                    Log "Lösche: $($bkp.FullName)" "Info"
                    Remove-Item $bkp.FullName -Recurse -Force
                    
                    # Fortschritt
                    $prog++
                    $pct = [math]::Round(($prog / $bkpDirs.Count) * 100)
                    Write-Progress -Activity $act -Status "$pct% abgeschlossen" -PercentComplete $pct
                }
                catch {
                    Log "Fehler: $($bkp.FullName) - $_" "Error"
                }
            }
            
            Write-Progress -Activity $act -Completed
            $totalFiles += $fCount
            $totalSize += $fSize
        }
        else {
            # Normale Ordner
            $toDel = $cutoffDate -eq [DateTime]::MinValue ?
                $files :
                ($files | ? { $_.LastWriteTime -le $cutoffDate })
            
            $fCount = $toDel.Count
            Log "Zu löschen: $fCount" "Info"
            
            if ($fCount -eq 0) {
                Log "Keine zu löschenden Dateien in: $d" "Info"
                continue
            }
            
            # Größe
            $fSize = ($toDel | Measure-Object -Property Length -Sum).Sum
            $totalSize += $fSize
            
            # Lösch-Fortschritt
            $prog = 0
            $act = "Bereinige $d"
            
            foreach ($f in $toDel) {
                try {
                    # Prüfe Dateizugriff
                    $skip = $false
                    try {
                        $fs = [System.IO.File]::Open($f.FullName, 
                              [System.IO.FileMode]::Open, 
                              [System.IO.FileAccess]::ReadWrite, 
                              [System.IO.FileShare]::None)
                        $fs.Close()
                        $fs.Dispose()
                    }
                    catch {
                        $skip = $true
                        Log "In Benutzung: $($f.FullName)" "Warning"
                    }
                    
                    if (!$skip) {
                        Remove-Item $f.FullName -Force
                        $totalFiles++
                    }
                    
                    # Fortschritt
                    $prog++
                    $pct = [math]::Round(($prog / $fCount) * 100)
                    Write-Progress -Activity $act -Status "$pct% abgeschlossen" -PercentComplete $pct
                }
                catch {
                    Log "Fehler: $($f.FullName) - $_" "Error"
                }
            }
            
            Write-Progress -Activity $act -Completed
            
            # Leere Ordner entfernen
            Get-ChildItem $path -Directory -Recurse | 
                ? { 
                    (Get-ChildItem $_.FullName -Recurse -File).Count -eq 0 -and
                    (Get-ChildItem $_.FullName -Directory).Count -eq 0
                } | % {
                    try {
                        Log "Entferne leeren Ordner: $($_.FullName)" "Info"
                        Remove-Item $_.FullName -Force
                    }
                    catch {
                        Log "Fehler: $($_.FullName) - $_" "Error"
                    }
                }
        }
        
        # Ausgabe pro Ordner
        $mb = [math]::Round($fSize / 1MB, 2)
        Log "Bereinigt '$d': $fCount Dateien ($mb MB)" "Info"
    }
    
    # Ergebnisanzeige
    cls
    
    if (Get-Command ShowTitle -EA SilentlyContinue) {
        ShowTitle "Bereinigung abgeschlossen" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|          Bereinigung abgeschlossen           |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    # Gesamtausgabe
    $totalMB = [math]::Round($totalSize / 1MB, 2)
    Log "Bereinigung abgeschlossen:" "Info"
    
    Write-Host "`nErgebnis der Bereinigung:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Gelöschte Dateien:         $totalFiles"
    Write-Host "    Freigegebener Speicherplatz: $totalMB MB"
    
    # Navigation
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host ""
    Read-Host "Option wählen"
    
    return
}

# Statistik anzeigen
function ShowStats {
    cls
    
    if (Get-Command ShowTitle -EA SilentlyContinue) {
        ShowTitle "Temp-Statistik" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|             Temp-Statistik                   |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    # Temp-Ordner prüfen
    if (!(Test-Path $tempPath)) {
        Log "Temp-Verzeichnis nicht gefunden: $tempPath" "Warning"
        mkdir $tempPath -Force >$null
        Log "Temp-Verzeichnis erstellt: $tempPath" "Info"
        
        Write-Host "`nKeine temporären Dateien zum Analysieren." -ForegroundColor Yellow
        
        # Navigation
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host ""
        Read-Host "Option wählen"
        
        return
    }
    
    $dirs = GetDirs
    
    if ($dirs.Count -eq 0) {
        Write-Host "`nKeine Unterordner im temp-Verzeichnis." -ForegroundColor Yellow
        
        # Navigation
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host ""
        Read-Host "Option wählen"
        
        return
    }
    
    Write-Host "`nStatistik der temporären Dateien:" -ForegroundColor Cyan
    
    $totalFiles = 0
    $totalSize = 0
    
    # Tabellenkopf
    Write-Host "`n  Ordner                    Dateien        Größe        Älteste Datei"
    Write-Host "  --------------------------------------------------------------------"
    
    foreach ($d in $dirs) {
        $path = "$tempPath\$d"
        
        if (!(Test-Path $path)) { continue }
        
        $files = Get-ChildItem $path -Recurse -File
        $cnt = $files.Count
        $totalFiles += $cnt
        
        $size = ($files | Measure-Object -Property Length -Sum).Sum
        $totalSize += $size
        $mb = [math]::Round($size / 1MB, 2)
        
        # Älteste Datei
        $oldest = $files | Sort-Object LastWriteTime | Select-Object -First 1
        $oldDate = $oldest ? $oldest.LastWriteTime.ToString("yyyy-MM-dd") : "N/A"
        
        # Ausgabe
        Write-Host ("  {0,-25} {1,7} {2,12} MB   {3,-10}" -f $d, $cnt, $mb, $oldDate)
    }
    
    # Gesamtstatistik
    $totalMB = [math]::Round($totalSize / 1MB, 2)
    Write-Host "  --------------------------------------------------------------------"
    Write-Host ("  {0,-25} {1,7} {2,12} MB" -f "Gesamt:", $totalFiles, $totalMB)
    
    # Navigation
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host ""
    Read-Host "Option wählen"
    
    # Zurück zum Hauptmenü
    StartCleanup
}

# Bereinigungsprozess starten
function CleanFiles {
    # Temp-Verzeichnis prüfen
    if (!(Test-Path $tempPath)) {
        Log "Temp-Verzeichnis nicht gefunden: $tempPath" "Error"
        mkdir $tempPath -Force >$null
        Log "Temp-Verzeichnis erstellt: $tempPath" "Info"
        
        Write-Host "`nKeine temporären Dateien zum Bereinigen." -ForegroundColor Yellow
        Write-Host "`nTaste drücken..."
        [Console]::ReadKey($true) >$null
        StartCleanup
        return
    }
    
    # Keine automatische Erstellung der Standardordner hier
    # Die Ordner werden erst erstellt, wenn sie benötigt werden
    # (wenn ein Backup oder Log erstellt wird)
    
    # Dateitypen auswählen
    $dirs = SelTypes
    
    # Zurück-Signal prüfen
    if ($dirs -eq "B") {
        Log "Zurück zum Hauptmenü" "Info"
        StartCleanup
        return
    }
    
    if ($dirs.Count -eq 0) {
        Log "Keine Dateitypen ausgewählt" "Warning"
        StartCleanup
        return
    }
    
    # Zeitrahmen auswählen
    $cutoff = SelTime
    
    if ($null -eq $cutoff) {
        Log "Kein Zeitrahmen ausgewählt" "Warning"
        StartCleanup
        return
    }
    
    # Bereinigung durchführen
    DoCleanup $dirs $cutoff
    
    # Zurück zum Hauptmenü
    StartCleanup
}

# Hauptmenü
function StartCleanup {
    cls
    
    if (Get-Command ShowTitle -EA SilentlyContinue) {
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
    
    # Navigation
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host "    X       [exit]      Beenden"
    
    Write-Host ""
    $c = Read-Host "Option wählen"
    
    if ($c -match "^[Xx]$") {
        Log "Benutzer hat Beenden gewählt" "Info"
        return
    }
    elseif ($c -match "^[Bb]$") {
        Log "Benutzer hat Zurück gewählt" "Info"
        return
    }
    else {
        switch ($c) {
            "1" { CleanFiles }
            "2" { ShowStats }
            default { 
                Write-Host "`nUngültige Eingabe." -ForegroundColor Red 
                Start-Sleep -Seconds 2
                StartCleanup
            }
        }
    }
}

# Skriptstart
Log "PiM-Bereinigung gestartet"
StartCleanup
Log "PiM-Bereinigung beendet"