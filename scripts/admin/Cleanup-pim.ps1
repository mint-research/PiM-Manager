# cleanup-pim.ps1 - Temp-Dateien bereinigen
# DisplayName: Temporäre Dateien bereinigen

# Pfadmodul laden
$pathsMod = "$PSScriptRoot\..\..\..\modules\paths.psm1"
if (Test-Path $pathsMod) {
    try { 
        Import-Module $pathsMod -Force -EA Stop 
        $p = GetPaths $PSScriptRoot
    } catch {
        # Fallback bei Modulladefehler
        $root = $PSScriptRoot -match "admin\\Cleanup$" ? 
            (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) : 
            (Split-Path -Parent $PSScriptRoot)
        $p = @{
            root = $root
            temp = "$root\temp"
            errMod = "$root\modules\error.psm1"
            uxMod = "$root\modules\ux.psm1"
            cfgMod = "$root\modules\config.psm1"
        }
    }
} else {
    # Fallback ohne Pfadmodul
    $root = $PSScriptRoot -match "admin\\Cleanup$" ? 
        (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) : 
        (Split-Path -Parent $PSScriptRoot)
    $p = @{
        root = $root
        temp = "$root\temp"
        errMod = "$root\modules\error.psm1"
        uxMod = "$root\modules\ux.psm1"
        cfgMod = "$root\modules\config.psm1"
    }
}

$isAdmin = $PSScriptRoot -match "admin\\Cleanup$"

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

# Cleanup-Konfiguration laden/erstellen
function GetCleanupConfig {
    # Bei aktivem Konfigurationsmodul dieses nutzen
    if ($useCfgMod -and (Get-Command GetConfig -EA SilentlyContinue) -and (Get-Command SetSchema -EA SilentlyContinue)) {
        # Cleanup-Schema definieren, falls noch nicht vorhanden
        $schema = GetSchema "cleanup"
        
        if ($schema -eq $null) {
            $schema = @{
                Version = "1.0"
                Type = "Object"
                Properties = @{
                    AutoCleanup = @{
                        Type = "Boolean"
                        Default = $false
                    }
                    MaxAge = @{
                        Type = "Object"
                        Properties = @{
                            Logs = @{
                                Type = "Number"
                                Default = 30  # Tage
                            }
                            Backups = @{
                                Type = "Number"
                                Default = 60  # Tage
                            }
                            Temp = @{
                                Type = "Number"
                                Default = 7   # Tage
                            }
                        }
                        Required = @("Logs", "Backups", "Temp")
                    }
                    PreserveFiles = @{
                        Type = "Array"
                        Default = @("important.log", "backup-current.zip")
                    }
                }
                Required = @("AutoCleanup", "MaxAge")
            }
            
            SetSchema -name "cleanup" -schema $schema
        }
        
        # Konfiguration laden
        return GetConfig -name "cleanup"
    }
    
    # Fallback: Standardkonfiguration
    return [PSCustomObject]@{
        AutoCleanup = $false
        MaxAge = [PSCustomObject]@{
            Logs = 30
            Backups = 60
            Temp = 7
        }
        PreserveFiles = @("important.log", "backup-current.zip")
    }
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
    if (!(Test-Path $p.temp)) { return @() }
    
    if (Get-Command SafeOp -EA SilentlyContinue) {
        return SafeOp {
            Get-ChildItem $p.temp -Directory | Select-Object -ExpandProperty Name
        } -m "Verzeichnisse konnten nicht aufgelistet werden" -def @()
    } else {
        try {
            return Get-ChildItem $p.temp -Directory | Select-Object -ExpandProperty Name
        } catch {
            Log "Fehler beim Auflisten der Verzeichnisse: $_" "Error"
            return @()
        }
    }
}

