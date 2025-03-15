# Backup.ps1 - Backup und Wiederherstellung für PiM-Manager
# DisplayName: Backup & Wiederherstellung

# Pfadmodul laden
$pathsMod = "$PSScriptRoot\..\..\modules\paths.psm1"
if (Test-Path $pathsMod) {
    try { 
        Import-Module $pathsMod -Force -EA Stop 
        $p = GetPaths $PSScriptRoot
    } catch {
        # Fallback bei Modulladefehler
        $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $p = @{
            root = $root
            cfg = "$root\config"
            temp = "$root\temp"
            errMod = "$root\modules\error.psm1"
            uxMod = "$root\modules\ux.psm1"
            cfgMod = "$root\modules\config.psm1"
            adminMod = "$root\modules\admin.psm1"
            backups = "$root\temp\backups"
        }
    }
} else {
    # Fallback ohne Pfadmodul
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $p = @{
        root = $root
        cfg = "$root\config"
        temp = "$root\temp"
        errMod = "$root\modules\error.psm1"
        uxMod = "$root\modules\ux.psm1"
        cfgMod = "$root\modules\config.psm1"
        adminMod = "$root\modules\admin.psm1"
        backups = "$root\temp\backups"
    }
}

# GitIgnore Pfad
$gitIgnore = Join-Path $p.root ".gitignore"

# Fehlermodul laden
if (Test-Path $p.errMod) {
    try { Import-Module $p.errMod -Force -EA Stop }
    catch { 
        Write-Host "Fehlermodul konnte nicht geladen werden: $_" -ForegroundColor Red 
    }
}

# UX-Modul laden
if (Test-Path $p.uxMod) {
    if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            Import-Module $p.uxMod -Force -EA Stop
        } -m "UX-Modul konnte nicht geladen werden" -t "Warning"
    } else {
        try { 
            Import-Module $p.uxMod -Force -EA Stop 
        } catch { 
            Write-Host "UX-Fehler: $_" -ForegroundColor Red 
        }
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
    if (Get-Command SafeOp -EA SilentlyContinue) {
        $useCfgMod = SafeOp {
            Import-Module $p.cfgMod -Force -EA Stop
            return $true
        } -m "Konfigurationsmodul konnte nicht geladen werden" -def $false
    } else {
        try {
            Import-Module $p.cfgMod -Force -EA Stop
            $useCfgMod = $true
        } catch {
            Write-Host "Konfigurationsmodul konnte nicht geladen werden: $_" -ForegroundColor Yellow
        }
    }
}

# Administratorrechte prüfen
$hasAdminRights = $false
if ($useAdminMod -and (Get-Command IsAdmin -EA SilentlyContinue)) {
    $hasAdminRights = IsAdmin
    
    # Wenn keine Admin-Rechte, warnen und eventuell Rechte anfordern
    if (!$hasAdminRights) {
        if (Get-Command RequireAdmin -EA SilentlyContinue) {
            RequireAdmin -message "Für Backup-Operationen werden Administratorrechte empfohlen, da einige Dateien möglicherweise geschützt sind."
            # Nach RequireAdmin Aufruf nochmals prüfen
            $hasAdminRights = IsAdmin
        } else {
            Write-Host "Warnung: Keine Administratorrechte. Einige Dateien können möglicherweise nicht gesichert werden." -ForegroundColor Yellow
        }
    }
} else {
    # Fallback-Methode zur Berechtigungsprüfung
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        $hasAdminRights = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (!$hasAdminRights) {
            Write-Host "Warnung: Keine Administratorrechte. Einige Dateien können möglicherweise nicht gesichert werden." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Fehler bei der Berechtigungsprüfung: $_" -ForegroundColor Red
        Write-Host "Es wird angenommen, dass keine Administratorrechte vorliegen." -ForegroundColor Yellow
    }
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

# Konfigurationsdateien für Backup/Restore auflisten
function GetConfigFiles {
    # Verwende das Konfigurationsmodul, wenn verfügbar
    if ($useCfgMod -and (Get-Command GetSchemas -EA SilentlyContinue)) {
        try {
            $schemas = GetSchemas
            $cfgFiles = @()
            
            foreach ($schema in $schemas) {
                $cfgFile = Join-Path $p.cfg "$schema.json"
                if (Test-Path $cfgFile) {
                    $cfgFiles += $cfgFile
                }
            }
            
            # Zusätzlich alle JSON-Dateien im Config-Verzeichnis hinzufügen
            Get-ChildItem $p.cfg -Filter "*.json" | % {
                if (!($cfgFiles -contains $_.FullName)) {
                    $cfgFiles += $_.FullName
                }
            }
            
            return $cfgFiles
        } catch {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Fehler beim Abrufen der Konfigurationsdateien" $_ "Warning"
            } else {
                Log "Fehler beim Abrufen der Konfigurationsdateien: $_" "Warning"
            }
            # Fallback auf direkte Methode
        }
    }
    
    # Direkte Methode: Alle JSON-Dateien im Config-Verzeichnis
    if (Test-Path $p.cfg) {
        return Get-ChildItem $p.cfg -Filter "*.json" | Select-Object -ExpandProperty FullName
    }
    
    return @()
}

