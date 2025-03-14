# PiM-Manager Codierungsstandard für neue Skripte

## 1. Grundstruktur neuer Skripte

```powershell
# script-name.ps1 - Kurzbeschreibung der Funktionalität
# DisplayName: Anzeigename im Menü

# 1. Pfadberechnung
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)  # Anpassen je nach Position
$cfgPath = "$root\config"
$tempPath = "$root\temp"

# 2. Fehlermodul laden
$errMod = "$root\modules\error.psm1"
if (Test-Path $errMod) {
    try { Import-Module $errMod -Force -EA Stop }
    catch { Write-Host "Fehlermodul konnte nicht geladen werden: $_" -ForegroundColor Red }
}

# 3. UX-Modul laden
$uxMod = "$root\modules\ux.psm1"
if (Test-Path $uxMod) {
    if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            Import-Module $uxMod -Force -EA Stop
        } -m "UX-Modul konnte nicht geladen werden" -t "Warning"
    } else {
        try { Import-Module $uxMod -Force -EA Stop }
        catch { Write-Host "UX-Fehler: $_" -ForegroundColor Red }
    }
}

# 4. Logging-Funktion (falls separat benötigt)
function Log($m, $t = "Info") {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $s = Split-Path -Leaf $PSCommandPath
    $l = "[$ts] [$s] [$t] $m"
    
    switch ($t) {
        "Error" { Write-Host $l -ForegroundColor Red }
        "Warning" { Write-Host $l -ForegroundColor Yellow }
        default { Write-Host $l -ForegroundColor Gray }
    }
}

# 5. Hauptfunktionen implementieren
function Operation1 {
    # SafeOp für kritische Operationen verwenden
    if (Get-Command SafeOp -EA SilentlyContinue) {
        $result = SafeOp {
            # Kritische Operation
            Get-Content "$cfgPath\settings.json" -Raw | ConvertFrom-Json
        } -m "Konfiguration konnte nicht geladen werden" -def @{}
    } else {
        try {
            # Fallback ohne SafeOp
            $result = Get-Content "$cfgPath\settings.json" -Raw | ConvertFrom-Json
        } catch {
            Log "Fehler beim Laden der Konfiguration: $_" "Error"
            $result = @{}
        }
    }
    
    # Weitere Operationen...
}

# 6. Menüsystem implementieren
function Menu {
    $hasUX = Get-Command SMenu -EA SilentlyContinue
    
    $opts = @{
        "1" = @{
            Display = "[option]    Option 1"
            Action = { Operation1; Menu }
        }
        # Weitere Optionen...
    }
    
    # SMenu verwenden falls verfügbar
    if ($hasUX) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            $result = SafeOp {
                SMenu -t "Skript-Titel" -m "Admin-Modus" -opts $opts -back -exit
            } -m "Menü konnte nicht angezeigt werden" -def "B"
        } else {
            $result = SMenu -t "Skript-Titel" -m "Admin-Modus" -opts $opts -back -exit
        }
        
        if ($result -eq "B") { return }
    } else {
        # Fallback für fehlendes UX-Modul
        # Standardmenü-Implementierung...
    }
}

# 7. Skript starten
Log "Skript gestartet" "Info"
Menu
Log "Skript beendet" "Info"
```

## 2. Richtlinien für Fehlerbehandlung

1. **Modulimport**: 
   - Immer zuerst das Fehlermodul laden
   - Fehlermodul-Verfügbarkeit prüfen und Fallback einbauen

2. **Kritische Operationen absichern**:
   - `SafeOp` für alle kritischen Operationen verwenden
   - Immer sinnvolle Defaultwerte bei Fehlern zurückgeben

3. **Dateizugriffe**:
   - Vor Zugriff immer `Test-Path` verwenden
   - Bei Dateioperationen Verzeichnisexistenz prüfen und ggf. erstellen
   - Bei Dateiaktualisierungen Locks durch `IO.File::Open` prüfen

4. **Konfigurationsmanagement**:
   - Immer Fallback-Konfiguration bereithalten
   - Bei fehlenden Konfigurationen sinnvolle Standardwerte verwenden
   - JSON-Konvertierungen immer mit Fehlerbehandlung

5. **UI-Operationen**:
   - Menu-Funktionen mit Fehlerbehandlung versehen
   - Bei fehlenden UX-Modulen immer Fallback-Implementierung bieten

## 3. Standardisierte Fehlertypen und Nachrichten

| Fehlertyp | Verwendungsfall | Standardaktion |
|-----------|----------------|----------------|
| `Info` | Normaler Ablauf, Information für Logs | Weiterlaufen |
| `Warning` | Problem, aber nicht kritisch | Weiterlaufen mit Alternativlösung |
| `Error` | Problem, das Teilfunktionalität blockiert | Teiloperation abbrechen, Rest fortsetzen |
| `Fatal` | Schwerwiegendes Problem | Skript beenden |