# Dateitypen auswählen
function SelType {
    $dirs = GetDirs
    
    # Konfiguration laden
    $cfg = GetCleanupConfig
    
    # Wenn keine Verzeichnisse vorhanden sind, aber temp-Verzeichnis existiert
    if ($dirs.Count -eq 0 -and (Test-Path $p.temp)) { 
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Keine Ordner im temp-Verzeichnis" -t "Warning"
        } else {
            Log "Keine Ordner im temp-Verzeichnis" "Warning"
        }
        
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
        $tempDir = Join-Path $p.temp $d
        
        $cnt = if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                (Get-ChildItem $tempDir -Recurse -File -EA SilentlyContinue).Count
            } -m "Dateien konnten nicht gezählt werden" -def 0
        } else {
            try {
                (Get-ChildItem $tempDir -Recurse -File -EA SilentlyContinue).Count
            } catch {
                Log "Fehler beim Zählen der Dateien: $_" "Warning"
                0
            }
        }
        
        # Empfohlene Aufbewahrungszeit anzeigen
        $maxAge = switch ($d) {
            "logs" { $cfg.MaxAge.Logs }
            "backups" { $cfg.MaxAge.Backups }
            default { $cfg.MaxAge.Temp }
        }
        
        Write-Host "    $($i+1)       [folder]    $d - $cnt Dateien (Max. Alter: $maxAge Tage)"
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
    
    # Konfiguration laden
    $cfg = GetCleanupConfig
    
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
    Write-Host "    4       [option]    Älter als bestimmte Anzahl Tage"
    Write-Host "    5       [option]    Empfohlene Einstellungen (aus Konfiguration)"
    Write-Host "    6       [option]    Alle"
    
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
        "4" { 
            Write-Host "`nBitte geben Sie die Anzahl der Tage ein:"
            $days = Read-Host "Tage"
            
            if (!($days -match "^\d+$")) {
                Write-Host "`nUngültige Eingabe. Es wird ein Standardwert von 30 Tagen verwendet." -ForegroundColor Yellow
                $days = 30
            }
            
            return (Get-Date).AddDays(-[int]$days)
        }
        "5" { 
            # Spezielle Option: Map mit Verzeichnis und Alter zurückgeben
            $dirAgeMap = @{}
            
            foreach ($dir in (GetDirs)) {
                $maxAge = switch ($dir) {
                    "logs" { $cfg.MaxAge.Logs }
                    "backups" { $cfg.MaxAge.Backups }
                    default { $cfg.MaxAge.Temp }
                }
                
                $dirAgeMap[$dir] = (Get-Date).AddDays(-$maxAge)
            }
            
            return $dirAgeMap
        }
        "6" { return [DateTime]::MinValue }
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
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Keine Bereinigung durchgeführt" -t "Warning"
        } else {
            Log "Keine Bereinigung durchgeführt" "Warning"
        }
        return
    }
    
    Log "Beginne Bereinigung..." "Info"
    $totFiles = 0
    $totSize = 0
    
    # Konfiguration für zu erhaltende Dateien
    $cfg = GetCleanupConfig
    $preserveFiles = $cfg.PreserveFiles ?? @()
    
    # Direkte Cutoff-Zeit oder Map mit unterschiedlichen Zeiten pro Verzeichnis
    if ($cutoffDate -is [DateTime]) {
        Log "Cutoff-Datum für alle Verzeichnisse: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
        
        # Einzelner Cutoff für alle Verzeichnisse
        foreach ($d in $dirs) {
            CleanDir -d $d -cutoffDate $cutoffDate -preserveFiles $preserveFiles -stats ([ref]$totFiles) -statsSize ([ref]$totSize)
        }
    } else {
        # Map mit unterschiedlichen Cutoff-Zeiten pro Verzeichnis
        Log "Verwende unterschiedliche Cutoff-Daten je nach Verzeichnistyp" "Info"
        
        foreach ($d in $dirs) {
            if ($cutoffDate.ContainsKey($d)) {
                $dirCutoff = $cutoffDate[$d]
                Log "Cutoff-Datum für $d: $($dirCutoff.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
                CleanDir -d $d -cutoffDate $dirCutoff -preserveFiles $preserveFiles -stats ([ref]$totFiles) -statsSize ([ref]$totSize)
            } else {
                Log "Kein Cutoff-Datum für $d definiert, wird übersprungen" "Warning"
            }
        }
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

# Verzeichnis bereinigen
function CleanDir {
    param (
        [Parameter(Mandatory)]
        [string]$d,
        
        [Parameter(Mandatory)]
        [DateTime]$cutoffDate,
        
        [array]$preserveFiles = @(),
        
        [Parameter(Mandatory)]
        [ref]$stats,
        
        [Parameter(Mandatory)]
        [ref]$statsSize
    )
    
    $path = Join-Path $p.temp $d
    
    if (!(Test-Path $path)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Ordner nicht gefunden: $path" -t "Warning"
        } else {
            Log "Ordner nicht gefunden: $path" "Warning"
        }
        return
    }
    
    Log "Prüfe: $d" "Info"
    
    # Dateien auflisten
    $files = if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            Get-ChildItem $path -Recurse -File
        } -m "Dateien konnten nicht aufgelistet werden" -def @()
    } else {
        try {
            Get-ChildItem $path -Recurse -File
        } catch {
            Log "Fehler beim Auflisten der Dateien: $_" "Error"
            return
        }
    }
    
    Log "Dateien: $($files.Count)" "Info"
    
    if ($files.Count -gt 0) {
        $oldest = $files | Sort-Object LastWriteTime | Select-Object -First 1
        $newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        
        Log "Älteste: $($oldest.Name) - $($oldest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
        Log "Neueste: $($newest.Name) - $($newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Info"
    }
    
    # Spezialfall für Backups
    if ($d -eq "backups" -and $cutoffDate -eq [DateTime]::MinValue) {
        $bkpDirs = if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                Get-ChildItem $path -Directory
            } -m "Backup-Ordner konnten nicht aufgelistet werden" -def @()
        } else {
            try {
                Get-ChildItem $path -Directory
            } catch {
                Log "Fehler beim Auflisten der Backup-Ordner: $_" "Error"
                return
            }
        }
        
        $fCount = $files.Count  # Für Bericht
        $fSize = ($files | Measure-Object -Property Length -Sum).Sum
        
        Log "Backup-Ordner: $($bkpDirs.Count)" "Info"
        
        # Fortschritt
        $prog = 0
        $act = "Bereinige Backup-Ordner"
        
        foreach ($bkp in $bkpDirs) {
            try {
                Log "Lösche: $($bkp.FullName)" "Info"
                
                if (Get-Command SafeOp -EA SilentlyContinue) {
                    SafeOp {
                        Remove-Item $bkp.FullName -Recurse -Force
                    } -m "Backup-Ordner konnte nicht gelöscht werden: $($bkp.FullName)" -t "Warning"
                } else {
                    try {
                        Remove-Item $bkp.FullName -Recurse -Force
                    } catch {
                        Log "Fehler: $($bkp.FullName) - $_" "Error"
                    }
                }
                
                # Fortschritt
                $prog++
                $pct = [math]::Round(($prog / $bkpDirs.Count) * 100)
                Write-Progress -Activity $act -Status "$pct% abgeschlossen" -PercentComplete $pct
            } 
            catch {
                if (Get-Command Err -EA SilentlyContinue) {
                    Err "Fehler beim Löschen" $_ "Error"
                } else {
                    Log "Fehler: $($bkp.FullName) - $_" "Error"
                }
            }
        }
        
        Write-Progress -Activity $act -Completed
        $stats.Value += $fCount
        $statsSize.Value += $fSize
    }
    else {
        # Normale Ordner
        $toDel = $cutoffDate -eq [DateTime]::MinValue ?
            $files :
            ($files | ? { 
                # Alter prüfen und zu erhaltende Dateien ausschließen
                $_.LastWriteTime -le $cutoffDate -and 
                !($preserveFiles -contains $_.Name) 
            })
        
        $fCount = $toDel.Count
        Log "Zu löschen: $fCount" "Info"
        
        if ($fCount -eq 0) {
            Log "Keine zu löschenden Dateien in: $d" "Info"
            return
        }
        
        # Größe
        $fSize = ($toDel | Measure-Object -Property Length -Sum).Sum
        $statsSize.Value += $fSize
        
        # Lösch-Fortschritt
        $prog = 0
        $act = "Bereinige $d"
        
        foreach ($f in $toDel) {
            try {
                # Prüfe Dateizugriff
                $skip = $false
                
                if (Get-Command SafeOp -EA SilentlyContinue) {
                    # Versuche Datei zu öffnen, um zu prüfen, ob sie in Benutzung ist
                    $canAccess = SafeOp {
                        $fs = [IO.File]::Open($f.FullName, 
                            [IO.FileMode]::Open, 
                            [IO.FileAccess]::ReadWrite, 
                            [IO.FileShare]::None)
                        $fs.Close()
                        $fs.Dispose()
                        return $true
                    } -m "Datei wird verwendet: $($f.FullName)" -def $false
                    
                    if (!$canAccess) {
                        $skip = $true
                        Log "In Benutzung: $($f.FullName)" "Warning"
                    }
                } else {
                    try {
                        $fs = [IO.File]::Open($f.FullName, 
                               [IO.FileMode]::Open, 
                               [IO.FileAccess]::ReadWrite, 
                               [IO.FileShare]::None)
                        $fs.Close()
                        $fs.Dispose()
                    } catch {
                        $skip = $true
                        Log "In Benutzung: $($f.FullName)" "Warning"
                    }
                }
                
                if (!$skip) {
                    if (Get-Command SafeOp -EA SilentlyContinue) {
                        SafeOp {
                            Remove-Item $f.FullName -Force
                        } -m "Datei konnte nicht gelöscht werden: $($f.FullName)" -t "Warning"
                    } else {
                        Remove-Item $f.FullName -Force
                    }
                    $stats.Value++
                }
                
                # Fortschritt
                $prog++
                $pct = [math]::Round(($prog / $fCount) * 100)
                Write-Progress -Activity $act -Status "$pct% abgeschlossen" -PercentComplete $pct
            }
            catch {
                if (Get-Command Err -EA SilentlyContinue) {
                    Err "Fehler beim Löschen" $_ "Warning"
                } else {
                    Log "Fehler: $($f.FullName) - $_" "Error"
                }
            }
        }
        
        Write-Progress -Activity $act -Completed
        
        # Leere Ordner entfernen
        $emptyDirs = if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                Get-ChildItem $path -Directory -Recurse | 
                ? { 
                    (Get-ChildItem $_.FullName -Recurse -File).Count -eq 0 -and
                    (Get-ChildItem $_.FullName -Directory).Count -eq 0
                }
            } -m "Leere Ordner konnten nicht gefunden werden" -def @()
        } else {
            try {
                Get-ChildItem $path -Directory -Recurse | 
                ? { 
                    (Get-ChildItem $_.FullName -Recurse -File).Count -eq 0 -and
                    (Get-ChildItem $_.FullName -Directory).Count -eq 0
                }
            } catch {
                Log "Fehler beim Suchen leerer Ordner: $_" "Error"
                @()
            }
        }
        
        foreach ($dir in $emptyDirs) {
            try {
                Log "Entferne leeren Ordner: $($dir.FullName)" "Info"
                
                if (Get-Command SafeOp -EA SilentlyContinue) {
                    SafeOp {
                        Remove-Item $dir.FullName -Force
                    } -m "Ordner konnte nicht gelöscht werden: $($dir.FullName)" -t "Warning"
                } else {
                    Remove-Item $dir.FullName -Force
                }
            }
            catch {
                if (Get-Command Err -EA SilentlyContinue) {
                    Err "Fehler beim Löschen des Ordners" $_ "Warning"
                } else {
                    Log "Fehler: $($dir.FullName) - $_" "Error"
                }
            }
        }
    }
    
    # Ausgabe pro Ordner
    $mb = [math]::Round($fSize / 1MB, 2)
    Log "Bereinigt '$d': $fCount Dateien ($mb MB)" "Info"
}