# GitIgnore-Regeln parsen
function ParseGI {
    if (!(Test-Path $gitIgnore)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "GitIgnore nicht gefunden: $gitIgnore" -t "Warning"
        } else {
            Log "GitIgnore nicht gefunden: $gitIgnore" "Warning"
        }
        return @()
    }

    $rules = @()
    
    if (Get-Command SafeOp -EA SilentlyContinue) {
        $content = SafeOp {
            Get-Content $gitIgnore
        } -m "GitIgnore konnte nicht gelesen werden" -def @()
        
        $content | ? { ![string]::IsNullOrWhiteSpace($_) -and !$_.StartsWith('#') } | % {
            if ($_.StartsWith('!')) {
                # Negation (Einschluss)
                $rules += @{Rule = $_.Substring(1).Trim(); Include = $true}
            } else {
                # Standard (Ausschluss)
                $rules += @{Rule = $_.Trim(); Include = $false}
            }
        }
    } else {
        try {
            Get-Content $gitIgnore | ? { ![string]::IsNullOrWhiteSpace($_) -and !$_.StartsWith('#') } | % {
                if ($_.StartsWith('!')) {
                    # Negation (Einschluss)
                    $rules += @{Rule = $_.Substring(1).Trim(); Include = $true}
                } else {
                    # Standard (Ausschluss)
                    $rules += @{Rule = $_.Trim(); Include = $false}
                }
            }
        } catch {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Fehler beim Lesen der GitIgnore" $_ "Warning"
            } else {
                Log "Fehler beim Lesen der GitIgnore: $_" "Warning"
            }
        }
    }
    
    return $rules
}