## 4. Pfadverarbeitung

```powershell
# Absolute vs. relative Pfade
$absPath = Join-Path $root "config\settings.json"  # Bevorzugt (plattformübergreifend)
$relPath = "$root\config\settings.json"            # Alternative

# Verzeichnisse erstellen vor Zugriff
if (!(Test-Path $dir)) {
    if (Get-Command SafeOp -EA SilentlyContinue) {
        SafeOp {
            md $dir -Force >$null
        } -m "Verzeichnis konnte nicht erstellt werden: $dir" -t "Warning"
    } else {
        try { md $dir -Force >$null }
        catch { Log "Fehler: $_" "Error" }
    }
}

# Sonderzeichen in Pfaden beachten
$safePath = [System.IO.Path]::Combine($root, "file with spaces.txt")
```

## 5. Konfigurationsmanagement

```powershell
# Konfiguration laden
function LoadCfg($path) {
    # Existenz prüfen
    if (!(Test-Path $path)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Konfigurationsdatei nicht gefunden: $path" -t "Warning"
        } else {
            Log "Konfigurationsdatei nicht gefunden: $path" "Warning"
        }
        return @{}  # Leere Konfiguration zurückgeben
    }
    
    # Mit Fehlerbehandlung laden
    if (Get-Command SafeOp -EA SilentlyContinue) {
        return SafeOp {
            Get-Content $path -Raw | ConvertFrom-Json
        } -m "Konfiguration konnte nicht geladen werden" -def @{}
    } else {
        try {
            return Get-Content $path -Raw | ConvertFrom-Json
        } catch {
            Log "Fehler beim Laden der Konfiguration: $_" "Error"
            return @{}
        }
    }
}

# Konfiguration speichern
function SaveCfg($cfg, $path) {
    # Verzeichnis prüfen/erstellen
    $dir = Split-Path -Parent $path
    if (!(Test-Path $dir)) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                md $dir -Force >$null
            } -m "Verzeichnis konnte nicht erstellt werden" -t "Warning"
        } else {
            try { md $dir -Force >$null }
            catch { Log "Fehler: $_" "Error"; return $false }
        }
    }
    
    # Mit Fehlerbehandlung speichern
    if (Get-Command SafeOp -EA SilentlyContinue) {
        return SafeOp {
            $cfg | ConvertTo-Json -Depth 4 | Set-Content $path
            return $true
        } -m "Konfiguration konnte nicht gespeichert werden" -def $false
    } else {
        try {
            $cfg | ConvertTo-Json -Depth 4 | Set-Content $path
            return $true
        } catch {
            Log "Fehler beim Speichern der Konfiguration: $_" "Error"
            return $false
        }
    }
}
```

## 6. Tokenoptimierung

1. **Variablennamen kürzen**:
   - `$message` → `$m`
   - `$timestamp` → `$ts`
   - `$configFile` → `$f`

2. **Operatoren statt Cmdlets**:
   - `>>` statt `Out-File -Append`
   - `>$null` statt `Out-Null`

3. **Eingebaute Abkürzungen nutzen**:
   - `-EA` statt `-ErrorAction`
   - `?` statt `Where-Object`
   - `%` statt `ForEach-Object`

4. **Kompakte Bedingungen**:
   - Ternärer Operator: `$val = $cond ? $true : $false` 
   - Boolesche Kurzformen: `$var = $x -or $default`

5. **Parameterlisten optimieren**:
   - Standardwerte direkt setzen: `$p = $p ?? "default"`
   - Positionsparameter wo sinnvoll

## 7. Best Practices für neue Skripte

1. **Modulares Design**:
   - Funktionen mit einer klaren Aufgabe
   - Wiederverwendbaren Code in Funktionen auslagern

2. **Konsistente Benennungen**:
   - Funktionen: Verb-Substantiv (z.B. `Get-Config`, `Save-Settings`)
   - Variablen: Aussagekräftige Namen, camelCase für temporäre Variablen

3. **Kommentare**:
   - Funktionsköpfe kommentieren (Eingabe, Ausgabe, Zweck)
   - Komplexe Logik erklären
   - Keine offensichtlichen Dinge kommentieren

4. **Fortschrittsanzeigen**:
   - `Write-Progress` für längere Operationen
   - Prozentangaben und Status stets aktualisieren

5. **Rückgabewerte**:
   - Funktionen sollten sinnvolle Rückgabewerte haben
   - Bei Fehlern stets einen Standardwert zurückgeben

6. **Parametriesierung**:
   - Wichtige Werte als Parameter definieren
   - Standardwerte für optionale Parameter