# Statistik anzeigen
function Stats {
    cls
    
    # Konfiguration laden
    $cfg = GetCleanupConfig
    
    if (Get-Command Title -EA SilentlyContinue) {
        Title "Temp-Statistik" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|             Temp-Statistik                   |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    # Temp-Ordner prüfen
    if (!(Test-Path $p.temp)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Temp-Verzeichnis nicht gefunden: $($p.temp)" -t "Warning"
        } else {
            Log "Temp-Verzeichnis nicht gefunden: $($p.temp)" "Warning"
        }
        
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                md $p.temp -Force >$null
            } -m "Temp-Verzeichnis konnte nicht erstellt werden" -t "Warning"
        } else {
            try {
                md $p.temp -Force >$null
                Log "Temp-Verzeichnis erstellt: $($p.temp)" "Info"
            } catch {
                Log "Fehler beim Erstellen des Temp-Verzeichnisses: $_" "Error"
            }
        }
        
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
    
    Write-Host "`nTemp-Verzeichnis-Statistik:" -ForegroundColor Cyan
    Write-Host ""
    
    $stats = @()
    $totalSize = 0
    $totalCount = 0
    
    foreach ($d in $dirs) {
        $path = Join-Path $p.temp $d
        if (!(Test-Path $path)) { continue }
        
        $files = if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                Get-ChildItem $path -Recurse -File
            } -m "Dateien konnten nicht aufgelistet werden" -def @()
        } else {
            try {
                Get-ChildItem $path -Recurse -File
            } catch {
                Log "Fehler beim Auflisten der Dateien: $_" "Error"
                @()
            }
        }
        
        $fileCount = $files.Count
        $totalCount += $fileCount
        
        $size = ($files | Measure-Object -Property Length -Sum).Sum
        $totalSize += $size
        
        $sizeInMB = [math]::Round($size / 1MB, 2)
        
        # Max Age aus Konfiguration
        $maxAge = switch ($d) {
            "logs" { $cfg.MaxAge.Logs }
            "backups" { $cfg.MaxAge.Backups }
            default { $cfg.MaxAge.Temp }
        }
        
        # Anzahl der Dateien, die gelöscht werden könnten
        $cutoffDate = (Get-Date).AddDays(-$maxAge)
        $cleanableFiles = ($files | ? { $_.LastWriteTime -le $cutoffDate }).Count
        $cleanablePct = $fileCount -gt 0 ? [math]::Round(($cleanableFiles / $fileCount) * 100, 0) : 0
        
        $stats += [PSCustomObject]@{
            Dir = $d
            Count = $fileCount
            Size = $sizeInMB
            MaxAge = $maxAge
            Cleanable = $cleanableFiles
            CleanablePct = $cleanablePct
        }
    }
    
    # Sortierte Tabelle anzeigen
    $stats | Sort-Object Size -Descending | % {
        Write-Host "    $($_.Dir.PadRight(15)) $($_.Count.ToString().PadLeft(6)) Dateien    $($_.Size.ToString().PadLeft(8)) MB    $($_.CleanablePct.ToString().PadLeft(3))% löschbar (älter als $($_.MaxAge) Tage)"
    }
    
    # Gesamtsumme
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
    Write-Host "`n    $("GESAMT".PadRight(15)) $($totalCount.ToString().PadLeft(6)) Dateien    $($totalSizeMB.ToString().PadLeft(8)) MB"
    
    # Konfigurationsinfo
    Write-Host "`nKonfiguration:" -ForegroundColor Cyan
    Write-Host "    Automatische Bereinigung: $($cfg.AutoCleanup ? 'Aktiviert' : 'Deaktiviert')"
    Write-Host "    Aufbewahrungszeiten:"
    Write-Host "      - Logs:    $($cfg.MaxAge.Logs) Tage"
    Write-Host "      - Backups: $($cfg.MaxAge.Backups) Tage"
    Write-Host "      - Temp:    $($cfg.MaxAge.Temp) Tage"
    
    # Geschützte Dateien
    if ($cfg.PreserveFiles -and $cfg.PreserveFiles.Count -gt 0) {
        Write-Host "    Geschützte Dateien: $($cfg.PreserveFiles -join ', ')"
    }
    
    # Optionen anzeigen
    Write-Host "`nOptionen:" -ForegroundColor Yellow
    Write-Host "    1       [option]    Konfiguration bearbeiten"
    
    # Navigation
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host ""
    
    $ch = Read-Host "Option wählen"
    
    if ($ch -eq "1" -and $useCfgMod) {
        # Konfiguration bearbeiten
        EditConfig
        Stats
        return
    } else if ($ch -eq "1") {
        Write-Host "`nKonfigurationsmodul nicht verfügbar. Konfiguration kann nicht bearbeitet werden." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        Stats
        return
    }
    
    # Zurück
    return
}