# Test, ob Pfad auf Basis der GitIgnore-Regeln ignoriert werden soll
function ShouldSkip($path, $rules) {
    # Relativen Pfad bestimmen
    $relPath = $path.Replace($p.root, "").TrimStart("\")
    
    # Standardmäßig nicht ignorieren
    $skip = $false
    
    foreach ($rule in $rules) {
        $pattern = $rule.Rule
        $include = $rule.Include
        
        # Effizientere Struktur mit Switch
        switch -Regex ($pattern) {
            '.*\/\*\*$' { # Endet mit /**
                $dirPath = $pattern.Substring(0, $pattern.Length - 3)
                if ($relPath.StartsWith($dirPath) -or $relPath -eq $dirPath.TrimEnd('/')) { 
                    $skip = !$include
                    return $skip
                }
            }
            '\/$' { # Endet mit /
                $dirPath = $pattern.TrimEnd("/")
                if ($relPath.StartsWith("$dirPath\") -or $relPath -eq $dirPath) { 
                    $skip = !$include
                    return $skip
                }
            }
            '\/\*$' { # Endet mit /*
                $dirPath = $pattern.Substring(0, $pattern.Length - 2)
                $parent = Split-Path -Parent $relPath
                if ($parent -eq $dirPath.TrimEnd('/')) { 
                    $skip = !$include
                    return $skip
                }
            }
            '\*' { # Enthält *
                $regex = "^" + [regex]::Escape($pattern).Replace("\*", ".*") + "$"
                if ($relPath -match $regex) { 
                    $skip = !$include
                    return $skip
                }
            }
            default { # Exakte Übereinstimmung
                if ($relPath -eq $pattern -or $relPath.StartsWith("$pattern\")) { 
                    $skip = !$include
                    return $skip
                }
            }
        }
    }
    
    return $skip
}

# Backup erstellen
function BkpCreate {
    # Admin-Rechte für Backup-Operationen empfehlen
    if (!$hasAdminRights -and $useAdminMod -and (Get-Command RequireAdmin -EA SilentlyContinue)) {
        RequireAdmin -message "Für vollständige Backup-Operationen werden Administratorrechte empfohlen."
        # Nach RequireAdmin Aufruf nochmals prüfen
        $hasAdminRights = IsAdmin
    }
    
    Log "Backup wird vorbereitet..."
    
    # Zeitstempel für Backup-Verzeichnis
    $ts = Get-Date -Format "yyyy-MM-dd-HH-mm"
    $bkpName = "backup-$ts"
    $curBkpPath = Join-Path $p.backups $bkpName
    
    # Temp-Verzeichnis prüfen/erstellen
    if (!(Test-Path $p.temp)) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                md $p.temp -Force >$null
            } -m "Temp-Verzeichnis konnte nicht erstellt werden" -t "Error"
        } else {
            try {
                md $p.temp -Force >$null
                Log "Temp-Verzeichnis erstellt: $($p.temp)"
            } catch {
                Log "Fehler beim Erstellen des Temp-Verzeichnisses: $_" "Error"
                return
            }
        }
    }
    
    # Backups-Verzeichnis prüfen/erstellen
    if (!(Test-Path $p.backups)) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                md $p.backups -Force >$null
            } -m "Backup-Verzeichnis konnte nicht erstellt werden" -t "Error"
        } else {
            try {
                md $p.backups -Force >$null
                Log "Backups-Verzeichnis erstellt: $($p.backups)"
            } catch {
                Log "Fehler beim Erstellen des Backup-Verzeichnisses: $_" "Error"
                return
            }
        }
    }
    
    # Backup-Verzeichnis erstellen
    if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            md $curBkpPath -Force >$null
        } -m "Aktuelles Backup-Verzeichnis konnte nicht erstellt werden" -t "Error"
    } else {
        try {
            md $curBkpPath -Force >$null
            Log "Backup-Verzeichnis erstellt: $curBkpPath"
        } catch {
            Log "Fehler beim Erstellen des aktuellen Backup-Verzeichnisses: $_" "Error"
            return
        }
    }
    
    # GitIgnore-Regeln laden
    $rules = ParseGI
    Log "GitIgnore-Regeln geladen: $($rules.Count) Einträge"
    
    # Konfigurationsverzeichnis speziell behandeln
    $cfgFiles = GetConfigFiles
    $cfgBkpPath = Join-Path $curBkpPath "config"
    
    if ($cfgFiles.Count -gt 0) {
        # Konfigurationsverzeichnis im Backup erstellen
        if (!(Test-Path $cfgBkpPath)) {
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    md $cfgBkpPath -Force >$null
                } -m "Konfigurations-Backup-Verzeichnis konnte nicht erstellt werden" -t "Warning"
            } else {
                try {
                    md $cfgBkpPath -Force >$null
                } catch {
                    Log "Fehler beim Erstellen des Konfigurations-Backup-Verzeichnisses: $_" "Error"
                }
            }
        }
        
        # Konfigurationsdateien kopieren
        foreach ($cfgFile in $cfgFiles) {
            $fileName = Split-Path -Leaf $cfgFile
            $destPath = Join-Path $cfgBkpPath $fileName
            
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    Copy-Item -Path $cfgFile -Destination $destPath -Force
                } -m "Konfigurationsdatei konnte nicht gesichert werden: $fileName" -t "Warning"
            } else {
                try {
                    Copy-Item -Path $cfgFile -Destination $destPath -Force
                    Log "Konfigurationsdatei gesichert: $fileName" "Info"
                } catch {
                    Log "Fehler beim Sichern der Konfigurationsdatei: $fileName - $_" "Error"
                }
            }
        }
        
        Log "Konfigurationen gesichert: $($cfgFiles.Count) Dateien" "Info"
    }
    
    # Alle Dateien und Verzeichnisse im Root-Verzeichnis
    $allItems = if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            Get-ChildItem $p.root -Recurse -File
        } -m "Dateien konnten nicht aufgelistet werden" -def @()
    } else {
        try {
            Get-ChildItem $p.root -Recurse -File
        } catch {
            Log "Fehler beim Auflisten der Dateien: $_" "Error"
            return
        }
    }
    
    # Zu sichernde Dateien ermitteln
    $bkpItems = $allItems | ? {
        # Backup-Verzeichnis selbst ausschließen
        if ($_.FullName.StartsWith($p.backups) -or $_.FullName.StartsWith("$($p.temp)\backups")) { return $false }
        # Konfigurationsverzeichnis ausschließen (wird separat behandelt)
        if ($_.FullName.StartsWith($p.cfg)) { return $false }
        # Nach GitIgnore-Regeln filtern
        return !(ShouldSkip $_.FullName $rules)
    }
    
    $totFiles = $bkpItems.Count + $cfgFiles.Count
    Log "Zu sichernde Dateien: $totFiles"
    
    # Fortschrittsanzeige vorbereiten
    $progress = $cfgFiles.Count  # Bereits gesicherte Konfig-Dateien zählen
    $act = "Backup erstellen"
    
    foreach ($item in $bkpItems) {
        # Relativen Pfad bestimmen
        $relPath = $item.FullName.Replace($p.root, "").TrimStart("\")
        $tgtPath = Join-Path $curBkpPath $relPath
        
        # Zielverzeichnis erstellen
        $tgtDir = Split-Path -Parent $tgtPath
        if (!(Test-Path $tgtDir)) {
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    md $tgtDir -Force >$null
                } -m "Zielverzeichnis konnte nicht erstellt werden: $tgtDir" -t "Warning"
            } else {
                try {
                    md $tgtDir -Force >$null
                } catch {
                    Log "Fehler beim Erstellen des Zielverzeichnisses: $_" "Error"
                    continue
                }
            }
        }
        
        # Datei kopieren
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                Copy-Item -Path $item.FullName -Destination $tgtPath -Force
            } -m "Datei konnte nicht kopiert werden: $relPath" -t "Warning"
        } else {
            try {
                Copy-Item -Path $item.FullName -Destination $tgtPath -Force
            } catch {
                Log "Fehler beim Kopieren: $relPath - $_" "Error"
            }
        }
        
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
    Write-Host "Davon Konfigurationsdateien: $($cfgFiles.Count)" -ForegroundColor Cyan
    
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
        if (Get-Command SafeOp -EA SilentlyContinue) {
            $result = SafeOp {
                SMenu -t "Backup-Manager" -m "Admin-Modus" -opts $opts -back -exit
            } -m "Menü konnte nicht angezeigt werden" -def "B"
        } else {
            $result = SMenu -t "Backup-Manager" -m "Admin-Modus" -opts $opts -back -exit
        }
        
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
        foreach ($k in ($opts.Keys | Sort-Object)) {
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
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    & $opts[$ch].Action
                } -m "Aktion konnte nicht ausgeführt werden" -t "Warning"
            } else {
                try {
                    & $opts[$ch].Action
                } catch {
                    Log "Fehler bei der Ausführung: $_" "Error"
                    Start-Sleep -Seconds 2
                    BkpMenu
                }
            }
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

