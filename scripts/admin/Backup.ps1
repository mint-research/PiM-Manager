# Backup.ps1 - Backup und Wiederherstellung für PiM-Manager
# DisplayName: Backup & Wiederherstellung

# Pfadberechnung (zwei Ebenen nach oben von scripts\admin)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cfgPath = "$root\config"
$tempPath = "$root\temp"
$bkpPath = "$tempPath\backups"
$gitIgnore = "$root\.gitignore"

# UX-Modul laden
$modPath = "$root\modules\ux.psm1"
if (Test-Path $modPath) {
    try { Import-Module $modPath -Force -EA Stop }
    catch { Write-Host "UX-Fehler: $_" -ForegroundColor Red }
}

# Logging-Funktion
function Log($m, $t = "Info") {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $s = Split-Path -Leaf $PSCommandPath
    $logLine = "[$ts] [$s] [$t] $m"
    
    switch ($t) {
        "Error" { Write-Host $logLine -ForegroundColor Red }
        "Warning" { Write-Host $logLine -ForegroundColor Yellow }
        default { Write-Host $logLine -ForegroundColor Gray }
    }
}

# GitIgnore-Regeln parsen
function ParseGI {
    if (!(Test-Path $gitIgnore)) {
        Log "GitIgnore nicht gefunden: $gitIgnore" "Warning"
        return @()
    }

    $rules = @()
    Get-Content $gitIgnore | ? { ![string]::IsNullOrWhiteSpace($_) -and !$_.StartsWith('#') } | % {
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
function ShouldSkip($p, $r) {
    # Relativen Pfad bestimmen
    $rp = $p.Replace($root, "").TrimStart("\")
    
    # Standardmäßig nicht ignorieren
    $s = $false
    
    foreach ($x in $r) {
        $pat = $x.Rule
        $inc = $x.Include
        
        # Effizientere Struktur mit Switch
        switch -Regex ($pat) {
            '.*\/\*\*$' { # Endet mit /**
                $dp = $pat.Substring(0, $pat.Length - 3)
                if ($rp.StartsWith($dp) -or $rp -eq $dp.TrimEnd('/')) { 
                    $s = !$inc
                    return $s
                }
            }
            '\/$' { # Endet mit /
                $dp = $pat.TrimEnd("/")
                if ($rp.StartsWith("$dp\") -or $rp -eq $dp) { 
                    $s = !$inc
                    return $s
                }
            }
            '\/\*$' { # Endet mit /*
                $dp = $pat.Substring(0, $pat.Length - 2)
                $parent = Split-Path -Parent $rp
                if ($parent -eq $dp.TrimEnd('/')) { 
                    $s = !$inc
                    return $s
                }
            }
            '\*' { # Enthält *
                $regex = "^" + [regex]::Escape($pat).Replace("\*", ".*") + "$"
                if ($rp -match $regex) { 
                    $s = !$inc
                    return $s
                }
            }
            default { # Exakte Übereinstimmung
                if ($rp -eq $pat -or $rp.StartsWith("$pat\")) { 
                    $s = !$inc
                    return $s
                }
            }
        }
    }
    
    return $s
}

# Backup erstellen
function BkpCreate {
    Log "Backup wird vorbereitet..."
    
    # Zeitstempel für Backup-Verzeichnis
    $ts = Get-Date -Format "yyyy-MM-dd-HH-mm"
    $bkpName = "backup-$ts"
    $curBkpPath = "$bkpPath\$bkpName"
    
    # Temp-Verzeichnis prüfen/erstellen
    if (!(Test-Path $tempPath)) {
        md $tempPath -Force >$null
        Log "Temp-Verzeichnis erstellt: $tempPath"
    }
    
    # Backups-Verzeichnis prüfen/erstellen
    if (!(Test-Path $bkpPath)) {
        md $bkpPath -Force >$null
        Log "Backups-Verzeichnis erstellt: $bkpPath"
    }
    
    # Backup-Verzeichnis erstellen
    md $curBkpPath -Force >$null
    Log "Backup-Verzeichnis erstellt: $curBkpPath"
    
    # GitIgnore-Regeln laden
    $rules = ParseGI
    Log "GitIgnore-Regeln geladen: $($rules.Count) Einträge"
    
    # Alle Dateien und Verzeichnisse im Root-Verzeichnis
    $allItems = Get-ChildItem $root -Recurse -File
    
    # Zu sichernde Dateien ermitteln
    $bkpItems = $allItems | ? {
        # Backup-Verzeichnis selbst ausschließen
        if ($_.FullName.StartsWith($bkpPath) -or $_.FullName.StartsWith("$tempPath\backups")) { return $false }
        # Nach GitIgnore-Regeln filtern
        return !(ShouldSkip $_.FullName $rules)
    }
    
    $totFiles = $bkpItems.Count
    Log "Zu sichernde Dateien: $totFiles"
    
    # Fortschrittsanzeige vorbereiten
    $progress = 0
    $act = "Backup erstellen"
    
    foreach ($item in $bkpItems) {
        # Relativen Pfad bestimmen
        $relPath = $item.FullName.Replace($root, "").TrimStart("\")
        $tgtPath = "$curBkpPath\$relPath"
        
        # Zielverzeichnis erstellen
        $tgtDir = Split-Path -Parent $tgtPath
        if (!(Test-Path $tgtDir)) {
            md $tgtDir -Force >$null
        }
        
        # Datei kopieren
        Copy-Item -Path $item.FullName -Destination $tgtPath -Force
        
        # Fortschritt anzeigen
        $progress++
        $percent = [math]::Round(($progress / $totFiles) * 100)
        Write-Progress -Activity $act -Status "$percent% abgeschlossen" -PercentComplete $percent -CurrentOperation $relPath
    }
    
    Write-Progress -Activity $act -Completed
    
    # Erfolgsmeldung
    Log "Backup abgeschlossen: $curBkpPath" "Info"
    Write-Host "`nBackup wurde erfolgreich erstellt:" -ForegroundColor Green
    Write-Host "Speicherort: $curBkpPath" -ForegroundColor Cyan
    Write-Host "Gesicherte Dateien: $totFiles" -ForegroundColor Cyan
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    BkpMenu
}

# Backup wiederherstellen
function BkpRestore {
    # Prüfen auf vorhandene Backups
    if (!(Test-Path $bkpPath)) {
        Log "Keine Backups gefunden" "Warning"
        Write-Host "`nEs wurden keine Backups gefunden.`nErstellen Sie zuerst ein Backup." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpMenu
        return
    }
    
    # Verfügbare Backups suchen
    $bkps = Get-ChildItem $bkpPath -Directory | ? { $_.Name -match "^backup-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$" } | Sort Name -Descending
    
    if ($bkps.Count -eq 0) {
        Log "Keine Backups gefunden" "Warning"
        Write-Host "`nEs wurden keine Backups gefunden.`nErstellen Sie zuerst ein Backup." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpMenu
        return
    }
    
    # Backups anzeigen
    cls
    $hasUX = Get-Command Title -EA SilentlyContinue
    if ($hasUX) {
        Title "Backup wiederherstellen" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|          Backup wiederherstellen             |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    Write-Host "`nVerfügbare Backups:`n" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $bkps.Count; $i++) {
        $b = $bkps[$i]
        $date = $b.Name.Substring(7)  # "backup-" entfernen
        $files = (Get-ChildItem $b.FullName -Recurse -File).Count
        Write-Host "  $($i+1). $date - $files Dateien"
    }
    
    # Auswahl
    Write-Host "`nGeben Sie die Nummer des wiederherzustellenden Backups ein"
    Write-Host "oder 'B' für zurück zum Hauptmenü."
    $ch = Read-Host "`nAuswahl"
    
    if ($ch -match "^[Bb]$") {
        BkpMenu
        return
    }
    
    # Numerischen Wert validieren
    if (!($ch -match "^\d+$")) {
        Log "Ungültige Eingabe: $ch" "Warning"
        Write-Host "`nUngültige Eingabe. Bitte eine Zahl eingeben." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpRestore
        return
    }
    
    $idx = [int]$ch - 1
    
    # Index-Bereichsprüfung
    if ($idx -lt 0 -or $idx -ge $bkps.Count) {
        Log "Ungültiger Index: $idx" "Warning"
        Write-Host "`nUngültige Auswahl. Bitte wählen Sie eine Zahl zwischen 1 und $($bkps.Count)." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpRestore
        return
    }
    
    # Bestätigung
    $selBkp = $bkps[$idx]
    $bkpDate = $selBkp.Name.Substring(7)
    Write-Host "`nSie haben folgendes Backup ausgewählt:"
    Write-Host "Datum: $bkpDate" -ForegroundColor Cyan
    Write-Host "Pfad: $($selBkp.FullName)" -ForegroundColor Cyan
    
    $confirm = Read-Host "`nMöchten Sie fortfahren? (j/n)"
    
    if ($confirm -ne "j") {
        Log "Wiederherstellung abgebrochen" "Warning"
        Write-Host "`nWiederherstellung abgebrochen." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpMenu
        return
    }
    
    # Wiederherstellung durchführen
    Log "Beginne Wiederherstellung von: $($selBkp.FullName)" "Info"
    
    # Alle Dateien im Backup
    $bkpFiles = Get-ChildItem $selBkp.FullName -Recurse -File
    $totFiles = $bkpFiles.Count
    $progress = 0
    $act = "Backup wiederherstellen"
    
    foreach ($file in $bkpFiles) {
        # Relativen Pfad im Backup bestimmen
        $relPath = $file.FullName.Replace($selBkp.FullName, "").TrimStart("\")
        $tgtPath = "$root\$relPath"
        
        # Zielverzeichnis erstellen
        $tgtDir = Split-Path -Parent $tgtPath
        if (!(Test-Path $tgtDir)) {
            md $tgtDir -Force >$null
        }
        
        # Datei kopieren
        Copy-Item -Path $file.FullName -Destination $tgtPath -Force
        
        # Fortschritt anzeigen
        $progress++
        $percent = [math]::Round(($progress / $totFiles) * 100)
        Write-Progress -Activity $act -Status "$percent% abgeschlossen" -PercentComplete $percent -CurrentOperation $relPath
    }
    
    Write-Progress -Activity $act -Completed
    
    # Erfolgsmeldung
    Log "Wiederherstellung abgeschlossen" "Info"
    Write-Host "`nWiederherstellung wurde erfolgreich abgeschlossen!" -ForegroundColor Green
    Write-Host "Wiederhergestellte Dateien: $totFiles" -ForegroundColor Cyan
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    BkpMenu
}

# Backup-Verwaltung
function BkpManage {
    # Prüfen auf vorhandene Backups
    if (!(Test-Path $bkpPath)) {
        Log "Keine Backups gefunden" "Warning"
        Write-Host "`nEs wurden keine Backups gefunden." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpMenu
        return
    }
    
    # Verfügbare Backups suchen
    $bkps = Get-ChildItem $bkpPath -Directory | ? { $_.Name -match "^backup-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$" } | Sort Name -Descending
    
    if ($bkps.Count -eq 0) {
        Log "Keine Backups gefunden" "Warning"
        Write-Host "`nEs wurden keine Backups gefunden." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpMenu
        return
    }
    
    # Backups anzeigen
    cls
    $hasUX = Get-Command Title -EA SilentlyContinue
    if ($hasUX) {
        Title "Backup-Verwaltung" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|            Backup-Verwaltung                 |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    Write-Host "`nVerfügbare Backups:`n" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $bkps.Count; $i++) {
        $b = $bkps[$i]
        $date = $b.Name.Substring(7)  # "backup-" entfernen
        $files = (Get-ChildItem $b.FullName -Recurse -File).Count
        $size = "{0:N2} MB" -f ((Get-ChildItem $b.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB)
        Write-Host "  $($i+1). $date - $files Dateien - $size"
    }
    
    # Auswahl
    Write-Host "`nGeben Sie die Nummer des zu löschenden Backups ein"
    Write-Host "oder 'A' um alle Backups zu löschen,"
    Write-Host "oder 'B' für zurück zum Hauptmenü."
    $ch = Read-Host "`nAuswahl"
    
    if ($ch -match "^[Bb]$") {
        BkpMenu
        return
    }
    
    if ($ch -match "^[Aa]$") {
        # Bestätigung für Löschung aller Backups
        Write-Host "`nSind Sie sicher, dass Sie ALLE Backups löschen möchten?" -ForegroundColor Red
        Write-Host "Diese Aktion kann nicht rückgängig gemacht werden!" -ForegroundColor Red
        $conf = Read-Host "Bestätigen Sie mit 'ja'"
        
        if ($conf -eq "ja") {
            Log "Lösche alle Backups" "Warning"
            
            foreach ($b in $bkps) {
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
        BkpMenu
        return
    }
    
    # Numerischen Wert validieren
    if (!($ch -match "^\d+$")) {
        Log "Ungültige Eingabe: $ch" "Warning"
        Write-Host "`nUngültige Eingabe. Bitte eine Zahl eingeben." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpManage
        return
    }
    
    $idx = [int]$ch - 1
    
    # Index-Bereichsprüfung
    if ($idx -lt 0 -or $idx -ge $bkps.Count) {
        Log "Ungültiger Index: $idx" "Warning"
        Write-Host "`nUngültige Auswahl. Bitte wählen Sie eine Zahl zwischen 1 und $($bkps.Count)." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpManage
        return
    }
    
    # Bestätigung
    $selBkp = $bkps[$idx]
    $bkpDate = $selBkp.Name.Substring(7)
    Write-Host "`nSie haben folgendes Backup ausgewählt:"
    Write-Host "Datum: $bkpDate" -ForegroundColor Cyan
    Write-Host "Pfad: $($selBkp.FullName)" -ForegroundColor Cyan
    
    Write-Host "`nMöchten Sie dieses Backup löschen?" -ForegroundColor Yellow
    $conf = Read-Host "Bestätigen Sie mit 'j'"
    
    if ($conf -eq "j") {
        Log "Lösche Backup: $($selBkp.Name)" "Warning"
        Remove-Item $selBkp.FullName -Recurse -Force
        Write-Host "`nBackup wurde gelöscht." -ForegroundColor Green
    } else {
        Write-Host "`nLöschung abgebrochen." -ForegroundColor Yellow
    }
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    BkpMenu
}

# Hauptmenü anzeigen
function BkpMenu {
    # UX-Funktion prüfen
    $hasUX = Get-Command SMenu -EA SilentlyContinue
    
    # Menüoptionen
    $opts = @{
        "1" = @{
            Display = "[option]    Backup erstellen"
            Action = { BkpCreate }
        }
        "2" = @{
            Display = "[option]    Backup wiederherstellen"
            Action = { BkpRestore }
        }
        "3" = @{
            Display = "[option]    Backup-Verwaltung"
            Action = { BkpManage }
        }
    }
    
    if ($hasUX) {
        # UX-Modul nutzen
        $result = SMenu -t "Backup-Manager" -m "Admin-Modus" -opts $opts -back -exit
        
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
        foreach ($k in ($opts.Keys | Sort)) {
            Write-Host "    $k       $($opts[$k].Display)"
        }
        
        # Navigation
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
        # Eingabe
        Write-Host ""
        $ch = Read-Host "Option wählen"
        
        if ($ch -match "^[Xx]$") {
            Write-Host "PiM-Manager wird beendet..." -ForegroundColor Yellow
            exit
        } elseif ($ch -match "^[Bb]$") {
            return
        } elseif ($opts.ContainsKey($ch)) {
            & $opts[$ch].Action
        } else {
            Write-Host "Ungültige Option." -ForegroundColor Red
            Start-Sleep -Seconds 2
            BkpMenu
        }
    }
}

# Skriptstart
Log "Backup-Manager gestartet"
BkpMenu
Log "Backup-Manager beendet"