# cleanup-pim.ps1 - Temp-Dateien bereinigen
# DisplayName: Temporäre Dateien bereinigen

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
    Get-ChildItem $tempPath -Directory | Select -ExpandProperty Name
}

# Dateitypen auswählen
function SelType {
    $dirs = GetDirs
    
    # Wenn keine Verzeichnisse vorhanden sind, aber temp-Verzeichnis existiert
    if ($dirs.Count -eq 0 -and (Test-Path $tempPath)) { 
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
    
    if (Get-Command Title -EA SilentlyContinue) {
        try { Title "Dateitypen auswählen" "Admin-Modus" }
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
    $ch = Read-Host "Option wählen oder Nummern durch Komma getrennt (z.B. '1,3')"
    
    if ($ch -match "^[Bb]$") {
        Log "Auswahl abgebrochen" "Info"
        return "B"
    }
    
    if ([string]::IsNullOrWhiteSpace($ch)) {
        Log "Keine Eingabe - Zurück" "Info"
        return "B"
    }
    
    if ($ch -match "^[Aa]$") {
        Log "Alle Typen ausgewählt" "Info"
        return $dirs
    }
    
    # Mehrfachauswahl
    $ch -split ',' | % { $_.Trim() } | ? { $_ -match "^\d+$" } | % {
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
    
    if (Get-Command Title -EA SilentlyContinue) {
        Title "Zeitraum auswählen" "Admin-Modus"
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
function Clean($dirs, $cutoffDate) {
    if ($dirs.Count -eq 0 -or $null -eq $cutoffDate) {
        Log "Keine Bereinigung durchgeführt" "Warning"
        return
    }
    
    Log "Beginne Bereinigung..." "Info"
    $totFiles = 0
    $totSize = 0
    
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
            $oldest = $files | Sort LastWriteTime | Select -First 1
            $newest = $files | Sort LastWriteTime -Descending | Select -First 1
            
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
            $totFiles += $fCount
            $totSize += $fSize
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
            $totSize += $fSize
            
            # Lösch-Fortschritt
            $prog = 0
            $act = "Bereinige $d"
            
            foreach ($f in $toDel) {
                try {
                    # Prüfe Dateizugriff
                    $skip = $false
                    try {
                        $fs = [IO.File]::Open($f.FullName, 
                              [IO.FileMode]::Open, 
                              [IO.FileAccess]::ReadWrite, 
                              [IO.FileShare]::None)
                        $fs.Close()
                        $fs.Dispose()
                    }
                    catch {
                        $skip = $true
                        Log "In Benutzung: $($f.FullName)" "Warning"
                    }
                    
                    if (!$skip) {
                        Remove-Item $f.FullName -Force
                        $totFiles++
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
    
    if (Get-Command Title -EA SilentlyContinue) {
        Title "Bereinigung abgeschlossen" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|          Bereinigung abgeschlossen           |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    # Gesamtausgabe
    $totalMB = [math]::Round($totSize / 1MB, 2)
    Log "Bereinigung abgeschlossen:" "Info"
    
    Write-Host "`nErgebnis der Bereinigung:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Gelöschte Dateien:         $totFiles"
    Write-Host "    Freigegebener Speicherplatz: $totalMB MB"
    
    # Navigation
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host ""
    Read-Host "Option wählen"
    
    return
}

# Statistik anzeigen
function Stats {
    cls
    
    if (Get-Command Title -EA SilentlyContinue) {
        Title "Temp-Statistik" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|             Temp-Statistik                   |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    # Temp-Ordner prüfen
    if (!(Test-Path $tempPath)) {
        Log "Temp-Verzeichnis nicht gefunden: $tempPath" "Warning"
        md $tempPath -Force >$null
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
    
    Write-Host