# Konfiguration bearbeiten
function EditConfig {
    if (!$useCfgMod -or !(Get-Command GetConfig -EA SilentlyContinue) -or !(Get-Command SaveConfig -EA SilentlyContinue)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Konfigurationsmodul nicht verfügbar" -t "Warning"
        } else {
            Log "Konfigurationsmodul nicht verfügbar" "Warning"
        }
        return
    }
    
    cls
    
    if (Get-Command Title -EA SilentlyContinue) {
        Title "Cleanup-Konfiguration" "Admin-Modus"
    } else {
        Write-Host "+===============================================+"
        Write-Host "|           Cleanup-Konfiguration              |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
    }
    
    # Aktuelle Konfiguration laden
    $cfg = GetCleanupConfig
    
    Write-Host "`nAktuelle Konfiguration:" -ForegroundColor Cyan
    Write-Host "    1. Automatische Bereinigung: $($cfg.AutoCleanup ? 'Aktiviert' : 'Deaktiviert')"
    Write-Host "    2. Aufbewahrungszeit für Logs:    $($cfg.MaxAge.Logs) Tage"
    Write-Host "    3. Aufbewahrungszeit für Backups: $($cfg.MaxAge.Backups) Tage"
    Write-Host "    4. Aufbewahrungszeit für Temp:    $($cfg.MaxAge.Temp) Tage"
    Write-Host "    5. Geschützte Dateien: $($cfg.PreserveFiles -join ', ')"
    
    Write-Host "`nWas möchten Sie ändern?" -ForegroundColor Yellow
    Write-Host "    6. Zurücksetzen auf Standardwerte"
    
    Write-Host ""
    Write-Host "    B       [back]      Zurück"
    Write-Host ""
    
    $ch = Read-Host "Option wählen"
    
    if ($ch -match "^[Bb]$") {
        return
    }
    
    if ($ch -eq "1") {
        # Automatische Bereinigung umschalten
        $cfg.AutoCleanup = !$cfg.AutoCleanup
        SaveConfig -name "cleanup" -config $cfg
        Write-Host "Automatische Bereinigung: $($cfg.AutoCleanup ? 'Aktiviert' : 'Deaktiviert')" -ForegroundColor Green
        Start-Sleep -Seconds 1
        EditConfig
        return
    }
    
    if ($ch -eq "2") {
        # Logs-Aufbewahrungszeit
        Write-Host "`nAufbewahrungszeit für Logs (Tage):"
        $days = Read-Host "Tage"
        
        if ($days -match "^\d+$" -and [int]$days -ge 1) {
            $cfg.MaxAge.Logs = [int]$days
            SaveConfig -name "cleanup" -config $cfg
            Write-Host "Aufbewahrungszeit für Logs auf $days Tage gesetzt" -ForegroundColor Green
        } else {
            Write-Host "Ungültige Eingabe. Aufbewahrungszeit nicht geändert." -ForegroundColor Red
        }
        
        Start-Sleep -Seconds 1
        EditConfig
        return
    }
    
    if ($ch -eq "3") {
        # Backups-Aufbewahrungszeit
        Write-Host "`nAufbewahrungszeit für Backups (Tage):"
        $days = Read-Host "Tage"
        
        if ($days -match "^\d+$" -and [int]$days -ge 1) {
            $cfg.MaxAge.Backups = [int]$days
            SaveConfig -name "cleanup" -config $cfg
            Write-Host "Aufbewahrungszeit für Backups auf $days Tage gesetzt" -ForegroundColor Green
        } else {
            Write-Host "Ungültige Eingabe. Aufbewahrungszeit nicht geändert." -ForegroundColor Red
        }
        
        Start-Sleep -Seconds 1
        EditConfig
        return
    }
    
    if ($ch -eq "4") {
        # Temp-Aufbewahrungszeit
        Write-Host "`nAufbewahrungszeit für temporäre Dateien (Tage):"
        $days = Read-Host "Tage"
        
        if ($days -match "^\d+$" -and [int]$days -ge 1) {
            $cfg.MaxAge.Temp = [int]$days
            SaveConfig -name "cleanup" -config $cfg
            Write-Host "Aufbewahrungszeit für temporäre Dateien auf $days Tage gesetzt" -ForegroundColor Green
        } else {
            Write-Host "Ungültige Eingabe. Aufbewahrungszeit nicht geändert." -ForegroundColor Red
        }
        
        Start-Sleep -Seconds 1
        EditConfig
        return
    }
    
    if ($ch -eq "5") {
        # Geschützte Dateien
        Write-Host "`nGeschützte Dateien (durch Komma getrennt):"
        Write-Host "Aktuelle Liste: $($cfg.PreserveFiles -join ', ')"
        $files = Read-Host "Neue Liste"
        
        if (![string]::IsNullOrWhiteSpace($files)) {
            $fileList = $files -split ',' | % { $_.Trim() } | ? { ![string]::IsNullOrWhiteSpace($_) }
            $cfg.PreserveFiles = $fileList
            SaveConfig -name "cleanup" -config $cfg
            Write-Host "Liste der geschützten Dateien aktualisiert" -ForegroundColor Green
        } else {
            Write-Host "Ungültige Eingabe. Liste nicht geändert." -ForegroundColor Red
        }
        
        Start-Sleep -Seconds 1
        EditConfig
        return
    }
    
    if ($ch -eq "6") {
        # Standardwerte zurücksetzen
        
        Write-Host "`nSind Sie sicher, dass Sie die Konfiguration zurücksetzen möchten?" -ForegroundColor Yellow
        $confirm = Read-Host "Bestätigen Sie mit 'j'"
        
        if ($confirm -eq "j") {
            # Standardkonfiguration erstellen
            $stdCfg = [PSCustomObject]@{
                AutoCleanup = $false
                MaxAge = [PSCustomObject]@{
                    Logs = 30
                    Backups = 60
                    Temp = 7
                }
                PreserveFiles = @("important.log", "backup-current.zip")
            }
            
            SaveConfig -name "cleanup" -config $stdCfg
            Write-Host "Konfiguration auf Standardwerte zurückgesetzt" -ForegroundColor Green
        } else {
            Write-Host "Zurücksetzen abgebrochen" -ForegroundColor Yellow
        }
        
        Start-Sleep -Seconds 1
        EditConfig
        return
    }
    
    # Ungültige Option
    Write-Host "Ungültige Option" -ForegroundColor Red
    Start-Sleep -Seconds 1
    EditConfig
    return
}