# Backup-Verwaltung
function BkpManage {
    # Prüfen auf vorhandene Backups
    if (!(Test-Path $p.backups)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Keine Backups gefunden" -t "Warning"
        } else {
            Log "Keine Backups gefunden" "Warning"
        }
        
        Write-Host "`nEs wurden keine Backups gefunden." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpMenu
        return
    }
    
    # Verfügbare Backups suchen
    $bkps = if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            Get-ChildItem $p.backups -Directory | ? { $_.Name -match "^backup-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$" } | Sort-Object Name -Descending
        } -m "Backups konnten nicht aufgelistet werden" -def @()
    } else {
        try {
            Get-ChildItem $p.backups -Directory | ? { $_.Name -match "^backup-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$" } | Sort-Object Name -Descending
        } catch {
            Log "Fehler beim Auflisten der Backups: $_" "Error"
            return
        }
    }
    
    if ($bkps.Count -eq 0) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Keine Backups gefunden" -t "Warning"
        } else {
            Log "Keine Backups gefunden" "Warning"
        }
        
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
        
        $fileInfo = if (Get-Command SafeOp -EA SilentlyContinue) {
            $files = SafeOp {
                (Get-ChildItem $b.FullName -Recurse -File)
            } -m "Dateien konnten nicht aufgelistet werden" -def @()
            
            $count = $files.Count
            $size = "{0:N2} MB" -f ((($files | Measure-Object -Property Length -Sum).Sum) / 1MB)
            @{Count = $count; Size = $size}
        } else {
            try {
                $files = Get-ChildItem $b.FullName -Recurse -File
                $count = $files.Count
                $size = "{0:N2} MB" -f ((($files | Measure-Object -Property Length -Sum).Sum) / 1MB)
                @{Count = $count; Size = $size}
            } catch {
                Log "Fehler beim Berechnen der Backup-Größe: $_" "Warning"
                @{Count = 0; Size = "0.00 MB"}
            }
        }
        
        # Prüfen, ob Konfigurationsdateien enthalten sind
        $cfgPath = Join-Path $b.FullName "config"
        $hasCfg = Test-Path $cfgPath
        $cfgInfo = if ($hasCfg) { " (enthält Konfigurationen)" } else { "" }
        
        Write-Host "  $($i+1). $date - $($fileInfo.Count) Dateien - $($fileInfo.Size)$cfgInfo"
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
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Lösche alle Backups" -t "Warning"
            } else {
                Log "Lösche alle Backups" "Warning"
            }
            
            foreach ($b in $bkps) {
                if (Get-Command SafeOp -EA SilentlyContinue) {
                    SafeOp {
                        Remove-Item $b.FullName -Recurse -Force
                    } -m "Backup konnte nicht gelöscht werden: $($b.Name)" -t "Error"
                    
                    if (Get-Command Err -EA SilentlyContinue) {
                        Err "Backup gelöscht: $($b.Name)" -t "Info"
                    } else {
                        Log "Backup gelöscht: $($b.Name)" "Info"
                    }
                } else {
                    try {
                        Remove-Item $b.FullName -Recurse -Force
                        Log "Backup gelöscht: $($b.Name)" "Info"
                    } catch {
                        Log "Fehler beim Löschen des Backups: $($b.Name) - $_" "Error"
                    }
                }
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
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Ungültige Eingabe: $ch" -t "Warning"
        } else {
            Log "Ungültige Eingabe: $ch" "Warning"
        }
        
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
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Ungültiger Index: $idx" -t "Warning"
        } else {
            Log "Ungültiger Index: $idx" "Warning"
        }
        
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
    
    # Prüfen, ob Konfigurationsdateien enthalten sind
    $cfgPath = Join-Path $selBkp.FullName "config"
    $hasCfg = Test-Path $cfgPath
    $cfgInfo = if ($hasCfg) { " (enthält Konfigurationen)" } else { "" }
    
    Write-Host "`nSie haben folgendes Backup ausgewählt:"
    Write-Host "Datum: $bkpDate" -ForegroundColor Cyan
    Write-Host "Pfad: $($selBkp.FullName)$cfgInfo" -ForegroundColor Cyan
    
    Write-Host "`nMöchten Sie dieses Backup löschen?" -ForegroundColor Yellow
    $conf = Read-Host "Bestätigen Sie mit 'j'"
    
    if ($conf -eq "j") {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Lösche Backup: $($selBkp.Name)" -t "Warning"
        } else {
            Log "Lösche Backup: $($selBkp.Name)" "Warning"
        }
        
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                Remove-Item $selBkp.FullName -Recurse -Force
            } -m "Backup konnte nicht gelöscht werden: $($selBkp.Name)" -t "Error"
        } else {
            try {
                Remove-Item $selBkp.FullName -Recurse -Force
            } catch {
                Log "Fehler beim Löschen des Backups: $_" "Error"
            }
        }
        
        Write-Host "`nBackup wurde gelöscht." -ForegroundColor Green
    } else {
        Write-Host "`nLöschung abgebrochen." -ForegroundColor Yellow
    }
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    BkpMenu
}