# Automatische Bereinigung
function AutoCleanup {
    # Konfiguration prüfen
    $cfg = GetCleanupConfig
    
    if (!$cfg.AutoCleanup) {
        Log "Automatische Bereinigung ist deaktiviert" "Info"
        return
    }
    
    Log "Starte automatische Bereinigung..." "Info"
    
    # Alle Verzeichnisse bereinigen
    $dirs = GetDirs
    
    if ($dirs.Count -eq 0) {
        Log "Keine Verzeichnisse zum Bereinigen gefunden" "Info"
        return
    }
    
    # Map mit unterschiedlichen Cutoff-Zeiten pro Verzeichnis erstellen
    $dirAgeMap = @{}
    
    foreach ($dir in $dirs) {
        $maxAge = switch ($dir) {
            "logs" { $cfg.MaxAge.Logs }
            "backups" { $cfg.MaxAge.Backups }
            default { $cfg.MaxAge.Temp }
        }
        
        $dirAgeMap[$dir] = (Get-Date).AddDays(-$maxAge)
    }
    
    # Bereinigung durchführen
    Clean -dirs $dirs -cutoffDate $dirAgeMap
}

# Hauptmenü
function Menu {
    # Prüfen auf automatische Bereinigung
    $cfg = GetCleanupConfig
    
    if ($cfg.AutoCleanup) {
        # Automatische Bereinigung durchführen
        AutoCleanup
    }
    
    $hasUX = Get-Command SMenu -EA SilentlyContinue
    
    $opts = @{
        "1" = @{
            Display = "[option]    Dateien bereinigen"
            Action = {
                $types = SelType
                if ($types -ne "B") {
                    $time = SelTime
                    if ($time) {
                        Clean $types $time
                    }
                }
                Menu
            }
        }
        "2" = @{
            Display = "[option]    Statistik anzeigen"
            Action = { 
                Stats
                Menu
            }
        }
    }
    
    if ($useCfgMod) {
        $opts["3"] = @{
            Display = "[option]    Konfiguration bearbeiten"
            Action = {
                EditConfig
                Menu
            }
        }
    }
    
    if ($hasUX) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                SMenu -t "Temp-Bereinigung" -m "Admin-Modus" -opts $opts -back -exit
            } -m "Menü konnte nicht angezeigt werden" -t "Error"
        } else {
            SMenu -t "Temp-Bereinigung" -m "Admin-Modus" -opts $opts -back -exit
        }
    } else {
        # Eigene Menü-Implementierung (Standardmuster)
        cls
        Write-Host "+===============================================+"
        Write-Host "|            Temp-Bereinigung                  |"
        Write-Host "|             (Admin-Modus)                    |"
        Write-Host "+===============================================+"
        
        foreach ($k in ($opts.Keys | Sort-Object)) {
            Write-Host "    $k       $($opts[$k].Display)"
        }
        
        Write-Host ""
        Write-Host "    B       [back]      Zurück"
        Write-Host "    X       [exit]      Beenden"
        
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
                    Menu
                }
            }
        } else {
            Write-Host "Ungültige Option." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Menu
        }
    }
}

# Skriptstart
Log "Cleanup-Tool gestartet" "Info"
Menu
Log "Cleanup-Tool beendet" "Info"