# Backup wiederherstellen
function BkpRestore {
    # Prüfen auf vorhandene Backups
    if (!(Test-Path $p.backups)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Keine Backups gefunden" -t "Warning"
        } else {
            Log "Keine Backups gefunden" "Warning"
        }
        
        Write-Host "`nEs wurden keine Backups gefunden.`nErstellen Sie zuerst ein Backup." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpMenu
        return
    }
    
    # Verfügbare Backups suchen
    $bkps = if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            Get-ChildItem $p.backups -Directory | ? { $_.Name -match "^backup-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$" } | Sort-Object Name -Descending
        } -m "Backups konnten nicht aufgelistet werden" -def @()
    } else {
        try {
            Get-ChildItem $p.backups -Directory | ? { $_.Name -match "^backup-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}$" } | Sort-Object Name -Descending
        } catch {
            Log "Fehler beim Auflisten der Backups: $_" "Error"
            return
        }
    }
    
    if ($bkps.Count -eq 0) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Keine Backups gefunden" -t "Warning"
        } else {
            Log "Keine Backups gefunden" "Warning"
        }
        
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
        
        $files = if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                (Get-ChildItem $b.FullName -Recurse -File).Count
            } -m "Dateien konnten nicht gezählt werden" -def 0
        } else {
            try {
                (Get-ChildItem $b.FullName -Recurse -File).Count
            } catch {
                Log "Fehler beim Zählen der Dateien: $_" "Warning"
                0
            }
        }
        
        # Prüfen, ob Konfigurationsdateien enthalten sind
        $cfgPath = Join-Path $b.FullName "config"
        $hasCfg = Test-Path $cfgPath
        $cfgInfo = if ($hasCfg) { " (enthält Konfigurationen)" } else { "" }
        
        Write-Host "  $($i+1). $date - $files Dateien$cfgInfo"
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
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Ungültige Eingabe: $ch" -t "Warning"
        } else {
            Log "Ungültige Eingabe: $ch" "Warning"
        }
        
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
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Ungültiger Index: $idx" -t "Warning"
        } else {
            Log "Ungültiger Index: $idx" "Warning"
        }
        
        Write-Host "`nUngültige Auswahl. Bitte wählen Sie eine Zahl zwischen 1 und $($bkps.Count)." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpRestore
        return
    }
    
    # Ausgewähltes Backup
    $selBkp = $bkps[$idx]
    $bkpDate = $selBkp.Name.Substring(7)
    $cfgPath = Join-Path $selBkp.FullName "config"
    $hasCfg = Test-Path $cfgPath
    
    # Optionen für Wiederherstellung
    cls
    if ($hasUX) {
        Title "Wiederherstellungsoptionen" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|       Wiederherstellungsoptionen             |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    Write-Host "`nGewähltes Backup: $bkpDate" -ForegroundColor Cyan
    Write-Host "Pfad: $($selBkp.FullName)" -ForegroundColor Cyan
    
    Write-Host "`nWas möchten Sie wiederherstellen?" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    1       [option]    Alles wiederherstellen"
    
    if ($hasCfg) {
        Write-Host "    2       [option]    Nur Dateien (ohne Konfigurationen)"
        Write-Host "    3       [option]    Nur Konfigurationen"
    }
    
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    
    $restoreOpt = Read-Host "`nOption wählen"
    
    if ($restoreOpt -match "^[Bb]$") {
        BkpRestore
        return
    }
    
    # Option validieren
    if (!($restoreOpt -match "^[1-3]$") -or ($restoreOpt -match "^[2-3]$" -and !$hasCfg)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Ungültige Option: $restoreOpt" -t "Warning"
        } else {
            Log "Ungültige Option: $restoreOpt" "Warning"
        }
        
        Write-Host "`nUngültige Option." -ForegroundColor Red
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpRestore
        return
    }
    
    # Bestätigung
    Write-Host "`nSind Sie sicher, dass Sie die Wiederherstellung durchführen möchten?" -ForegroundColor Red
    Write-Host "Diese Aktion kann vorhandene Dateien überschreiben!" -ForegroundColor Red
    $confirm = Read-Host "`nBitte bestätigen Sie mit 'j'"
    
    if ($confirm -ne "j") {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Wiederherstellung abgebrochen" -t "Warning"
        } else {
            Log "Wiederherstellung abgebrochen" "Warning"
        }
        
        Write-Host "`nWiederherstellung abgebrochen." -ForegroundColor Yellow
        
        # Pause
        Write-Host "`nTaste drücken für Menü..."
        [Console]::ReadKey($true) >$null
        BkpMenu
        return
    }
    
    # Wiederherstellung durchführen
    Log "Beginne Wiederherstellung von: $($selBkp.FullName)" "Info"
    
    # Wiederherstellung basierend auf Option
    $restoreFiles = $restoreOpt -eq "1" -or $restoreOpt -eq "2"
    $restoreConfig = $restoreOpt -eq "1" -or $restoreOpt -eq "3"
    
    # Konfigurationen wiederherstellen
    if ($restoreConfig -and $hasCfg) {
        # Konfigurationsverzeichnis prüfen/erstellen
        if (!(Test-Path $p.cfg)) {
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    md $p.cfg -Force >$null
                } -m "Konfigurationsverzeichnis konnte nicht erstellt werden" -t "Error"
            } else {
                try {
                    md $p.cfg -Force >$null
                } catch {
                    Log "Fehler beim Erstellen des Konfigurationsverzeichnisses: $_" "Error"
                }
            }
        }
        
        # Alle Konfigurationsdateien kopieren
        $cfgFiles = if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                Get-ChildItem $cfgPath -File -Filter "*.json"
            } -m "Konfigurationsdateien konnten nicht aufgelistet werden" -def @()
        } else {
            try {
                Get-ChildItem $cfgPath -File -Filter "*.json"
            } catch {
                Log "Fehler beim Auflisten der Konfigurationsdateien: $_" "Error"
                @()
            }
        }
        
        foreach ($cfgFile in $cfgFiles) {
            $targetPath = Join-Path $p.cfg $cfgFile.Name
            
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    Copy-Item -Path $cfgFile.FullName -Destination $targetPath -Force
                } -m "Konfigurationsdatei konnte nicht wiederhergestellt werden: $($cfgFile.Name)" -t "Warning"
            } else {
                try {
                    Copy-Item -Path $cfgFile.FullName -Destination $targetPath -Force
                    Log "Konfigurationsdatei wiederhergestellt: $($cfgFile.Name)" "Info"
                } catch {
                    Log "Fehler beim Wiederherstellen der Konfigurationsdatei: $($cfgFile.Name) - $_" "Error"
                }
            }
        }
        
        Log "Konfigurationen wiederhergestellt: $($cfgFiles.Count) Dateien" "Info"
    }
    
    # Dateien wiederherstellen
    if ($restoreFiles) {
        # Alle Dateien im Backup (außer config)
        $bkpFiles = if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                Get-ChildItem $selBkp.FullName -Recurse -File | ? { 
                    !$_.FullName.StartsWith($cfgPath)
                }
            } -m "Backup-Dateien konnten nicht aufgelistet werden" -def @()
        } else {
            try {
                Get-ChildItem $selBkp.FullName -Recurse -File | ? { 
                    !$_.FullName.StartsWith($cfgPath)
                }
            } catch {
                Log "Fehler beim Auflisten der Backup-Dateien: $_" "Error"
                @()
            }
        }
        
        $totFiles = $bkpFiles.Count
        $progress = 0
        $act = "Backup wiederherstellen"
        
        foreach ($file in $bkpFiles) {
            # Relativen Pfad im Backup bestimmen
            $relPath = $file.FullName.Replace($selBkp.FullName, "").TrimStart("\")
            $tgtPath = Join-Path $p.root $relPath
            
            # Zielverzeichnis erstellen
            $tgtDir = Split-Path -Parent $tgtPath
            if (!(Test-Path $tgtDir)) {
                if (Get-Command SafeOp -EA SilentlyContinue) {
                    SafeOp {
                        md $tgtDir -Force >$null
                    } -m "Zielverzeichnis konnte nicht erstellt werden: $tgtDir" -t "Warning"
                } else {
                    try {
                        md $tgtDir -Force >$null
                    } catch {
                        Log "Fehler beim Erstellen des Zielverzeichnisses: $_" "Error"
                        continue
                    }
                }
            }
            
            # Datei kopieren
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    Copy-Item -Path $file.FullName -Destination $tgtPath -Force
                } -m "Datei konnte nicht wiederhergestellt werden: $relPath" -t "Warning"
            } else {
                try {
                    Copy-Item -Path $file.FullName -Destination $tgtPath -Force
                } catch {
                    Log "Fehler beim Wiederherstellen: $relPath - $_" "Error"
                }
            }
            
            # Fortschritt anzeigen
            $progress++
            $percent = [math]::Round(($progress / $totFiles) * 100)
            Write-Progress -Activity $act -Status "$percent% abgeschlossen" -PercentComplete $percent -CurrentOperation $relPath
        }
        
        Write-Progress -Activity $act -Completed
    }
    
    # Erfolgsmeldung
    Log "Wiederherstellung abgeschlossen" "Info"
    Write-Host "`nWiederherstellung wurde erfolgreich abgeschlossen!" -ForegroundColor Green
    
    if ($restoreFiles) {
        Write-Host "Wiederhergestellte Dateien: $($bkpFiles.Count)" -ForegroundColor Cyan
    }
    
    if ($restoreConfig -and $hasCfg) {
        Write-Host "Wiederhergestellte Konfigurationen: $($cfgFiles.Count)" -ForegroundColor Cyan
    }
    
    # Pause
    Write-Host "`nTaste drücken für Menü..."
    [Console]::ReadKey($true) >$null
    BkpMenu
}